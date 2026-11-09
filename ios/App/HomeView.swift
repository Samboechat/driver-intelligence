import SwiftUI
import ReplayKit
import UserNotifications
import DriverCore

struct HomeView: View {
    @EnvironmentObject var perms: Permissions
    @State private var status = SharedStore.status
    @State private var history = SharedStore.history
    @State private var trips = SharedStore.trips
    @State private var factors = SharedStore.currentFactors(SharedStore.settings)
    @State private var settings = SharedStore.settings
    @State private var focusConfirmed = UserDefaults.standard.bool(forKey: "focusConfirmed")
    @State private var testSent = false
    @State private var showSimulator = false
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var isLive: Bool {
        guard status.running, let last = status.lastFrameAt else { return false }
        return Date().timeIntervalSince(last) < 8
    }

    private var today: [OfferRecord] { history.filter { Calendar.current.isDateInToday($0.date) } }
    private var tripsToday: [TripRecord] { trips.filter { Calendar.current.isDateInToday($0.completedAt) } }
    private var phase: TripPhase { status.tripPhase.flatMap(TripPhase.init(rawValue:)) ?? .none }
    private var inTrip: Bool { isLive && [.toPickup, .waiting, .onTrip].contains(phase) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusCard
                    if inTrip { tripCard }
                    if !SharedStore.isShared {
                        Banner(text: "Grupo do app indisponível: a extensão vai usar os ajustes padrão e o app não verá os prints. No ESign, assine mantendo as extensões e os grupos (App Groups) do app.", color: Palette.warning)
                    }
                    if !perms.notificationsOK || (settings.saveScreenshots && !perms.photosOK) || !focusConfirmed || !testSent && today.isEmpty { setupCard }
                    earningsCard
                    if !today.isEmpty { todayCard }
                    learningCard
                    howItWorks
                }
                .padding(16)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Driver Intelligence")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSimulator = true } label: { Label("Simular", systemImage: "function") }
                }
            }
            .sheet(isPresented: $showSimulator) {
                SimulatorView().preferredColorScheme(.dark)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        status = SharedStore.status
        history = SharedStore.history
        trips = SharedStore.trips
        settings = SharedStore.settings
        factors = SharedStore.currentFactors(settings)
        Task { await perms.refresh() }
    }

    // MARK: Cartões

    private var statusCard: some View {
        Card {
            HStack(spacing: 10) {
                Circle().fill(isLive ? Palette.positive : (status.running ? Palette.warning : Palette.neutral)).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leitura de chamados").font(.headline)
                    Text(isLive ? "Ativa · \(status.screen.flatMap(ScreenKind.init(rawValue:))?.label ?? "lendo a tela")"
                                : (status.running ? "Transmissão iniciada, aguardando quadros" : "Desligada"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(isLive
                 ? "Pode abrir o Uber Driver. Cada chamado vira uma notificação com R$/km, R$/h, lucro e veredito."
                    + (settings.saveScreenshots ? " Um print de cada chamado vai para o álbum." : " Nenhuma imagem da tela é guardada.")
                 : "Toque no botão abaixo e escolha \"Driver Intelligence\" › Iniciar Transmissão. A leitura é feita no próprio iPhone.")
                .font(.footnote).foregroundStyle(.secondary)
            BroadcastButton(running: status.running)
            if status.running || status.framesAnalyzed > 0 {
                HStack {
                    Stat(title: "Quadros", value: "\(status.framesAnalyzed)")
                    Stat(title: "Chamados", value: "\(status.offersNotified)")
                    if settings.saveScreenshots { Stat(title: "Prints", value: "\(status.screenshotsSaved)") }
                    Stat(title: "Leitura", value: status.lastOcrMs.map { "\($0) ms" } ?? "—")
                }
            }
            if BroadcastButton.extensionBundleId == nil {
                Banner(text: "A extensão de leitura de tela não está dentro do app instalado. No ESign, desative a opção de remover plugins/extensões (\"Remove PlugIns\") e assine de novo.", color: Palette.negative)
            } else if !status.running {
                Text("Se o botão não abrir a janela: Central de Controle › segure o botão de Gravação de Tela › Driver Intelligence › Iniciar Transmissão.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let e = status.lastError {
                Text("Último erro: \(e)").font(.caption).foregroundStyle(Palette.warning)
            }
        }
    }

    private var tripCard: some View {
        Card {
            HStack {
                Image(systemName: "car.fill").foregroundStyle(Palette.brand)
                Text(phase.label).font(.headline)
                Spacer()
                if let f = status.tripFare { Text(Br.money(f)).font(.headline.monospacedDigit()) }
            }
            if let start = status.tripAcceptedAt {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TEMPO REAL").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Text(start, style: .timer).font(.title2.bold().monospacedDigit())
                    }
                    Spacer()
                    Stat(title: "Previsão", value: Br.minutes(status.tripPredictedMin))
                }
            }
            HStack {
                Button("🏁 Finalizei") { SharedStore.command = AppCommand(action: .finish) }.buttonStyle(.borderedProminent)
                Button("Parar de acompanhar", role: .destructive) { SharedStore.command = AppCommand(action: .reset) }.buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
    }

    private var setupCard: some View {
        Card {
            Text("Configuração").font(.headline)
            StepRow(
                number: 1,
                title: "Notificações",
                detail: perms.notificationsQuiet
                    ? "Estão em modo silencioso. Ative \"Permitir Notificações\", \"Faixas\" e \"Tela Bloqueada\" nos Ajustes."
                    : (perms.notifications == .denied
                       ? "Negadas. Abra os Ajustes › Notificações e ative \"Permitir Notificações\"."
                       : "É por elas que a análise chega por cima do Uber."),
                done: perms.notificationsOK,
                action: perms.notificationsOK ? nil : (perms.notifications == .notDetermined ? "Permitir" : "Abrir Ajustes", {
                    if perms.notifications == .notDetermined { Task { await perms.requestNotifications() } } else { perms.openSettings() }
                })
            )
            if settings.saveScreenshots {
              StepRow(
                number: 2,
                title: "Fotos (prints dos chamados)",
                detail: "Para salvar o print de cada chamado no álbum \"Driver Intelligence\".",
                done: perms.photosOK,
                action: perms.photosOK ? nil : (PhotoAlbum.notDetermined ? "Permitir" : "Abrir Ajustes", {
                    if PhotoAlbum.notDetermined { Task { await perms.requestPhotos() } } else { perms.openAppSettings() }
                })
              )
            }
            StepRow(
                number: 3,
                title: "Permitir durante o Foco",
                detail: "Ajustes › Foco › Condução (e Não Perturbe) › Apps › adicionar Driver Intelligence.",
                done: focusConfirmed,
                action: focusConfirmed ? nil : ("Já fiz isso", {
                    focusConfirmed = true
                    UserDefaults.standard.set(true, forKey: "focusConfirmed")
                })
            )
            StepRow(
                number: 4,
                title: "Testar notificação",
                detail: "Envia uma análise de exemplo para conferir como aparece.",
                done: testSent,
                action: ("Enviar teste", {
                    Notifier.sendTest(settings: SharedStore.settings)
                    testSent = true
                })
            )
        }
    }

    private var earningsCard: some View {
        let gross = tripsToday.compactMap(\.fare).reduce(0, +)
        let profit = tripsToday.compactMap(\.profit).reduce(0, +)
        let minutes = tripsToday.compactMap(\.totalMin).reduce(0, +)
        let km = tripsToday.compactMap(\.totalKm).reduce(0, +)
        return Card {
            HStack {
                Text("Ganhos de hoje").font(.headline)
                Spacer()
                Text("\(tripsToday.count) corrida(s)").font(.subheadline).foregroundStyle(.secondary)
            }
            Text(Br.money(gross)).font(.system(size: 34, weight: .bold).monospacedDigit())
            HStack {
                Stat(title: "Lucro", value: Br.money(profit), color: profit >= 0 ? Palette.positive : Palette.negative)
                Stat(title: "R$/h real", value: minutes > 1 ? Br.decimal(gross / (minutes / 60), 0) : "—")
                Stat(title: "Km", value: Br.decimal(km, 0))
            }
            if let goal = settings.dailyGoal, goal > 0 {
                ProgressView(value: min(gross, goal), total: goal).tint(Palette.positive)
                Text(gross >= goal ? "Meta do dia batida! 🎉" : "Faltam \(Br.money(goal - gross)) para a meta de \(Br.money(goal))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if tripsToday.isEmpty {
                Text("As corridas aceitas são registradas sozinhas, com o tempo real de cada uma.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var todayCard: some View {
        Card {
            HStack {
                Text("Chamados de hoje").font(.headline)
                Spacer()
                Text("\(today.count)").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack {
                Stat(title: settings.useMatrix ? "Aceitar" : "Rentáveis", value: "\(today.filter { $0.cls == .green }.count)", color: Palette.positive)
                Stat(title: settings.useMatrix ? "Avaliar" : "Moderados", value: "\(today.filter { $0.cls == .yellow }.count)", color: Palette.warning)
                Stat(title: settings.useMatrix ? "Recusar" : "Abaixo", value: "\(today.filter { $0.cls == .red }.count)", color: Palette.negative)
            }
            HStack {
                Stat(title: "Aceitos", value: "\(today.filter { $0.result == .accepted }.count)")
                Stat(title: "Recusados", value: "\(today.filter { $0.result == .rejected }.count)")
                Stat(title: "Ignorados", value: "\(today.filter { $0.result == .expired }.count)")
            }
            ForEach(today.prefix(3)) { r in OfferRow(record: r) }
        }
    }

    private var learningCard: some View {
        Card {
            HStack {
                Image(systemName: "brain.head.profile").foregroundStyle(Palette.brand)
                Text("Tempo real aprendido").font(.headline)
            }
            if factors.learned {
                Text("Nas suas corridas neste horário, a busca leva ×\(Br.decimal(factors.pickup)) e a viagem ×\(Br.decimal(factors.trip)) do tempo que o app mostra. As próximas análises já usam isso.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Ainda aprendendo (\(SharedStore.samples.count)/5 corridas medidas). Até lá, a análise usa +\(Int(((settings.pickupTimeFactor - 1) * 100).rounded()))% na busca e +\(Int(((settings.tripTimeFactor - 1) * 100).rounded()))% na viagem.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var howItWorks: some View {
        Card {
            Text("Como funciona").font(.headline)
            Text("O iPhone não permite janelas por cima de outros apps. Por isso o Driver Intelligence usa a transmissão de tela do iOS: lê o chamado no próprio aparelho, aplica a sua matriz de aceite e manda a notificação. Cada quadro é descartado logo depois de lido (prints só se você ligar nos Ajustes). Um indicador vermelho no topo mostra que a transmissão está ligada; para parar, toque nele.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Se o app não perceber que você aceitou, toque e segure a notificação do chamado › \"Aceitei esta corrida\". O app nunca aceita nem recusa corridas.")
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
