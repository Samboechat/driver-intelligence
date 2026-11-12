import Foundation

/// Meta da semana (segunda a domingo).
public struct WeeklyGoal: Equatable, Codable, Sendable {
    public var revenue: Double
    public var hoursOnline: Double

    public init(revenue: Double = 2820, hoursOnline: Double = 56) {
        self.revenue = revenue
        self.hoursOnline = hoursOnline
    }
}

/// Turno de trabalho, com o hodômetro do carro no início e no fim.
public struct Shift: Equatable, Codable, Sendable, Identifiable {
    public var id: String
    public var start: Date
    public var end: Date?
    public var odometerStart: Double?
    public var odometerEnd: Double?
    /// Km medidos pelo GPS durante o turno.
    public var gpsKm: Double?
    /// Turno aberto sozinho ao ligar a leitura.
    public var auto: Bool?

    public init(id: String = UUID().uuidString, start: Date, end: Date? = nil, odometerStart: Double? = nil, odometerEnd: Double? = nil,
                gpsKm: Double? = nil, auto: Bool? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.odometerStart = odometerStart
        self.odometerEnd = odometerEnd
        self.gpsKm = gpsKm
        self.auto = auto
    }

    public var isOpen: Bool { end == nil }

    /// Km pelo painel do carro (nil sem as duas leituras ou com leitura final menor que a inicial).
    public var odometerKm: Double? {
        guard let a = odometerStart, let b = odometerEnd, b >= a else { return nil }
        return b - a
    }

    /// Km rodados no turno: o painel do carro vale mais; sem ele, o GPS.
    public var kmDriven: Double? {
        odometerKm ?? gpsKm.flatMap { $0 > 0.05 ? $0 : nil }
    }

    /// De onde veio o número de `kmDriven`.
    public var kmSource: String? {
        if odometerKm != nil { return "painel" }
        return kmDriven != nil ? "GPS" : nil
    }

    public func hours(until now: Date) -> Double {
        max(0, (end ?? now).timeIntervalSince(start)) / 3600
    }
}

public enum WeekMath {
    /// Semana de segunda 00:00 a segunda 00:00 que contém `date`.
    public static func week(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        var cal = calendar
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let start = cal.date(from: comps) ?? cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86400)
        return DateInterval(start: start, end: end)
    }

    /// Horas de turno dentro do intervalo (turno aberto conta até `now`; turnos que cruzam a virada são cortados).
    public static func hoursOnline(_ shifts: [Shift], in interval: DateInterval, now: Date) -> Double {
        shifts.reduce(0) { total, s in
            let a = max(s.start, interval.start)
            let b = min(s.end ?? now, interval.end)
            return total + max(0, b.timeIntervalSince(a)) / 3600
        }
    }

    /// Fração 0...1 de uma meta (0 se a meta for inválida).
    public static func progress(_ value: Double, of goal: Double) -> Double {
        guard goal > 0, value.isFinite else { return 0 }
        return min(1, max(0, value / goal))
    }
}
