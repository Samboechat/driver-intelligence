import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Atualiza e encerra a Atividade ao Vivo (app e extensão de leitura). Abrir fica no app: ver LiveActivityStarter.
@available(iOS 16.2, *)
enum LiveActivityController {
    static var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    static var isRunning: Bool { !Activity<RideActivityAttributes>.activities.isEmpty }

    /// Se ninguém atualizar até essa hora, a ilha mostra "sem atualização" em vez de um número velho.
    static func content(_ state: RideActivityAttributes.ContentState) -> ActivityContent<RideActivityAttributes.ContentState> {
        ActivityContent(state: state, staleDate: Date().addingTimeInterval(state.phase == .offer ? 90 : 240),
                        relevanceScore: state.phase == .offer ? 100 : 50)
    }

    /// `expand`: abre a ilha por alguns segundos (em silêncio; o som é o da notificação).
    static func update(_ state: RideActivityAttributes.ContentState, expand: Bool = false) {
        let body = Self.content(state)
        for activity in Activity<RideActivityAttributes>.activities {
            Task {
                if expand {
                    await activity.update(body, alertConfiguration: AlertConfiguration(
                        title: "\(state.verdict)", body: "Novo chamado", sound: .named("di-silencio.wav")))
                } else {
                    await activity.update(body)
                }
            }
        }
    }

    static func end() {
        for activity in Activity<RideActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
#endif
