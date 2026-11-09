import Foundation
import ActivityKit

/// Abrir a Atividade ao Vivo só é permitido com o app em primeiro plano.
@available(iOS 16.2, *)
extension LiveActivityController {
    /// Chamado pelo app (em primeiro plano). Devolve o erro em texto, se houver.
    @discardableResult
    static func start(_ state: RideActivityAttributes.ContentState = .init()) -> String? {
        guard isAvailable else { return "Atividades ao Vivo desligadas nos Ajustes do iPhone." }
        if isRunning {
            update(state)
            return nil
        }
        do {
            _ = try Activity<RideActivityAttributes>.request(
                attributes: RideActivityAttributes(),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
