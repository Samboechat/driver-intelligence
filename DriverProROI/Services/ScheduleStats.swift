import Foundation

struct BandStat {
    var plannedHours = 0.0
    var doneHours = 0.0
    var historyHours = 0.0
    var historyGross = 0.0

    /// R$/hora bruto médio da faixa (só com amostra mínima de 30 min).
    var avgPerHour: Double { historyHours >= 0.5 ? historyGross / historyHours : 0 }
    var completion: Double { plannedHours > 0 ? min(1, doneHours / plannedHours) : 0 }
}

/// Planejado vs. Realizado do cronograma e R$/hora médio por faixa horária.
struct ScheduleStats {
    private(set) var bands: [UUID: BandStat] = [:]
    private(set) var plannedWeek = 0.0
    private(set) var doneInBlocksWeek = 0.0
    private(set) var workedWeek = 0.0

    var completion: Double { plannedWeek > 0 ? min(1, doneInBlocksWeek / plannedWeek) : 0 }
    var outsideBlocksWeek: Double { max(0, workedWeek - doneInBlocksWeek) }

    init(blocks: [ScheduleBlock], shifts: [Shift], summaries: [DailySummary], dayOffs: [DayOff],
         now: Date = Date(), historyWeeks: Int = 8) {
        let calendar = Calendar.br
        let today = calendar.startOfDay(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: today, duration: 7 * 86400)
        let historyStart = calendar.date(byAdding: .weekOfYear, value: -historyWeeks, to: week.start) ?? week.start
        let working = blocks.filter { $0.countsAsWork }
        let offDays = Set(dayOffs.map { $0.day })

        // Planejado da semana atual.
        var cursor = week.start
        while cursor < week.end {
            let weekday = calendar.component(.weekday, from: cursor)
            if !offDays.contains(cursor) {
                for block in working where block.weekday == weekday {
                    bands[block.id, default: BandStat()].plannedHours = block.durationHours
                    plannedWeek += block.durationHours
                }
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? week.end
        }

        var grossByDay: [Date: Double] = [:]
        for summary in summaries {
            grossByDay[summary.day] = summary.totalGross
            if summary.day >= week.start && summary.day < week.end {
                workedWeek += summary.activeHours
            }
        }

        let recent = shifts.filter { $0.startedAt >= historyStart }
        let grouped = Dictionary(grouping: recent) { $0.day }

        for (day, dayShifts) in grouped {
            let weekday = calendar.component(.weekday, from: day)
            let previousDay = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            let previousWeekday = calendar.component(.weekday, from: previousDay)

            // Blocos do dia + blocos da véspera que atravessam a meia-noite.
            var candidates: [(block: ScheduleBlock, interval: DateInterval)] = []
            for block in working {
                if block.weekday == weekday {
                    candidates.append((block, block.interval(onDay: day)))
                } else if block.weekday == previousWeekday && block.endMinute <= block.startMinute {
                    candidates.append((block, block.interval(onDay: previousDay)))
                }
            }
            guard !candidates.isEmpty else { continue }

            let intervals = dayShifts.flatMap { $0.activeIntervals(now: now) }
            let entries = dayShifts.flatMap { $0.entries }
            let totalSeconds = intervals.reduce(0) { $0 + $1.duration }
            let totalEntries = entries.reduce(0) { $0 + $1.amount }
            let dayGross = grossByDay[day] ?? totalEntries
            let inCurrentWeek = day >= week.start && day < week.end

            for candidate in candidates {
                var seconds = 0.0
                for interval in intervals {
                    seconds += interval.intersection(with: candidate.interval)?.duration ?? 0
                }
                guard seconds > 0 else { continue }

                // Rateio do bruto do dia: pelas corridas lançadas (se houver) ou pelo tempo ativo.
                var share = 0.0
                if totalEntries > 0 {
                    let inside = entries.filter { candidate.interval.contains($0.date) }.reduce(0) { $0 + $1.amount }
                    share = inside / totalEntries
                } else if totalSeconds > 0 {
                    share = seconds / totalSeconds
                }

                var stat = bands[candidate.block.id] ?? BandStat()
                stat.historyHours += seconds / 3600
                stat.historyGross += dayGross * share
                if inCurrentWeek {
                    stat.doneHours += seconds / 3600
                    doneInBlocksWeek += seconds / 3600
                }
                bands[candidate.block.id] = stat
            }
        }
    }

    func stat(for block: ScheduleBlock) -> BandStat {
        bands[block.id] ?? BandStat()
    }
}
