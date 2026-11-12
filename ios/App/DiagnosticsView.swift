import SwiftUI
import DriverCore

/// O que a leitura de tela está enxergando: estado do canal com o app, números da leitura
/// e o texto das telas que pareciam chamado e não puderam ser lidas.
struct DiagnosticsView: View {
    @EnvironmentObject var perms: Permissions
    @ObservedObject private var capture = CaptureMonitor.shared
    @ObservedObject private var gps = LocationService.shared
    @State private var status = SharedStore.status
    @State private var misses = SharedStore.misses
    @State private var settings = SharedStore.settings
    @State private var now = Date()
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var state: ReadingState { ReadingState.current(status: status, capture: capture, now: now) }

    var body: some View {
        Form {
            Section {
                row("Leitura", state.title, state.color)
                row("Extensão de leitura no app", BroadcastButton.extensionBundleId != nil ? "Instalada" : "Faltando",
                    BroadcastButton.extensionBundleId != nil ? Palette.positive : Palette.negative)
                row("Notificações", perms.notificationsOK ? "Permitidas" : "Bloqueadas",
                    perms.notificationsOK ? Palette.positive : Palette.negative)
                row("Último sinal da leitura", SharedStore.pulseAt.map { ago($0) } ?? "nunca recebido",
                    SharedStore.pulseAt == nil ? Palette.warning : Color.secondary)
                row("Armazenamento compartilhado", SharedStore.isShared ? "Disponível" : "Indisponível (usando o canal reserva)", Color.secondary)
            } header: {
                Text("Estado")
            } footer: {
                Text("Instalado pelo ESign, o app costuma ficar sem o armazenamento compartilhado. Nesse caso a leitura conversa com o app por um canal reserva, e tudo continua funcionando.")
            }

            Section {
                row("Atividades ao Vivo no iPhone", islandAvailable ? "Permitidas" : "Desligadas",
                    islandAvailable ? Palette.positive : Palette.negative)
                row("Ilha aberta agora", islandRunning ? "Sim" : "Não", islandRunning ? Palette.positive : Color.secondary)
                if let e = SharedStore.liveError { Text("Erro ao abrir a ilha: \(e)").font(.footnote).foregroundStyle(Palette.warning) }
                row("Localização", locationLabel, gps.authorized ? Palette.positive : Palette.warning)
                row("GPS ligado agora", gps.isTracking ? "Sim" : "Não", gps.isTracking ? Palette.positive : Color.secondary)
                row("Última posição", gps.lastFix.map { ago($0) } ?? "—")
                if let e = gps.lastError { Text("Erro do GPS: \(e)").font(.footnote).foregroundStyle(Palette.warning) }
            } header: {
                Text("Dynamic Island e GPS")
            } footer: {
                Text("Para a ilha receber os chamados com o Uber na frente: Atividades ao Vivo permitidas, localização permitida e GPS ligado. Se \"Ilha aberta agora\" ficar em Não com a leitura ligada, abra o app uma vez com a leitura já rodando.")
            }

            Section("Esta gravação") {
                row("Telas analisadas", "\(status.framesAnalyzed)")
                row("Última tela lida", status.lastFrameAt.map { ago($0) } ?? "—")
                row("Tempo de cada leitura", status.lastOcrMs.map { "\($0) ms" } ?? "—")
                row("Chamados avisados", "\(status.offersNotified)")
                row("Chamados não lidos", "\(status.missed ?? 0)", (status.missed ?? 0) > 0 ? Palette.warning : Color.secondary)
                if let screen = status.screen { row("Tela reconhecida", screenLabel(screen)) }
                if let e = status.lastError { Text("Último erro: \(e)").font(.footnote).foregroundStyle(Palette.warning) }
            }

            Section {
                Toggle("Guardar o texto dos chamados não lidos", isOn: $settings.keepReadDiagnostics)
                if misses.isEmpty {
                    Text("Nenhum chamado ficou sem leitura.").foregroundStyle(.secondary)
                }
                ForEach(misses) { m in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(m.at.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.semibold))
                            Spacer()
                            ShareLink(item: m.text) { Label("Enviar", systemImage: "square.and.arrow.up").font(.subheadline) }
                        }
                        Text(m.text)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(14)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Chamados não lidos")
            } footer: {
                Text("Quando uma tela tem cara de chamado (botão Aceitar ou distâncias) mas falta o valor ou alguma distância, o texto que o app enxergou fica guardado aqui, só no aparelho. Envie esse texto para ajustar a leitura. Ele pode conter os endereços do chamado.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Diagnóstico")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(timer) { _ in
            now = Date()
            status = SharedStore.status
            let m = SharedStore.misses
            if m != misses { misses = m }
        }
        .onChange(of: settings) { new in
            SharedStore.settings = new
            Bridge.publishSettings(new)
        }
    }

    private var islandAvailable: Bool {
        if #available(iOS 16.2, *) { return LiveActivityController.isAvailable }
        return false
    }

    private var islandRunning: Bool {
        if #available(iOS 16.2, *) { return LiveActivityController.isRunning }
        return false
    }

    private var locationLabel: String {
        switch gps.authorization {
        case .authorizedAlways: return "Sempre"
        case .authorizedWhenInUse: return "Durante o uso"
        case .denied: return "Negada"
        case .restricted: return "Bloqueada"
        default: return "Ainda não pedida"
        }
    }

    private func row(_ title: String, _ value: String, _ color: Color = .secondary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(color).multilineTextAlignment(.trailing)
        }
    }

    private func ago(_ date: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 5 { return "agora" }
        if s < 60 { return "há \(s) s" }
        if s < 3600 { return "há \(s / 60) min" }
        if s < 86400 { return "há \(s / 3600) h" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func screenLabel(_ raw: String) -> String {
        switch ScreenKind(rawValue: raw) {
        case .offer: return "Chamado"
        case .goingToPickup: return "Indo buscar"
        case .waitingPassenger: return "Aguardando passageiro"
        case .onTrip: return "Em viagem"
        case .tripCompleted: return "Corrida concluída"
        case .onlineIdle: return "Online, sem chamado"
        case .offline: return "Offline"
        default: return "Outra tela"
        }
    }
}
