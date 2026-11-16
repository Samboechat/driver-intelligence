import Foundation

// MARK: - Estruturas de resultado

/// Resultado financeiro de um dia.
struct DayBreakdown: Identifiable {
    let id: UUID
    let day: Date
    let gross: Double
    let tips: Double
    let surge: Double
    let trips: Int
    let km: Double
    let productiveKm: Double
    let hours: Double
    let drivingHours: Double
    let pausedHours: Double
    let fuel: Double
    let fixed: Double
    let reserve: Double
    let extras: Double
    let excess: Double

    var variableCost: Double { fuel + extras + reserve + excess }
    var totalCost: Double { variableCost + fixed }
    var net: Double { gross - totalCost }
    var margin: Double { gross > 0 ? net / gross : 0 }
    var grossPerKm: Double { km > 0 ? gross / km : 0 }
    var netPerKm: Double { km > 0 ? net / km : 0 }
    var grossPerHour: Double { hours > 0 ? gross / hours : 0 }
    var netPerHour: Double { hours > 0 ? net / hours : 0 }
    var idleHours: Double { max(0, hours - drivingHours) }
    var surgeShare: Double { gross > 0 ? surge / gross : 0 }
    var avgTicket: Double { trips > 0 ? (gross - tips) / Double(trips) : 0 }
    var avgTripMinutes: Double { trips > 0 ? hours * 60 / Double(trips) : 0 }

    /// Fração de km rodados sem passageiro (nil se o motorista não informou km em corrida).
    var deadheadShare: Double? {
        guard productiveKm > 0, km > 0 else { return nil }
        return max(0, 1 - productiveKm / km)
    }
}

struct PeriodTotals {
    var days = 0
    var gross = 0.0
    var tips = 0.0
    var surge = 0.0
    var trips = 0
    var km = 0.0
    var productiveKm = 0.0
    var kmWithProductive = 0.0
    var hours = 0.0
    var drivingHours = 0.0
    var pausedHours = 0.0
    var fuel = 0.0
    var fixed = 0.0
    var reserve = 0.0
    var extras = 0.0
    var excess = 0.0

    init(_ list: [DayBreakdown] = []) {
        for item in list { add(item) }
    }

    mutating func add(_ b: DayBreakdown) {
        days += 1
        gross += b.gross
        tips += b.tips
        surge += b.surge
        trips += b.trips
        km += b.km
        hours += b.hours
        drivingHours += b.drivingHours
        pausedHours += b.pausedHours
        fuel += b.fuel
        fixed += b.fixed
        reserve += b.reserve
        extras += b.extras
        excess += b.excess
        if b.productiveKm > 0 {
            productiveKm += b.productiveKm
            kmWithProductive += b.km
        }
    }

    var variableCost: Double { fuel + extras + reserve + excess }
    var net: Double { gross - variableCost - fixed }
    var margin: Double { gross > 0 ? net / gross : 0 }
    var grossPerKm: Double { km > 0 ? gross / km : 0 }
    var netPerKm: Double { km > 0 ? net / km : 0 }
    var grossPerHour: Double { hours > 0 ? gross / hours : 0 }
    var netPerHour: Double { hours > 0 ? net / hours : 0 }
    var idleHours: Double { max(0, hours - drivingHours) }
    var surgeShare: Double { gross > 0 ? surge / gross : 0 }
    var avgTicket: Double { trips > 0 ? (gross - tips) / Double(trips) : 0 }
    var avgTripMinutes: Double { trips > 0 ? hours * 60 / Double(trips) : 0 }
    var deadheadShare: Double? {
        guard productiveKm > 0, kmWithProductive > 0 else { return nil }
        return max(0, 1 - productiveKm / kmWithProductive)
    }
}

/// Demonstrativo de resultado (DRE) de um período.
struct DREReport {
    let interval: DateInterval
    let totals: PeriodTotals
    let idleDays: Int
    let idleFixedCost: Double
    let coveredByDayOffBank: Double

