import AppIntents
import Foundation

/// Ponte entre intents (widget, Live Activity, Atalhos) e o gerenciador de turno do app.
/// No processo do app o `handler` é registrado na inicialização; fora dele o comando
/// fica pendente e é aplicado na próxima abertura do app.
@MainActor
final class ShiftCommandCenter {
    static let shared = ShiftCommandCenter()

    var handler: ((ShiftCommand) -> String)?

    private init() {}

    @discardableResult
    func send(_ command: ShiftCommand) -> String {
        if let handler {
            return handler(command)
        }
        PendingCommandStore.push(command)
        return "Comando registrado. Abra o DriverPro ROI para aplicar."
    }
}

/// Botão dos widgets e da Live Activity: inicia, pausa ou retoma o turno.
/// `LiveActivityIntent` faz o sistema executar o intent no processo do app.
struct ToggleShiftIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Iniciar ou pausar turno"
    static let description: IntentDescription? = IntentDescription("Inicia o turno se estiver parado, pausa se estiver rodando e retoma se estiver pausado.")
    static let openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        ShiftCommandCenter.shared.send(.toggle)
        return .result()
    }
}
