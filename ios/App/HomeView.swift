import SwiftUI
import ReplayKit
import UserNotifications
import DriverCore

struct HomeView: View {
    @State private var status = SharedStore.status
    @State private var history = SharedStore.history
    @State private var notificationsAllowed: Bool?
    @State private var focusConfirmed = UserDefaults.standard.bool(forKey: "focusConfirmed")
    @State private var testSent = false
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var isLive: Bool {
        guard status.running, let last = status.lastFrameAt else { return false }
        return Date().timeIntervalSince(last) < 8
    }

    private var today: [OfferRecord] {
        history.filter { Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusCard
                    if !SharedStore.isShared {
                        Banner(text: "Grupo do app indisponível: a extensão vai usar os ajustes padrão. Reinstale pelo AltStore para compartilhar os ajustes.", color: Palette.warning)
                    }
                    setupCard
                    if !today.isEmpty { todayCard }
                    howItWorks
                }
                .padding(16)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Driver Intelligence")
        }
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        status = SharedStore.status
        history = SharedStore.history
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async { notificationsAllowed = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional }
        }
    }

    // MARK: Cartões

    private var statusCard: some View {
        Card {
            HStack(spacing: 10) {
                Circle().fill(isLive ? Palette.positive : (status.running ? Palette.warning : Palette.neutral)).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leitura de ofertas").font(.headline)
                    Text(isLive ? "Ativa · lendo a tela" : (status.running ? "Transmissão iniciada, aguardando quadros" : "Desligada"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(isLive
                 ? "Pode abrir o Uber Driver. Cada oferta vira uma notificação com R$/km, R$/h, lucro e o veredito."
                 : "Toque no botão abaixo e escolha \"Driver Intelligence\" para começar a transmitir a tela. O texto é lido no próprio iPhone; nenhuma imagem é salva ou enviada.")
                .font(.footnote).foregroundStyle(.secondary)
            BroadcastButton(running: status.running)
            if status.running || status.framesAnalyzed > 0 {
                HStack {
                    Stat(title: "Quadros lidos", value: "\(status.framesAnalyzed)")
                    Stat(title: "Ofertas", value: "\(status.offersNotified)")
                    Stat(title: "Leitura", value: status.lastOcrMs.map { "\($0) ms" } ?? "—")
                }
            }
            if BroadcastButton.extensionBundleId == nil {
                Banner(text: "A extensão de leitura de tela não está dentro do app instalado. No ESign, desative a opção de remover plugins/extensões (\"Remove PlugIns\") e assine de novo.", color: Palette.negative)
            } else {
                Text("Se o botão não abrir a janela: Central de Controle › segure o botão de Gravação de Tela › escolha Driver Intelligence › Iniciar Transmissão.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let e = status.lastError {
                Text("Último erro: \(e)").font(.caption).foregroundStyle(Palette.warning)
            }
        }
    }

    private var setupCard: some View {
        Card {
            Text("Configuração").font(.headline)
            StepRow(
                number: 1,
                title: "Permitir notificações",
                detail: "É por elas que a análise chega enquanto você usa o app de corrida.",
                done: notificationsAllowed == true,
                action: notificationsAllowed == true ? nil : ("Permitir", {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                        refresh()
                    }
                })
            )
            StepRow(
                number: 2,
                title: "Permitir durante o Foco",
                detail: "Ajustes do iOS › Foco › Não Perturbe (e Condução) › Apps › adicionar Driver Intelligence.",
                done: focusConfirmed,
                action: focusConfirmed ? nil : ("Já fiz isso", {
                    focusConfirmed = true
                    UserDefaults.standard.set(true, forKey: "focusConfirmed")
                })
            )
            StepRow(
                number: 3,
                title: "Testar notificação",
                detail: "Envia uma análise de exemplo para conferir como aparece.",
                done: testSent,
                action: ("Enviar teste", {
                    Notifier.sendTest(settings: SharedStore.settings)
                    testSent = true
                })
            )
            StepRow(
                number: 4,
                title: "Iniciar a transmissão",
                detail: "Pelo botão acima ou na Central de Controle: segure o botão de gravação de tela › Driver Intelligence › Iniciar Transmissão.",
                done: status.running,
                action: nil
            )
        }
    }

    private var todayCard: some View {
        Card {
            HStack {
                Text("Hoje").font(.headline)
                Spacer()
                Text("\(today.count) ofertas analisadas").font(.subheadline).foregroundStyle(.secondary)
            }
            let greens = today.filter { $0.cls == .green }.count
            HStack {
                Stat(title: "Rentáveis", value: "\(greens)", color: Palette.positive)
                Stat(title: "Moderadas", value: "\(today.filter { $0.cls == .yellow }.count)", color: Palette.warning)
                Stat(title: "Abaixo", value: "\(today.filter { $0.cls == .red }.count)", color: Palette.negative)
            }
            ForEach(today.prefix(3)) { r in OfferRow(record: r) }
        }
    }

    private var howItWorks: some View {
        Card {
            Text("Como funciona").font(.headline)
            Text("O iPhone não permite janelas por cima de outros apps. Por isso o Driver Intelligence usa a transmissão de tela do iOS: lê a oferta, calcula com os custos do seu carro e manda a notificação. Um indicador vermelho no topo mostra que a transmissão está ligada; para parar, toque nele.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("O app nunca aceita nem recusa corridas.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// Seletor de transmissão do sistema. Fica escondido (mas no layout) e é acionado pelo nosso botão:
/// o botão interno do RPSystemBroadcastPickerView só recebe toques no tamanho com que foi criado,
/// então disparamos a ação dele diretamente.
final class BroadcastPickerHolder: ObservableObject {
    let picker: RPSystemBroadcastPickerView = {
        let p = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        p.showsMicrophoneButton = false
        p.preferredExtension = BroadcastButton.extensionBundleId
        return p
    }()

    func open() {
        picker.preferredExtension = BroadcastButton.extensionBundleId
        for case let button as UIButton in picker.subviews {
            button.sendActions(for: .touchUpInside)
            button.sendActions(for: .touchDown)
            return
        }
    }
}

struct PickerHost: UIViewRepresentable {
    let holder: BroadcastPickerHolder
    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        v.alpha = 0.011 // presente na hierarquia, mas invisível
        v.isUserInteractionEnabled = false
        v.addSubview(holder.picker)
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct BroadcastButton: View {
    var running: Bool
    @StateObject private var holder = BroadcastPickerHolder()

    var body: some View {
        ZStack {
            PickerHost(holder: holder).frame(width: 1, height: 1)
            Button {
                holder.open()
            } label: {
                Text(running ? "Parar / trocar transmissão" : "Iniciar leitura de ofertas")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(Palette.background)
                    .background(Palette.brand, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    /// Identificador real da extensão instalada (instaladores como AltStore/ESign podem alterá-lo).
    static var extensionBundleId: String? {
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil) else { return nil }
        for url in items where url.pathExtension == "appex" {
            if let b = Bundle(url: url),
               let ext = b.object(forInfoDictionaryKey: "NSExtension") as? [String: Any],
               (ext["NSExtensionPointIdentifier"] as? String) == "com.apple.broadcast-services-upload" {
                return b.bundleIdentifier
            }
        }
        return nil
    }
}
