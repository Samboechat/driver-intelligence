import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Atualiza e encerra a Atividade ao Vivo (app e extensão de leitura). Abrir fica no app: ver LiveActivityStarter.
@available(iOS 16.2, *)
enum LiveActivityController {
    static var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    static var isRunning: Bool { !Activity<RideActivityAttributes>.activities.isEmpty }

    static func update(_ state: RideActivityAttributes.ContentState) {
        let content = ActivityContent(state: state, staleDate: nil, relevanceScore: state.phase == .offer ? 100 : 50)
        for activity in Activity<RideActivityAttributes>.activities {
            Task { await activity.update(content) }
        }
    }

    static func end() {
        for activity in Activity<RideActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
#endif
