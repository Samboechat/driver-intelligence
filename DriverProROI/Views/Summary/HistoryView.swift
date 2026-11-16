import SwiftData
import SwiftUI

/// Histórico de resumos diários + DRE.
struct HistoryView: View {
    let engine: FinanceEngine

    @Environment(\.modelContext) private var context
    @AppStorage("privacyMode") private var privacy = false
    @Query(sort: \Shift.startedAt, order: .reverse) private var shifts: [Shift]
    @State private var mode = 0
    @State private var editing: DayRef?
    @State private var replay: DayRef?
    @State private var adding = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Visão", selection: $mode) {
                Text("Dias").tag(0)
                Text("DRE").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if mode == 0 {
                daysList
            } else {
                DREView(engine: engine)
            }
        }
        .screenBackground()
        .navigationTitle("Resumos")
        .navigationBarTitleDisplayMode(.inline)
        .privacyToolbar()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    adding = true
                } label: {
                    Label("Lançar dia manualmente", systemImage: "plus.circle.fill")
                        .font(.title3)
                }
            }
        }
        .sheet(item: $editing) { reference in
            NavigationStack {
                SummaryEditorView(day: reference.day, engine: engine, allowsDayChange: false)
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                SummaryEditorView(day: Date(), engine: engine, allowsDayChange: true)
            }
        }
        .navigationDestination(item: $replay) { reference in
            RouteReplayView(day: reference.day)
        }
    }

    private var routeDays: Set<Date> {
        Set(shifts.filter { $0.status == .finished }.map { $0.day })
    }

    private var months: [MonthGroup] {
        var result: [MonthGroup] = []
        for item in engine.breakdowns.reversed() {
            let title = Fmt.date(item.day, "MMMM 'de' yyyy").capitalized
            if let last = result.indices.last, result[last].title == title {
                result[last].items.append(item)
            } else {
                result.append(MonthGroup(title: title, items: [item]))
            }
        }
        return result
    }

    @ViewBuilder
    private var daysList: some View {
        if engine.breakdowns.isEmpty {
            ContentUnavailableView(
                "Nenhum resumo ainda",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Encerre um turno ou toque em + para lançar um dia manualmente.")
            )
        } else {
            let days = routeDays
            List {
                ForEach(months) { month in
                    Section(month.title) {
                        ForEach(month.items) { item in
                            row(item, hasRoute: days.contains(item.day))
                        }
                        .onDelete { offsets in
                            delete(offsets, in: month.items)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ item: DayBreakdown, hasRoute: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(Fmt.date(item.day, "EEE, dd/MM").capitalized)
                        .font(.headline)
                    Spacer()
                    Text(Fmt.money(item.net, hidden: privacy))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(item.net >= 0 ? Theme.accent : Theme.danger)
                }
                HStack(spacing: 6) {
                    Text("Bruto \(Fmt.money(item.gross, hidden: privacy))")
                    Text("·")
                    Text(Fmt.km(item.km))
                    Text("·")
                    Text(Fmt.hours(item.hours))
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
                HStack(spacing: 6) {
                    SignalDot(signal: engine.signal(perKm: item.grossPerKm))
                    Text(Fmt.rate(item.grossPerKm, unit: "km", hidden: privacy))
                    SignalDot(signal: engine.signal(perHour: item.grossPerHour))
                        .padding(.leading, 8)
                    Text(Fmt.rate(item.grossPerHour, unit: "h", hidden: privacy))
                }
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                editing = DayRef(day: item.day)
            }
            if hasRoute {
                Button {
                    replay = DayRef(day: item.day)
                } label: {
                    Image(systemName: "map.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.info)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Ver trajeto do dia")
            }
        }
        .padding(.vertical, 4)
    }

    private func delete(_ offsets: IndexSet, in items: [DayBreakdown]) {
        for index in offsets {
            if let summary = engine.summary(on: items[index].day) {
                context.delete(summary)
            }
        }
        try? context.save()
        ShiftManager.shared.refreshShared()
    }
}

struct MonthGroup: Identifiable {
    let title: String
    var items: [DayBreakdown]
    var id: String { title }
}

enum DREPeriod: String, CaseIterable, Identifiable {
    case week, month, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "Semanal"
        case .month: return "Mensal"
        case .year: return "Anual"
        }
    }

    var component: Calendar.Component {
        switch self {
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }
}

/// DRE completo do motorista (semanal / mensal / anual) + projeção de faturamento.
struct DREView: View {
    let engine: FinanceEngine

    @AppStorage("privacyMode") private var privacy = false
    @State private var period: DREPeriod = .week
    @State private var anchor = Date()

    private var interval: DateInterval {
        Calendar.br.dateInterval(of: period.component, for: anchor)
            ?? DateInterval(start: Calendar.br.startOfDay(for: anchor), duration: 7 * 86400)
    }

    private var periodLabel: String {
        let current = interval
        switch period {
        case .week:
            let lastDay = current.end.addingTimeInterval(-1)
            return "\(Fmt.date(current.start, "dd/MM")) a \(Fmt.date(lastDay, "dd/MM/yyyy"))"
        case .month:
            return Fmt.date(current.start, "MMMM 'de' yyyy").capitalized
        case .year:
            return Fmt.date(current.start, "yyyy")
        }
    }

    private func money(_ value: Double) -> String {
        Fmt.money(value, hidden: privacy)
    }

    var body: some View {
        let report = engine.dre(interval)
        return ScrollView {
            VStack(spacing: 14) {
                Picker("Período", selection: $period) {
                    ForEach(DREPeriod.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button {
                        shift(-1)
                    } label: {
                        Image(systemName: "chevron.left.circle.fill").font(.title)
                    }
                    Spacer()
                    Text(periodLabel)
                        .font(.headline)
                    Spacer()
                    Button {
                        shift(1)
                    } label: {
                        Image(systemName: "chevron.right.circle.fill").font(.title)
                    }
                }

                statement(report)
                indicators(report)
                if period == .month && interval.contains(Date()) {
                    runRateCard
                }
            }
            .padding(16)
        }
    }

    private func shift(_ value: Int) {
        anchor = Calendar.br.date(byAdding: period.component, value: value, to: anchor) ?? anchor
    }

    private func statement(_ report: DREReport) -> some View {
        Card("Demonstrativo de resultado", icon: "doc.plaintext.fill") {
            InfoRow(label: "Receita bruta", value: money(report.totals.gross), bold: true)
            InfoRow(label: "   Gorjetas", value: money(report.totals.tips))
            InfoRow(label: "   Dinâmico e promoções", value: money(report.totals.surge))
            Divider()
            InfoRow(label: "(−) Combustível", value: money(report.totals.fuel))
            InfoRow(label: "(−) Despesas de rua", value: money(report.totals.extras))
            InfoRow(label: "(−) Reserva de manutenção", value: money(report.totals.reserve))
            if report.totals.excess > 0 {
                InfoRow(label: "(−) Multa de km excedente", value: money(report.totals.excess), color: Theme.danger)
            }
            InfoRow(label: "Custos variáveis", value: money(report.variableCosts), bold: true)
            Divider()
            InfoRow(label: "(−) Fixo dos dias trabalhados", value: money(report.totals.fixed))
            InfoRow(label: "(−) Fixo de \(report.idleDays) dia(s) parado(s)", value: money(report.idleFixedCost))
            InfoRow(label: "Custos fixos (locação/veículo)", value: money(report.fixedCosts), bold: true)
            if report.coveredByDayOffBank > 0 {
                InfoRow(label: "Coberto pelo banco de folga", value: money(report.coveredByDayOffBank), color: Theme.info)
            }
            Divider()
            InfoRow(label: "Lucro líquido", value: money(report.net),
                    color: report.net >= 0 ? Theme.accent : Theme.danger, bold: true)
            InfoRow(label: "Margem líquida", value: Fmt.percent(report.margin),
                    color: report.net >= 0 ? Theme.accent : Theme.danger, bold: true)
        }
    }

    private func indicators(_ report: DREReport) -> some View {
        let totals = report.totals
        return Card("Indicadores do período", icon: "speedometer") {
            InfoRow(label: "Dias trabalhados", value: "\(totals.days)")
            InfoRow(label: "Viagens", value: "\(totals.trips)")
            InfoRow(label: "Km rodados", value: Fmt.km(totals.km))
            InfoRow(label: "Horas ativas", value: Fmt.hours(totals.hours))
            InfoRow(label: "R$/km bruto", value: Fmt.rate(totals.grossPerKm, unit: "km", hidden: privacy),
                    color: engine.signal(perKm: totals.grossPerKm).color)
            InfoRow(label: "R$/km líquido", value: Fmt.rate(totals.netPerKm, unit: "km", hidden: privacy))
            InfoRow(label: "R$/h bruto", value: Fmt.rate(totals.grossPerHour, unit: "h", hidden: privacy),
                    color: engine.signal(perHour: totals.grossPerHour).color)
            InfoRow(label: "R$/h líquido", value: Fmt.rate(totals.netPerHour, unit: "h", hidden: privacy))
        }
    }

    private var runRateCard: some View {
        let rate = engine.runRate()
        return Card("Projeção do mês (run-rate)", icon: "chart.line.uptrend.xyaxis") {
            InfoRow(label: "Lucro médio por dia trabalhado", value: money(rate.avgNetPerWorkedDay))
            InfoRow(label: "Dias de trabalho restantes", value: "\(rate.remainingWorkDays)")
            InfoRow(label: "Faturamento projetado", value: money(rate.projectedGross))
            InfoRow(label: "Lucro líquido projetado", value: money(rate.projectedNet),
                    color: rate.projectedNet >= 0 ? Theme.accent : Theme.danger, bold: true)
            Text("Mantendo o ritmo atual nos dias de trabalho do seu cronograma e descontando o custo fixo dos dias de folga.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }
}
