import SwiftUI
import ReplayKit
import UserNotifications
import DriverCore

/// Avisa quando a tela começa ou para de ser gravada/transmitida (vale mesmo sem falar com a extensão).
final class CaptureMonitor: ObservableObject {
    static let shared = CaptureMonitor()
    @Published private(set) var isCaptured = UIScreen.main.isCaptured
    @Published private(set) var since: Date? = UIScreen.main.isCaptured ? Date() : nil
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        let now = UIScreen.main.isCaptured
        guard now != isCaptured else { return }
        isCaptured = now
        since = now ? Date() : nil
    }
}

/// Estado da leitura como o motorista entende: desligada, ligando, lendo ou gravando sem resposta.
enum ReadingState {
    case off, starting, reading, silent

    static func current(status: BroadcastStatus, capture: CaptureMonitor, now: Date = Date()) -> ReadingState {
        let pulse = SharedStore.pulseAt.map { now.timeIntervalSince($0) < 20 } ?? false
        let frames = status.lastFrameAt.map { now.timeIntervalSince($0) < 10 } ?? false
        if status.running && (pulse || frames) { return .reading }
        guard capture.isCaptured else { return .off }
        if let since = capture.since, now.timeIntervalSince(since) < 15 { return .starting }
        return .silent
    }

    var isOn: Bool { self != .off }

    var title: String {
        switch self {
        case .off: return "Leitura desligada"
        case .starting: return "Ligando a leitura…"
        case .reading: return "Lendo a tela"
        case .silent: return "Gravação ativa"
        }
    }

    var color: Color {
        switch self {
        case .off: return Palette.neutral
        case .starting, .silent: return Palette.warning
        case .reading: return Palette.positive
        }
    }