    var variableCosts: Double { totals.variableCost }
    var fixedCosts: Double { totals.fixed + idleFixedCost }
    var net: Double { totals.gross - variableCosts - fixedCosts }
    var margin: Double { totals.gross > 0 ? net / totals.gross : 0 }
}

struct WeeklyGoalStatus {
    let goal: Double
    let netBeforeToday: Double
    let todayNet: Double
    let remainingDays: Int
    let baseDaily: Double
    /// Meta de hoje já reajustada pelo desempenho dos dias anteriores.
    let todayTarget: Double
    let interval: DateInterval

    var netSoFar: Double { netBeforeToday + todayNet }
    var remaining: Double { max(0, goal - netSoFar) }
    var reached: Bool { goal > 0 && netSoFar >= goal }
    var progress: Double { goal > 0 ? min(1, max(0, netSoFar / goal)) : 0 }
    var adjustment: Double { todayTarget - baseDaily }
}

struct RunRate {
    let daysWorked: Int
    let grossSoFar: Double
    let netSoFar: Double
    let avgNetPerWorkedDay: Double
    let avgGrossPerWorkedDay: Double
    let remainingWorkDays: Int
    let projectedGross: Double
    let projectedNet: Double
}

struct CostPerKm {
    let fuel: Double
    let reserve: Double
    let fixed: Double
    let avgDailyKm: Double

    var variable: Double { fuel + reserve }
    var total: Double { fuel + reserve + fixed }
}

/// Situação do dia em andamento (turno aberto + resumo já fechado do dia).
struct LiveDay {
    let gross: Double
    let km: Double
    let hours: Double
    let fuel: Double
    let fixed: Double
    let reserve: Double
    let extras: Double

    var breakEvenTarget: Double { fixed + fuel + extras }
    var breakEvenProgress: Double {
        guard breakEvenTarget > 0 else { return gross > 0 ? 1 : 0 }
        return min(1, max(0, gross / breakEvenTarget))
    }
    var isPaid: Bool { gross > 0 && gross >= breakEvenTarget }
    var missing: Double { max(0, breakEvenTarget - gross) }
    var net: Double { gross - fixed - fuel - reserve - extras }
    var grossPerKm: Double { km > 0 ? gross / km : 0 }
    var grossPerHour: Double { hours > 0 ? gross / hours : 0 }
    var netPerKm: Double { km > 0 ? net / km : 0 }
    var netPerHour: Double { hours > 0 ? net / hours : 0 }
}

struct CategoryPerformance: Identifiable {
    let category: RideCategory
    let gross: Double
    let net: Double
    let hours: Double
    let km: Double
    let trips: Int
    /// true quando horas/km por categoria foram rateados (motorista não detalhou).
    let estimated: Bool

    var id: String { category.rawValue }
    var netPerHour: Double { hours > 0 ? net / hours : 0 }
    var netPerKm: Double { km > 0 ? net / km : 0 }
    var grossPerHour: Double { hours > 0 ? gross / hours : 0 }
    var grossPerKm: Double { km > 0 ? gross / km : 0 }
    var margin: Double { gross > 0 ? net / gross : 0 }
}

struct ProfileBucket: Identifiable {
    let title: String
    let totals: PeriodTotals
    var id: String { title }
}

struct TripSimulation {
    let totalKm: Double
    let hours: Double
    let variableCost: Double
    let fullCost: Double
    let net: Double
    let grossPerKm: Double
    let grossPerHour: Double
    let netPerHour: Double
    let paysCosts: Bool
    let kmSignal: Signal
    let hourSignal: Signal

    var worthIt: Bool { paysCosts && hourSignal != .red && kmSignal != .red }
}

