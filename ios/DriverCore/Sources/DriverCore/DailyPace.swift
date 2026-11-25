import Foundation

/// Meta do dia: quanto faturar, em quantos dias por semana, e até que horas vai o turno.
public struct DailyPlan: Equatable, Codable, Sendable {
    /// Meta de faturamento do dia. nil = meta da semana ÷ dias de trabalho.
    public var goal: Double?
    public var workdays: Int
    /// Hora em que o turno costuma acabar (0–23). Antes de `dayStartHour` conta como madrugada do mesmo turno.
    public var endHour: Int
    /// Corridas antes dessa hora contam no dia anterior (turno da noite que passa da meia-noite).
    public var dayStartHour: Int

    public init(goal: Double? = nil, workdays: Int = 6, endHour: Int = 3, dayStartHour: Int = 6) {
        self.goal = goal
        self.workdays = workdays
        self.endHour = endHour
        self.dayStartHour = dayStartHour
    }

    public func dailyGoal(weekly: WeeklyGoal) -> Double {
        if let goal, goal > 0 { return goal }
        return weekly.revenue / Double(max(1, workdays))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DailyPlan()
        goal = try c.decodeIfPresent(Double.self, forKey: .goal)
        workdays = try c.decodeIfPresent(Int.self, forKey: .workdays) ?? d.workdays
        endHour = try c.decodeIfPresent(Int.self, forKey: .endHour) ?? d.endHour
        dayStartHour = try c.decodeIfPresent(Int.self, forKey: .dayStartHour) ?? d.dayStartHour
    }
}

/// Como está o dia em relação à meta.
public struct PaceStatus: Equatable, Sendable {
    public var goal: Double
    public var earned: Double
    public var shiftEnd: Date
    public var hoursLeft: Double

    public var remaining: Double { max(0, goal - earned) }
    public var reached: Bool { earned >= goal - 0.005 }
    public var progress: Double { goal > 0 ? min(1, earned / goal) : 0 }
    /// Faturamento por hora necessário até o fim do turno. nil = o horário do turno já passou.
    public var neededPerHour: Double? {
        if reached { return 0 }
        return hoursLeft > 0.1 ? remaining / hoursLeft : nil
    }
}

public enum DailyPace {
    /// Início do dia de trabalho que contém `date` (às `dayStartHour`).
    public static func workdayStart(_ date: Date, plan: DailyPlan, calendar: Calendar = .current) -> Date {
        let shifted = calendar.date(byAdding: .hour, value: -plan.dayStartHour, to: date) ?? date
        let day = calendar.startOfDay(for: shifted)
        return calendar.date(byAdding: .hour, value: plan.dayStartHour, to: day) ?? day
    }

    /// Fim do turno do dia de trabalho que contém `date`.
    public static func shiftEnd(_ date: Date, plan: DailyPlan, calendar: Calendar = .current) -> Date {
        let start = workdayStart(date, plan: plan, calendar: calendar)
        let day = calendar.startOfDay(for: start)
        let h = plan.endHour <= plan.dayStartHour ? plan.endHour + 24 : plan.endHour
        return calendar.date(byAdding: .hour, value: h, to: day) ?? start
    }

    /// Soma do que entrou no dia de trabalho de `now`.
    public static func earned(_ entries: [(Date, Double)], now: Date, plan: DailyPlan, calendar: Calendar = .current) -> Double {
        let start = workdayStart(now, plan: plan, calendar: calendar)
        return entries.filter { $0.0 >= start && $0.0 <= now.addingTimeInterval(60) }.map(\.1).reduce(0, +)
    }

    public static func status(earned: Double, now: Date, plan: DailyPlan, weekly: WeeklyGoal,
                              calendar: Calendar = .current) -> PaceStatus {
        let end = shiftEnd(now, plan: plan, calendar: calendar)
        return PaceStatus(goal: plan.dailyGoal(weekly: weekly), earned: earned, shiftEnd: end,
                          hoursLeft: max(0, end.timeIntervalSince(now) / 3600))
    }
}

/// As contas de um chamado que interessam na hora de decidir.
public struct OfferEconomics: Equatable, Sendable {
    /// Valor − custo do carro (km total × custo por km).
    public var profit: Double?
    /// Preço base: o mínimo para não sair no prejuízo (só o custo do carro).
    public var breakEven: Double?
    /// Valor que mantém o ritmo da meta: minutos da corrida × R$/h necessário (nunca abaixo do preço base).
    public var goalFare: Double?
    /// R$/h usado no valor da meta.
    public var goalPerHour: Double?
    public var minutes: Double?

    public var meetsGoal: Bool? {
        guard let goalFare, let fare = profit.flatMap({ p in breakEven.map { p + $0 } }) else { return nil }
        return fare >= goalFare - 0.005
    }

    /// `neededPerHour`: ritmo da meta do dia; nunca usa menos que o piso por hora.
    public static func of(_ a: OfferAnalysis, costPerKm: Double, neededPerHour: Double?, hourFloor: Double) -> OfferEconomics {
        let km = a.financial.totalDistanceKm
        let cost = km.map { $0 * costPerKm }
        let profit: Double? = {
            guard let fare = a.offer.fare, let cost else { return nil }
            return fare - cost
        }()
        let minutes = a.realistic?.totalTimeMin ?? a.financial.totalTimeMin
        let perHour = max(neededPerHour ?? hourFloor, hourFloor)
        let goalFare = minutes.map { max(cost ?? 0, $0 * perHour / 60) }
        return OfferEconomics(profit: profit, breakEven: cost, goalFare: goalFare, goalPerHour: perHour, minutes: minutes)
    }
}