    var icon: String {
        switch self {
        case .off: return "pause.fill"
        case .starting: return "hourglass"
        case .reading: return "dot.radiowaves.left.and.right"
        case .silent: return "exclamationmark"
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var perms: Permissions
    @ObservedObject private var capture = CaptureMonitor.shared
    @State private var status = SharedStore.status
    @State private var history = SharedStore.history
    @State private var trips = SharedStore.trips
    @State private var factors = SharedStore.currentFactors(SharedStore.settings)
    @State private var settings = SharedStore.settings
    @State private var now = Date()
    @AppStorage("focusConfirmed") private var focusConfirmed = false
    @AppStorage("testSent") private var testSent = false
    @State private var showSimulator = false
    @State private var showHelp = false
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var state: ReadingState { ReadingState.current(status: status, capture: capture, now: now) }
    private var today: [OfferRecord] { history.filter { Calendar.current.isDateInToday($0.date) } }
    private var tripsToday: [TripRecord] { trips.filter { Calendar.current.isDateInToday($0.completedAt) } }
    private var phase: TripPhase { status.tripPhase.flatMap(TripPhase.init(rawValue:)) ?? .none }
    private var inTrip: Bool { state == .reading && [.toPickup, .waiting, .onTrip].contains(phase) }
    private var needsSetup: Bool {
        !perms.notificationsOK || (settings.saveScreenshots && !perms.photosOK) || !focusConfirmed || !testSent
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusCard
                    if inTrip { tripCard }
                    if needsSetup { setupCard }
                    lastOfferCard
                    todayCard
                    learningCard
                }
                .padding(16)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Driver Intelligence")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showHelp = true } label: { Label("Como funciona", systemImage: "questionmark.circle") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSimulator = true } label: { Label("Simular", systemImage: "function") }
                }
            }
            .sheet(isPresented: $showSimulator) { SimulatorView().preferredColorScheme(.dark) }
            .sheet(isPresented: $showHelp) { HelpView().preferredColorScheme(.dark) }
        }
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        capture.refresh()
        now = Date()
        status = SharedStore.status
        history = SharedStore.history
        trips = SharedStore.trips
        settings = SharedStore.settings
        factors = SharedStore.currentFactors(settings)
        Task { await perms.refresh() }
    }

    // MARK: Estado da leitura

    private var statusCard: some View {
        Card {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(state.color.opacity(0.18)).frame(width: 54, height: 54)
                    Image(systemName: state.icon).font(.title2.weight(.semibold)).foregroundStyle(state.color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.title).font(.title3.bold())
                    Text(stateDetail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            BroadcastButton(running: state.isOn)
            if state == .reading {
                HStack {
                    Stat(title: "Chamados", value: "\(status.offersNotified)")
                    Stat(title: "Última leitura", value: status.lastFrameAt.map { ago($0) } ?? "—")
                    Stat(title: "Velocidade", value: status.lastOcrMs.map { "\($0) ms" } ?? "—")
                }
            }
            if state == .silent {
                Banner(text: "O iPhone está gravando a tela, mas o app ainda não recebeu sinal da leitura. Se as notificações dos chamados estão chegando, pode continuar normalmente. Se não chegam, pare e ligue de novo escolhendo \"Driver Intelligence\" na janela do iOS.", color: Palette.warning)
            }
            if state == .reading, let missed = status.missed, missed > 0 {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Label("\(missed) chamado(s) não lido(s) nesta gravação. Ver o que o app enxergou", systemImage: "eye.trianglebadge.exclamationmark")
                        .font(.footnote).multilineTextAlignment(.leading)
                }
            }
            if BroadcastButton.extensionBundleId == nil {
                Banner(text: "A extensão de leitura de tela não está dentro do app instalado. No ESign, desative a opção de remover plugins/extensões (\"Remove PlugIns\") e assine de novo.", color: Palette.negative)
            } else if state == .off {
                Text("Se a janela não abrir: Central de Controle › segure o botão de Gravação de Tela › Driver Intelligence › Iniciar Transmissão.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let e = status.lastError, state == .reading {
                Text("Último erro de leitura: \(e)").font(.caption).foregroundStyle(Palette.warning)
            }
        }
    }

    private var stateDetail: String {
        switch state {
        case .off: return "Toque em Ligar leitura e, na janela do iOS, em Iniciar Transmissão."
        case .starting: return "Aguarde alguns segundos."
        case .reading: return "Pode abrir o Uber Driver. Cada chamado chega como notificação."
        case .silent: return "Sem sinal da leitura até agora."
        }
    }

    private func ago(_ date: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 5 { return "agora" }
        if s < 60 { return "há \(s) s" }
        if s < 3600 { return "há \(s / 60) min" }
        return "há \(s / 3600) h"
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
                Button("🏁 Finalizei") { Bridge.send(AppCommand(action: .finish)) }.buttonStyle(.borderedProminent)
                Button("Parar de acompanhar", role: .destructive) { Bridge.send(AppCommand(action: .reset)) }.buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
    }

    // MARK: Último chamado

    @ViewBuilder
    private var lastOfferCard: some View {
        if let r = history.first, now.timeIntervalSince(r.date) < 12 * 3600 {
            NavigationLink { CaptureDetail(record: r) } label: {
                Card {
                    HStack {
                        Text("ÚLTIMO CHAMADO · \(ago(r.date).uppercased())").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if let out = r.result { Text(out.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    VerdictBlock(record: r)
                }
            }
            .buttonStyle(.plain)
        } else {
            Card {
                Text("ÚLTIMO CHAMADO").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(state == .reading
                     ? "Nenhum chamado lido ainda. Quando um tocar no Uber, ele aparece aqui e no Histórico."
                     : "Ligue a leitura para os chamados aparecerem aqui e no Histórico.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Hoje

    private var todayCard: some View {
        let gross = tripsToday.compactMap(\.fare).reduce(0, +)
        let profit = tripsToday.compactMap(\.profit).reduce(0, +)
        let minutes = tripsToday.compactMap(\.totalMin).reduce(0, +)
        return Card {
            HStack {
                Text("Hoje").font(.headline)
                Spacer()
                Text("\(tripsToday.count) corrida(s) · \(today.count) chamado(s)").font(.subheadline).foregroundStyle(.secondary)
            }
            Text(Br.money(gross)).font(.system(size: 34, weight: .bold).monospacedDigit())
            HStack {
                Stat(title: "Lucro", value: Br.money(profit), color: profit >= 0 ? Palette.positive : Palette.negative)
                Stat(title: "R$/h real", value: minutes > 1 ? Br.decimal(gross / (minutes / 60), 0) : "—")
                Stat(title: "Aceitas", value: "\(today.filter { $0.result == .accepted }.count)")
            }
            if let goal = settings.dailyGoal, goal > 0 {
                ProgressView(value: min(gross, goal), total: goal).tint(Palette.positive)
                Text(gross >= goal ? "Meta do dia batida! 🎉" : "Faltam \(Br.money(goal - gross)) para a meta de \(Br.money(goal))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !today.isEmpty {
                Divider().opacity(0.3)
                HStack {
                    Stat(title: settings.useMatrix ? "Aceitar" : "Rentáveis", value: "\(today.filter { $0.cls == .green }.count)", color: Palette.positive)
                    Stat(title: settings.useMatrix ? "Avaliar" : "Moderados", value: "\(today.filter { $0.cls == .yellow }.count)", color: Palette.warning)
                    Stat(title: settings.useMatrix ? "Recusar" : "Abaixo", value: "\(today.filter { $0.cls == .red }.count)", color: Palette.negative)
                }
            }
        }
    }

    // MARK: Configuração

    private var setupCard: some View {
        Card {
            Text("Falta configurar").font(.headline)
            if !perms.notificationsOK {
                StepRow(
                    number: 1,
                    title: "Notificações",
                    detail: perms.notificationsQuiet
                        ? "Estão em modo silencioso. Ative \"Permitir Notificações\", \"Faixas\" e \"Tela Bloqueada\" nos Ajustes."
                        : (perms.notifications == .denied
                           ? "Negadas. Abra os Ajustes › Notificações e ative \"Permitir Notificações\"."
                           : "É por elas que a análise chega por cima do Uber."),
                    done: false,
                    action: (perms.notifications == .notDetermined ? "Permitir" : "Abrir Ajustes", {
                        if perms.notifications == .notDetermined { Task { await perms.requestNotifications() } } else { perms.openSettings() }
                    })
                )
            }
            if settings.saveScreenshots && !perms.photosOK {
                StepRow(
                    number: 2,
                    title: "Fotos (prints dos chamados)",
                    detail: "Para salvar o print de cada chamado no álbum \"Driver Intelligence\".",
                    done: false,
                    action: (PhotoAlbum.notDetermined ? "Permitir" : "Abrir Ajustes", {
                        if PhotoAlbum.notDetermined { Task { await perms.requestPhotos() } } else { perms.openAppSettings() }
                    })
                )
            }
            if !focusConfirmed {
                StepRow(
                    number: 3,
                    title: "Permitir durante o Foco",
                    detail: "Ajustes › Foco › Condução (e Não Perturbe) › Apps › adicionar Driver Intelligence.",
                    done: false,
                    action: ("Já fiz isso", { focusConfirmed = true })
                )
            }
            if !testSent {
                StepRow(
                    number: 4,
                    title: "Testar a notificação",
                    detail: "Envia dois exemplos (um para aceitar, um para recusar) para você conhecer o texto e os sons.",
                    done: false,
                    action: ("Enviar teste", {
                        Notifier.sendTest(settings: SharedStore.settings)
                        testSent = true
                    })
                )
            }
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
}

/// Veredito grande + os números que decidem + motivo. Usado na Início e no detalhe do chamado.
struct VerdictBlock: View {
    var record: OfferRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.verdict ?? record.cls.shortLabel)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(record.cls.color)
                Spacer()
                Text(Br.money(record.fare)).font(.system(size: 26, weight: .bold).monospacedDigit())
            }
            HStack {
                Stat(title: "R$/km", value: Br.decimal(record.revenuePerKm), color: record.cls.color)
                Stat(title: "R$/h", value: Br.decimal(record.revenuePerHour, 0))
                Stat(title: "Busca", value: Br.km(record.pickupKm))
                Stat(title: "Lucro", value: Br.money(record.profit))
            }
            if let reasons = record.reasons, !reasons.isEmpty {
                ForEach(reasons.prefix(3), id: \.self) { r in
                    Label(r, systemImage: record.cls == .red ? "xmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.footnote).foregroundStyle(record.cls.color)
                }
            } else if record.cls != .green {
                Text(record.headline).font(.footnote).foregroundStyle(record.cls.color)
            }
            if let alert = record.alert {
                Label(alert, systemImage: "exclamationmark.triangle.fill").font(.footnote.weight(.semibold)).foregroundStyle(Palette.warning)
            }
            let tags = [record.category, record.rating.map { "★ \(Br.decimal($0))" }, record.zoneKind?.label, Br.oneLine(record.destination)].compactMap { $0 }
            if !tags.isEmpty {
                Text(tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    help("1. Ligue a leitura", "O iPhone não permite janelas por cima de outros apps. Por isso o app usa a transmissão de tela do iOS: toque em Ligar leitura e depois em Iniciar Transmissão. Um indicador vermelho no topo mostra que está ligada.")
                    help("2. Abra o Uber Driver", "Quando um chamado tocar, o app lê o cartão, aplica a sua matriz de aceite e manda uma notificação em cerca de 2 segundos.")
                    help("3. Leia a notificação", "Título: o veredito (ACEITAR, AVALIAR ou RECUSAR) e o valor. Abaixo: R$/km, R$/h e a categoria. Quando não é para aceitar, a linha com ✖︎ ou • diz o motivo. Cada veredito tem um som diferente.")
                    help("4. Aceitou?", "O app percebe sozinho pela tela seguinte. Se não perceber, segure a notificação do chamado e toque em \"Aceitei esta corrida\". O app nunca aceita nem recusa por você.")
                    help("Privacidade", "A leitura é feita no próprio iPhone. Cada quadro é descartado depois de lido; prints só são guardados se você ligar nos Ajustes. Nada é enviado para a internet.")
                }
                .padding(20)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Como funciona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Fechar") { dismiss() } } }
        }
    }

    private func help(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
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
                Label(running ? "Parar leitura" : "Ligar leitura", systemImage: running ? "stop.fill" : "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(running ? Palette.negative : Palette.background)
                    .background(running ? Palette.negative.opacity(0.14) : Palette.brand, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(running ? Palette.negative.opacity(0.5) : Color.clear))
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