struct OdometerAudit {
    let days: Int
    let gpsKm: Double
    let odometerKm: Double
    /// Odômetro ÷ GPS. Acima de 1 = GPS contando a menos.
    var factor: Double { gpsKm > 0 ? odometerKm / gpsKm : 1 }
    var differencePct: Double { (factor - 1) * 100 }
}

// MARK: - Motor financeiro

/// Engenharia de custos reais: transforma resumos, despesas e perfil do veículo em lucro líquido.
struct FinanceEngine {
    /// Resumos ordenados por dia; `breakdowns` segue a mesma ordem.
    let summaries: [DailySummary]
    let breakdowns: [DayBreakdown]
    let vehicle: VehicleProfile
    let settings: AppSettings
    let fuel: FuelAnalysis
    let dayOffs: [DayOff]
    let movements: [VaultMovement]
    let workWeekdays: Set<Int>
    private let extrasByDay: [Date: Double]
    private let indexByDay: [Date: Int]

    init(summaries: [DailySummary],
         expenses: [Expense],
         fuelEntries: [FuelEntry],
         vehicle: VehicleProfile,
         settings: AppSettings,
         dayOffs: [DayOff],
         movements: [VaultMovement],
         workWeekdays: Set<Int>) {
        let calendar = Calendar.br
        let sorted = summaries.sorted { $0.day < $1.day }
        let analysis = FuelAnalysis(entries: fuelEntries, vehicle: vehicle)

        var extras: [Date: Double] = [:]
        for expense in expenses {
            extras[calendar.startOfDay(for: expense.date), default: 0] += expense.amount
        }

        let franchise = vehicle.mode == .rented ? vehicle.franchiseKm : 0
        var cumulativeKm: [Date: Double] = [:]
        var list: [DayBreakdown] = []
        var index: [Date: Int] = [:]

        for summary in sorted {
            let km = summary.costKm
            var excess = 0.0
            if franchise > 0 {
                let key = FinanceEngine.periodStart(for: summary.day, period: vehicle.rentPeriod)
                let before = cumulativeKm[key, default: 0]
                let after = before + km
                excess = (max(0, after - franchise) - max(0, before - franchise)) * vehicle.excessFeePerKm
                cumulativeKm[key] = after
            }
            let perKm = summary.fuelCostPerKm > 0 ? summary.fuelCostPerKm : analysis.currentCostPerKm
            let fuelCost = summary.manualFuelCost ?? km * perKm
            let breakdown = DayBreakdown(
                id: summary.id,
                day: summary.day,
                gross: summary.totalGross,
                tips: summary.tips,
                surge: summary.surge,
                trips: summary.totalTrips,
                km: km,
                productiveKm: summary.productiveKm,
                hours: summary.activeHours,
                drivingHours: summary.drivingHours,
                pausedHours: summary.pausedHours,
                fuel: fuelCost,
                fixed: summary.fixedCost,
                reserve: summary.reserveCost,
                extras: extras[summary.day] ?? 0,
                excess: excess
            )
            index[summary.day] = list.count
            list.append(breakdown)
        }

        self.summaries = sorted
        self.breakdowns = list
        self.vehicle = vehicle
        self.settings = settings
        self.fuel = analysis
        self.dayOffs = dayOffs
        self.movements = movements
        self.workWeekdays = workWeekdays.isEmpty ? [2, 3, 4, 5, 6, 7] : workWeekdays
        self.extrasByDay = extras
        self.indexByDay = index
    }

    static func periodStart(for day: Date, period: RentPeriod) -> Date {
        let component: Calendar.Component = period == .weekly ? .weekOfYear : .month
        return Calendar.br.dateInterval(of: component, for: day)?.start ?? day
    }

    // MARK: Consultas por dia

    func summary(on day: Date) -> DailySummary? {
        guard let index = indexByDay[Calendar.br.startOfDay(for: day)] else { return nil }
        return summaries[index]
    }

