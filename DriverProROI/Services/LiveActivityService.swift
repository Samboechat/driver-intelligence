import ActivityKit
import Foundation

/// Live Activity do turno (tela bloqueada e Dynamic Island).
@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()

    private var activity: Activity<ShiftActivityAttributes>?

    private init() {}

    private func adoptExisting() {
        if activity == nil {
            activity = Activity<ShiftActivityAttributes>.activities.first { $0.activityState == .active }
        }
    }

    /// Inicia (ou reaproveita) a Live Activity. Só funciona com o app em primeiro plano;
    /// se falhar, é tentado de novo na próxima vez que o app ficar ativo.
    func startIfNeeded(startedAt: Date, state: ShiftActivityAttributes.ContentState) {
        adoptExisting()
        if let activity, activity.activityState == .active {
            update(state)
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ShiftActivityAttributes(startedAt: startedAt)
        let content = ActivityContent(state: state, staleDate: nil)
        activity = try? Activity<ShiftActivityAttributes>.request(attributes: attributes, content: content, pushType: nil)
    }

    func update(_ state: ShiftActivityAttributes.ContentState) {
        adoptExisting()
        guard let activity else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        Task {
            await activity.update(content)
        }
    }

    func end(_ state: ShiftActivityAttributes.ContentState) {
        let content = ActivityContent(state: state, staleDate: nil)
        let all = Activity<ShiftActivityAttributes>.activities
        activity = nil
        Task {
            for item in all {
                await item.end(content, dismissalPolicy: .immediate)
            }
        }
    }
}
