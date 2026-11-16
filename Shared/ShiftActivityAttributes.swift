import ActivityKit
import Foundation

/// Dados da Live Activity (tela bloqueada e Dynamic Island).
struct ShiftActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isPaused: Bool
        var timerReference: Date
        var activeSeconds: Double
        var km: Double
        var net: Double
        var goal: Double
        var privacy: Bool
    }

    var startedAt: Date
}