    func breakdown(on day: Date) -> DayBreakdown? {
        guard let index = indexByDay[Calendar.br.startOfDay(for: day)] else { return nil }
        return breakdowns[index]
    }

    func extras(on day: Date) -> Double {
        extrasByDay[Calendar.br.startOfDay(for: day)] ?? 0
    }

    func breakdowns(in interval: DateInterval) -> [DayBreakdown] {
        breakdowns.filter { $0.day >= interval.start && $0.day < interval.end }
    }

    func breakdowns(since date: Date) -> [DayBreakdown] {
        breakdowns.filter { $0.day >= date }
    }

    // MARK: Custos

    /// Reserva de manutenção (cofre virtual) para um dia.
    func reserveCost(gross: Double, km: Double) -> Double {
        switch settings.vaultMode {
        case .perKm: return km * settings.vaultPerKm
        case .percent: return gross * settings.vaultPct / 100
        }
    }

    /// Multa de franquia gerada por `km` rodados em `day`, considerando o acumulado do período.
    func excessCost(day: Date, km: Double) -> Double {
        guard vehicle.mode == .rented, vehicle.franchiseKm > 0 else { return 0 }
        let target = Calendar.br.startOfDay(for: day)
        let key = FinanceEngine.periodStart(for: target, period: vehicle.rentPeriod)
        var before = 0.0
        for summary in summaries where summary.day < target {
            if FinanceEngine.periodStart(for: summary.day, period: vehicle.rentPeriod) == key {
                before += summary.costKm
            }
        }
        let after = before + km
        return (max(0, after - vehicle.franchiseKm) - max(0, before - vehicle.franchiseKm)) * vehicle.excessFeePerKm
    }

    /// Km acumulados e franquia do período de contrato atual (carro alugado).
    func franchiseStatus(now: Date = Date()) -> (used: Double, limit: Double, excessCost: Double)? {
        guard vehicle.mode == .rented, vehicle.franchiseKm > 0 else { return nil }
        let key = FinanceEngine.periodStart(for: now, period: vehicle.rentPeriod)
        var used = 0.0
        for summary in summaries where FinanceEngine.periodStart(for: summary.day, period: vehicle.rentPeriod) == key {
            used += summary.costKm
        }
        let cost = max(0, used - vehicle.franchiseKm) * vehicle.excessFeePerKm
        return (used, vehicle.franchiseKm, cost)
    }

    /// Resultado de um dia ainda não salvo (pré-visualização do editor de resumo).
    func previewBreakdown(day: Date, gross: Double, tips: Double, surge: Double, trips: Int,
                          km: Double, productiveKm: Double, hours: Double, drivingHours: Double,
                          pausedHours: Double, fuelPerKm: Double, manualFuel: Double?, fixed: Double) -> DayBreakdown {
        let perKm = fuelPerKm > 0 ? fuelPerKm : fuel.currentCostPerKm
        return DayBreakdown(
            id: UUID(),
            day: Calendar.br.startOfDay(for: day),
            gross: gross,
            tips: tips,
            surge: surge,
            trips: trips,
            km: km,
            productiveKm: productiveKm,
            hours: hours,
            drivingHours: drivingHours,
            pausedHours: pausedHours,
            fuel: manualFuel ?? km * perKm,
            fixed: fixed,
            reserve: reserveCost(gross: gross, km: km),
            extras: extras(on: day),
            excess: excessCost(day: day, km: km)
        )
    }

    /// Dia em andamento: soma o resumo já fechado do dia com o turno aberto.
    func liveDay(day: Date, shiftGross: Double, shiftKm: Double, shiftSeconds: Double) -> LiveDay {
        let base = breakdown(on: day)
        let gross = (base?.gross ?? 0) + shiftGross
        let km = (base?.km ?? 0) + shiftKm
        let hours = (base?.hours ?? 0) + shiftSeconds / 3600
        let fuelCost = (base?.fuel ?? 0) + shiftKm * fuel.currentCostPerKm
        return LiveDay(
            gross: gross,
            km: km,
            hours: hours,
            fuel: fuelCost,
            fixed: base?.fixed ?? vehicle.dailyFixedCost,
            reserve: reserveCost(gross: gross, km: km),
            extras: extras(on: day)
        )
    }

