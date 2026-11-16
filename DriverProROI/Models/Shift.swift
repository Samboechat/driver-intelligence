import Foundation
import SwiftData

struct RoutePoint: Codable, Hashable {
    var lat: Double
    var lon: Double
    var t: Date
    var speed: Double
}

struct PauseRecord: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var start: Date
    var end: Date?
    var lat: Double?
    var lon: Double?
}

/// Corrida lançada durante o turno (alimenta break-even, alerta de R$/h e faixas horárias).
struct LiveEntry: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var category: String
    var amount: Double
}

@Model
final class Shift {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?
    var statusRaw: String = ShiftStatus.running.rawValue
    /// Tempo ativo acumulado até a última pausa (segundos).
    var activeSeconds: Double = 0
    var pausedSeconds: Double = 0
    var drivingSeconds: Double = 0
    var gpsKm: Double = 0
    /// Preenchido enquanto o turno está rodando.
    var lastResumeAt: Date?
    /// Preenchido enquanto o turno está pausado.
    var pauseStartedAt: Date?
    var startLat: Double?
    var startLon: Double?
    var endLat: Double?
    var endLon: Double?
    @Attribute(.externalStorage) var routeData: Data?
    var pausesData: Data?
    var entriesData: Data?
    var mergedIntoSummary: Bool = false

    init(startedAt: Date = Date()) {
        self.id = UUID()
        self.startedAt = startedAt
        self.lastResumeAt = startedAt
    }

    var status: ShiftStatus {
        get { ShiftStatus(rawValue: statusRaw) ?? .finished }
        set { statusRaw = newValue.rawValue }
    }

    /// Dia contábil do turno (dia em que começou).
    var day: Date { Calendar.br.startOfDay(for: startedAt) }

    var route: [RoutePoint] {
        get { Blob.decode([RoutePoint].self, from: routeData) ?? [] }
        set { routeData = Blob.encode(newValue) }
    }

    var pauses: [PauseRecord] {
        get { Blob.decode([PauseRecord].self, from: pausesData) ?? [] }
        set { pausesData = Blob.encode(newValue) }
    }

    var entries: [LiveEntry] {
        get { Blob.decode([LiveEntry].self, from: entriesData) ?? [] }
        set { entriesData = Blob.encode(newValue) }
    }

    func currentActiveSeconds(at date: Date) -> Double {
        var total = activeSeconds
        if status == .running, let resume = lastResumeAt {
            total += max(0, date.timeIntervalSince(resume))
        }
        return total
    }

    func currentPausedSeconds(at date: Date) -> Double {
        var total = pausedSeconds
        if status == .paused, let start = pauseStartedAt {
            total += max(0, date.timeIntervalSince(start))
        }
        return total
    }

    /// Intervalos efetivamente trabalhados (turno menos pausas).
    func activeIntervals(now: Date = Date()) -> [DateInterval] {
        let end = endedAt ?? now
        guard end > startedAt else { return [] }
        var result: [DateInterval] = []
        var cursor = startedAt
        for pause in pauses.sorted(by: { $0.start < $1.start }) {
            let pauseStart = min(max(pause.start, startedAt), end)
            let pauseEnd = min(max(pause.end ?? end, pauseStart), end)
            if pauseStart > cursor {
                result.append(DateInterval(start: cursor, end: pauseStart))
            }
            cursor = max(cursor, pauseEnd)
        }
        if end > cursor {
            result.append(DateInterval(start: cursor, end: end))
        }
        return result
    }
}
