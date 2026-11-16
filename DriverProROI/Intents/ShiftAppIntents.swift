import AppIntents
import Foundation

// Intents expostos à Siri e ao app Atalhos (automações por Bluetooth, CarPlay, NFC etc.).

struct StartShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "Iniciar turno"
    static let description: IntentDescription? = IntentDescription("Inicia o cronômetro e a contagem de km por GPS do turno.")
    static let openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = ShiftManager.shared.execute(.start)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct PauseShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "Pausar turno"
    static let description: IntentDescription? = IntentDescription("Congela o cronômetro e a contagem de km (almoço, descanso, abastecimento).")
    static let openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = ShiftManager.shared.execute(.pause)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct ResumeShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "Retomar turno"
    static let description: IntentDescription? = IntentDescription("Retoma um turno pausado.")
    static let openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = ShiftManager.shared.execute(.resume)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct EndShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "Encerrar turno"
    static let description: IntentDescription? = IntentDescription("Encerra o turno e abre o app no Resumo Geral Diário.")
    static let openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = ShiftManager.shared.execute(.end)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct ShiftStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Status do turno"
    static let description: IntentDescription? = IntentDescription("Informa tempo ativo e km rodados do turno atual.")
    static let openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = ShiftManager.shared
        let message: String
        if manager.hasShift {
            let state = manager.isRunning ? "rodando" : "pausado"
            message = "Turno \(state): \(Fmt.hoursMinutes(manager.activeSeconds())) ativos e \(Fmt.km(manager.liveKm)) rodados."
        } else {
            message = "Nenhum turno em andamento."
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct DriverProShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartShiftIntent(),
            phrases: [
                "Iniciar turno no \(.applicationName)",
                "Começar turno no \(.applicationName)"
            ],
            shortTitle: "Iniciar turno",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: PauseShiftIntent(),
            phrases: [
                "Pausar turno no \(.applicationName)"
            ],
            shortTitle: "Pausar turno",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ResumeShiftIntent(),
            phrases: [
                "Retomar turno no \(.applicationName)"
            ],
            shortTitle: "Retomar turno",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: EndShiftIntent(),
            phrases: [
                "Encerrar turno no \(.applicationName)"
            ],
            shortTitle: "Encerrar turno",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: ShiftStatusIntent(),
            phrases: [
                "Status do turno no \(.applicationName)"
            ],
            shortTitle: "Status do turno",
            systemImageName: "gauge.with.dots.needle.50percent"
        )
    }
}