    // MARK: Semáforo

    static func signal(_ value: Double, floor: Double, marginPct: Double) -> Signal {
        guard value > 0, floor > 0 else { return .neutral }
        if value >= floor { return .green }
        if value >= floor * (1 - marginPct / 100) { return .yellow }
        return .red
    }

    func signal(perKm value: Double) -> Signal {
        FinanceEngine.signal(value, floor: settings.minPerKm, marginPct: settings.yellowMarginPct)
    }

    func signal(perHour value: Double) -> Signal {
        FinanceEngine.signal(value, floor: settings.minPerHour, marginPct: settings.yellowMarginPct)
    }

    // MARK: DRE e projeção

    func dre(_ interval: DateInterval, now: Date = Date()) -> DREReport {
        let calendar = Calendar.br
        let totals = PeriodTotals(breakdowns(in: interval))
        var idleDays = 0
        var covered = 0.0
        if let firstDay = breakdowns.first?.day {
            let today = calendar.startOfDay(for: now)
            let limit = min(interval.end, calendar.date(byAdding: .day, value: 1, to: today) ?? interval.end)
            var cursor = max(interval.start, firstDay)
            while cursor < limit {
                if indexByDay[cursor] == nil { idleDays += 1 }
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? limit
            }
            for dayOff in dayOffs where dayOff.day >= interval.start && dayOff.day < interval.end {
                covered += dayOff.coveredCost
            }
        }
        return DREReport(
            interval: interval,
            totals: totals,
            idleDays: idleDays,
            idleFixedCost: Double(idleDays) * vehicle.dailyFixedCost,
            coveredByDayOffBank: covered
        )
    }

    /// Projeção do mês mantendo o ritmo atual de lucro por dia trabalhado.
    func runRate(now: Date = Date()) -> RunRate {
        let calendar = Calendar.br
        let today = calendar.startOfDay(for: now)
        let month = calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: today, duration: 30 * 86400)
        let report = dre(month, now: now)
        let worked = report.totals.days
        let avgNet = worked > 0 ? report.totals.net / Double(worked) : 0
        let avgGross = worked > 0 ? report.totals.gross / Double(worked) : 0
        var remainingWork = 0
        var remainingRest = 0
        var cursor = calendar.date(byAdding: .day, value: 1, to: today) ?? month.end
        while cursor < month.end {
            if workWeekdays.contains(calendar.component(.weekday, from: cursor)) {
                remainingWork += 1
            } else {
                remainingRest += 1
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? month.end
        }
        let projectedNet = report.net + avgNet * Double(remainingWork) - vehicle.dailyFixedCost * Double(remainingRest)
        return RunRate(
            daysWorked: worked,
            grossSoFar: report.totals.gross,
            netSoFar: report.net,
            avgNetPerWorkedDay: avgNet,
            avgGrossPerWorkedDay: avgGross,
            remainingWorkDays: remainingWork,
            projectedGross: report.totals.gross + avgGross * Double(remainingWork),
            projectedNet: projectedNet
        )
    }

    // MARK: Meta semanal auto-ajustável

