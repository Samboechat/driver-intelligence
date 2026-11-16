import Foundation

/// Retrato do turno gravado pelo app e lido pelos widgets.
struct SharedShiftState: Codable, Equatable {
    enum Status: String, Codable {
        case idle, running, paused
    }

    var status: Status = .idle
    /// "Início virtual" do cronômetro: agora − tempo ativo (para Text(style: .timer)).
    var timerReference: Date = Date()
    var activeSeconds: Double = 0
    var km: Double = 0
    var grossToday: Double = 0
    var netToday: Double = 0
    var goalToday: Double = 0
    var privacy: Bool = false
    var updatedAt: Date = Date()

    private static let storageKey = "driverpro.shared.shift"

    static func load() -> SharedShiftState {
        guard let data = AppGroup.defaults.data(forKey: storageKey),
              let state = try? JSONDecoder().decode(SharedShiftState.self, from: data) else {
            return SharedShiftState()
        }
        return state
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            AppGroup.defaults.set(data, forKey: SharedShiftState.storageKey)
        }
    }
}

enum ShiftCommand: String, Codable {
    case start, pause, resume, toggle, end
}

/// Fila de 1 comando usada quando um intent roda fora do processo do app.
enum PendingCommandStore {
    private static let storageKey = "driverpro.pending.command"

    static func push(_ command: ShiftCommand) {
        AppGroup.defaults.set(command.rawValue, forKey: storageKey)
    }

    static func pop() -> ShiftCommand? {
        guard let raw = AppGroup.defaults.string(forKey: storageKey) else { return nil }
        AppGroup.defaults.removeObject(forKey: storageKey)
        return ShiftCommand(rawValue: raw)
    }
}