    func weeklyGoal(now: Date = Date()) -> WeeklyGoalStatus {
        let calendar = Calendar.br
        let today = calendar.startOfDay(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: today, duration: 7 * 86400)
        var before = 0.0
        var todayNet = 0.0
        for item in breakdowns where item.day >= week.start && item.day < week.end {
            if item.day < today {
                before += item.net
            } else if item.day == today {
                todayNet += item.net
            }
        }
        let offDays = Set(dayOffs.map { $0.day })
        var remainingDays = 0
        var cursor = today
        while cursor < week.end {
            let weekday = calendar.component(.weekday, from: cursor)
            if workWeekdays.contains(weekday) && !offDays.contains(cursor) {
                remainingDays += 1
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? week.end
        }
        let goal = settings.weeklyNetGoal
        let needed = max(0, goal - before)
        return WeeklyGoalStatus(
            goal: goal,
            netBeforeToday: before,
            todayNet: todayNet,
            remainingDays: remainingDays,
            baseDaily: baseDailyGoal,
            todayTarget: remainingDays > 0 ? needed / Double(remainingDays) : needed,
            interval: week
        )
    }

    /// Meta diária "cheia": meta semanal ÷ dias de trabalho do cronograma.
    var baseDailyGoal: Double {
        settings.weeklyNetGoal / Double(max(1, workWeekdays.count))
    }

    // MARK: Custo por km (CPK dinâmico)

    func costPerKm(now: Date = Date()) -> CostPerKm {
        let calendar = Calendar.br
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let firstDay = breakdowns.first?.day ?? today
        let start = max(windowStart, firstDay)
        let elapsed = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        let days = Double(max(1, elapsed + 1))
        var km = 0.0
        var gross = 0.0
        for item in breakdowns where item.day >= start {
            km += item.km
            gross += item.gross
        }
        let avgDailyKm = km / days
        let reservePerKm: Double
        switch settings.vaultMode {
        case .perKm: reservePerKm = settings.vaultPerKm
        case .percent: reservePerKm = km > 0 ? gross * settings.vaultPct / 100 / km : 0
        }
        return CostPerKm(
            fuel: fuel.currentCostPerKm,
            reserve: reservePerKm,
            fixed: avgDailyKm > 0 ? vehicle.dailyFixedCost / avgDailyKm : 0,
            avgDailyKm: avgDailyKm
        )
    }

    // MARK: Simulador de viabilidade

    func simulate(fare: Double, tripKm: Double, returnKm: Double, minutes: Double, now: Date = Date()) -> TripSimulation {
        let cpk = costPerKm(now: now)
        let totalKm = max(0, tripKm) + max(0, returnKm)
        let hours = max(0, minutes) / 60
        let variableCost = totalKm * cpk.variable
        let net = fare - variableCost
        let grossPerKm = totalKm > 0 ? fare / totalKm : 0
        let grossPerHour = hours > 0 ? fare / hours : 0
        return TripSimulation(
            totalKm: totalKm,
            hours: hours,
            variableCost: variableCost,
            fullCost: totalKm * cpk.total,
            net: net,
            grossPerKm: grossPerKm,
            grossPerHour: grossPerHour,
            netPerHour: hours > 0 ? net / hours : 0,
            paysCosts: fare > totalKm * cpk.total,
            kmSignal: signal(perKm: grossPerKm),
            hourSignal: signal(perHour: grossPerHour)
        )
    }

    // MARK: Rentabilidade por categoria

    func categoryPerformance(since date: Date) -> [CategoryPerformance] {
        struct Accumulator {
            var gross = 0.0
            var cost = 0.0
            var hours = 0.0
            var km = 0.0
            var trips = 0
            var estimated = false
        }
        var totals: [RideCategory: Accumulator] = [:]

        for (index, summary) in summaries.enumerated() where summary.day >= date {
            let day = breakdowns[index]
            let figures = summary.figures
            let categoriesGross = summary.categoriesGross
            guard categoriesGross > 0 else { continue }
            let dayTrips = Double(summary.totalTrips)
            let informedHours = figures.values.reduce(0) { $0 + $1.hours }
            let informedKm = figures.values.reduce(0) { $0 + $1.km }

            for category in RideCategory.allCases {
                guard let item = figures[category], item.gross > 0 else { continue }
                let grossShare = item.gross / categoriesGross
                let tripShare = dayTrips > 0 ? Double(item.trips) / dayTrips : grossShare
                let hourShare = informedHours > 0 ? item.hours / informedHours : tripShare
                let kmShare = informedKm > 0 ? item.km / informedKm : tripShare

                var entry = totals[category] ?? Accumulator()
                entry.gross += item.gross + (day.tips + day.surge) * grossShare
                entry.cost += (day.fuel + day.reserve + day.excess) * kmShare + (day.fixed + day.extras) * hourShare
                entry.hours += day.hours * hourShare
                entry.km += day.km * kmShare
                entry.trips += item.trips
                if informedHours <= 0 || informedKm <= 0 { entry.estimated = true }
                totals[category] = entry
            }
        }

        return RideCategory.allCases.compactMap { category in
            guard let entry = totals[category] else { return nil }
            return CategoryPerformance(
                category: category,
                gross: entry.gross,
                net: entry.gross - entry.cost,
                hours: entry.hours,
                km: entry.km,
                trips: entry.trips,
                estimated: entry.estimated
            )
        }
    }

    // MARK: Perfil de corrida (ticket médio)

    func tripProfile(since date: Date) -> [ProfileBucket] {
        var short = PeriodTotals()
        var medium = PeriodTotals()
        var long = PeriodTotals()
        for item in breakdowns where item.day >= date && item.trips > 0 {
            if item.avgTicket < settings.shortTicketLimit {
                short.add(item)
            } else if item.avgTicket <= settings.longTicketLimit {
                medium.add(item)
            } else {
                long.add(item)
            }
        }
        let shortTitle = "Curtas (ticket < \(Fmt.brl(settings.shortTicketLimit)))"
        let mediumTitle = "Médias (\(Fmt.brl(settings.shortTicketLimit)) a \(Fmt.brl(settings.longTicketLimit)))"
        let longTitle = "Longas (ticket > \(Fmt.brl(settings.longTicketLimit)))"
        return [
            ProfileBucket(title: shortTitle, totals: short),
            ProfileBucket(title: mediumTitle, totals: medium),
            ProfileBucket(title: longTitle, totals: long)
        ]
    }

    // MARK: Auditoria de odômetro

    func odometerAudit(since date: Date) -> OdometerAudit {
        var days = 0
        var gps = 0.0
        var odometer = 0.0
        for summary in summaries where summary.day >= date && summary.odometerKm > 0 && summary.gpsKm > 0 {
            days += 1
            gps += summary.gpsKm
            odometer += summary.odometerKm
        }
        return OdometerAudit(days: days, gpsKm: gps, odometerKm: odometer)
    }

    // MARK: Cofre virtual e banco de folga

    var vaultCredits: Double {
        breakdowns.reduce(0) { $0 + $1.reserve }
    }

    var vaultWithdrawals: Double {
        movements.filter { $0.kind == .maintenance }.reduce(0) { $0 + $1.amount }
    }

    var vaultBalance: Double { vaultCredits - vaultWithdrawals }

    /// Parte do excedente diário (acima da meta diária cheia) enviada ao banco de folga.
    func dayOffCredit(for item: DayBreakdown) -> Double {
        max(0, item.net - baseDailyGoal) * settings.dayOffBankPct / 100
    }

    var dayOffCredits: Double {
        breakdowns.reduce(0) { $0 + dayOffCredit(for: $1) }
    }

    var dayOffDebits: Double {
        dayOffs.reduce(0) { $0 + $1.coveredCost }
            + movements.filter { $0.kind == .dayOff }.reduce(0) { $0 + $1.amount }
    }

    var dayOffBalance: Double { dayOffCredits - dayOffDebits }

    /// Quantos dias de folga o saldo atual cobre.
    var dayOffDaysCovered: Double {
        vehicle.dailyFixedCost > 0 ? max(0, dayOffBalance) / vehicle.dailyFixedCost : 0
    }
}
