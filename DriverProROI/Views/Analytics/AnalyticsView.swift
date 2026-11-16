import Charts
import SwiftData
import SwiftUI

/// Inteligência de tarifas, performance por categoria e custos.
struct AnalyticsView: View {
    let engine: FinanceEngine

    @Environment(\.modelContext) private var context
    @AppStorage("privacyMode") private var privacy = false
    @State private var rangeDays = 30

    private func money(_ value: Double) -> String {
        Fmt.money(value, hidden: privacy)
    }

    var body: some View {
        let model = AnalyticsViewModel(engine: engine, rangeDays: rangeDays)
        return ScrollView {
            VStack(spacing: 14) {
                Picker("Período", selection: $rangeDays) {
                    Text("7 dias").tag(7)
                    Text("30 dias").tag(30)
                    Text("90 dias").tag(90)
                }
                .pickerStyle(.segmented)

                weeklyGoalCard(model.goal)
                cpkCard(model)
                if model.hasData {
                    categoryCard(model)
                    surgeCard(model)
                    deadheadCard(model)
                    profileCard(model)
                    timeCard(model)
                    auditCard(model)
                } else {
                    Card {
                        Text("Sem resumos nos últimos \(rangeDays) dias. Encerre um turno e lance os ganhos para liberar as análises.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Análises")
        .navigationBarTitleDisplayMode(.inline)
        .privacyToolbar()
    }

    // MARK: Meta semanal auto-ajustável

    private func weeklyGoalCard(_ goal: WeeklyGoalStatus) -> some View {
        Card("Meta semanal auto-ajustável", icon: "target") {
            ProgressView(value: goal.progress)
                .tint(goal.reached ? Theme.accent : Theme.info)
            InfoRow(label: "Lucro líquido na semana", value: money(goal.netSoFar), bold: true)
            InfoRow(label: "Meta da semana", value: money(goal.goal))
            InfoRow(label: "Falta", value: money(goal.remaining), color: goal.reached ? Theme.accent : Theme.warning)
            InfoRow(label: "Dias de trabalho restantes", value: "\(goal.remainingDays)")
            InfoRow(label: "Meta diária original", value: money(goal.baseDaily))
            InfoRow(label: "Meta de hoje (reajustada)", value: money(goal.todayTarget),
                    color: goal.adjustment <= 0 ? Theme.accent : Theme.warning, bold: true)
            Text(goalText(goal))
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }

    private func goalText(_ goal: WeeklyGoalStatus) -> String {
        if goal.reached { return "Meta batida. Se quiser, marque a folga remunerada no Cronograma." }
        if goal.adjustment < -1 { return "Você faturou acima do planejado nos dias anteriores, então a meta dos dias restantes caiu." }
        if goal.adjustment > 1 { return "Há déficit dos dias anteriores, redistribuído pelos dias de trabalho que restam." }
        return "No ritmo planejado."
    }

    // MARK: CPK dinâmico

    private func cpkCard(_ model: AnalyticsViewModel) -> some View {
        let cpk = model.cpk
        return Card("Custo por km rodado (CPK)", icon: "gauge.with.dots.needle.33percent") {
            SegmentBar(segments: [
                (cpk.fuel, Theme.warning),
                (cpk.reserve, Theme.info),
                (cpk.fixed, Theme.danger)
            ])
            LegendItem(color: Theme.warning, label: "Combustível", value: Fmt.rate(cpk.fuel, unit: "km", hidden: privacy))
            LegendItem(color: Theme.info, label: "Desgaste / reserva", value: Fmt.rate(cpk.reserve, unit: "km", hidden: privacy))
            LegendItem(color: Theme.danger, label: "Rateio do veículo", value: Fmt.rate(cpk.fixed, unit: "km", hidden: privacy))
            Divider()
            InfoRow(label: "Cada km custa", value: Fmt.rate(cpk.total, unit: "km", hidden: privacy), color: Theme.warning, bold: true)
            Text("Ponto de equilíbrio: abaixo desse valor por km total rodado (incluindo km vazio) você paga para trabalhar. Rateio calculado sobre a média de \(Fmt.number(cpk.avgDailyKm, digits: 0)) km/dia dos últimos 30 dias.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
            if let franchise = model.franchise {
                Divider()
                InfoRow(label: "Franquia do contrato",
                        value: "\(Fmt.number(franchise.used, digits: 0)) de \(Fmt.number(franchise.limit, digits: 0)) km",
                        color: franchise.used > franchise.limit ? Theme.danger : Color.white)
                if franchise.excessCost > 0 {
                    InfoRow(label: "Multa de km excedente", value: money(franchise.excessCost), color: Theme.danger)
                }
            }
        }
    }

    // MARK: Rentabilidade por categoria

    private func categoryCard(_ model: AnalyticsViewModel) -> some View {
        Card("Rentabilidade por categoria", icon: "chart.bar.xaxis") {
            if model.categories.isEmpty {
                Text("Lance os ganhos por categoria nos resumos para comparar.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            } else {
                Text("Lucro líquido por hora")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                Chart(model.categories) { item in
                    BarMark(
                        x: .value("Categoria", item.category.short),
                        y: .value("R$ por hora", item.netPerHour)
                    )
                    .foregroundStyle(item.category.color)
                    .annotation(position: .top) {
                        Text(privacy ? "••" : Fmt.brl(item.netPerHour))
                            .font(.caption2)
                            .foregroundStyle(.white)
                    }
                }
                .chartYAxis(privacy ? .hidden : .automatic)
                .frame(height: 170)

                Text("Lucro líquido por km")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                Chart(model.categories) { item in
                    BarMark(
                        x: .value("Categoria", item.category.short),
                        y: .value("R$ por km", item.netPerKm)
                    )
                    .foregroundStyle(item.category.color)
                    .annotation(position: .top) {
                        Text(privacy ? "••" : Fmt.brl(item.netPerKm))
                            .font(.caption2)
                            .foregroundStyle(.white)
                    }
                }
                .chartYAxis(privacy ? .hidden : .automatic)
                .frame(height: 150)

                ForEach(model.categories) { item in
                    InfoRow(label: "\(item.category.short) · \(item.trips) viagens",
                            value: "margem \(Fmt.percent(item.margin))",
                            color: item.category.color)
                }
                Text(model.categoryVerdict)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if model.categories.contains(where: { $0.estimated }) {
                    Text("Horas e km por categoria foram rateados pelo nº de viagens. Detalhe-os no resumo do dia para um resultado exato.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    // MARK: Termômetro de dinâmico

    private func surgeCard(_ model: AnalyticsViewModel) -> some View {
        let surge = model.totals.surgeShare
        let color = surge >= 0.30 ? Theme.danger : (surge >= 0.15 ? Theme.warning : Theme.accent)
        return Card("Dependência de dinâmico e promoções", icon: "thermometer.medium") {
            SegmentBar(segments: [
                (model.baseShare, Theme.accent),
                (surge, Theme.warning),
                (model.tipShare, Theme.info)
            ])
            LegendItem(color: Theme.accent, label: "Tarifa base", value: Fmt.percent(model.baseShare))
            LegendItem(color: Theme.warning, label: "Dinâmico / promoções / desafios", value: Fmt.percent(surge))
            LegendItem(color: Theme.info, label: "Gorjetas", value: Fmt.percent(model.tipShare))
            Text(model.surgeVerdict)
                .font(.subheadline)
                .foregroundStyle(color)
        }
    }

    // MARK: Km vazio

    private func deadheadCard(_ model: AnalyticsViewModel) -> some View {
        Card("Km vazio (deadhead)", icon: "arrow.triangle.swap") {
            if let share = model.totals.deadheadShare {
                SegmentBar(segments: [
                    (1 - share, Theme.accent),
                    (share, Theme.danger)
                ])
                LegendItem(color: Theme.accent, label: "Km em corrida", value: Fmt.km(model.totals.productiveKm))
                LegendItem(color: Theme.danger, label: "Km improdutivo",
                           value: "\(Fmt.km(model.totals.kmWithProductive - model.totals.productiveKm)) (\(Fmt.percent(share)))")
            }
            Text(model.deadheadVerdict)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: Perfil de corrida

    private func profileCard(_ model: AnalyticsViewModel) -> some View {
        Card("Perfil de corrida", icon: "figure.walk.motion") {
            InfoRow(label: "Ticket médio", value: money(model.totals.avgTicket))
            InfoRow(label: "Duração média por viagem", value: "\(Int(model.totals.avgTripMinutes.rounded())) min")
            Divider()
            ForEach(model.profile) { bucket in
                VStack(alignment: .leading, spacing: 2) {
                    Text(bucket.title)
                        .font(.subheadline.weight(.semibold))
                    if bucket.totals.days > 0 {
                        Text("\(bucket.totals.days) dia(s) · líquido \(Fmt.rate(bucket.totals.netPerHour, unit: "h", hidden: privacy)) · \(Fmt.rate(bucket.totals.netPerKm, unit: "km", hidden: privacy))")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    } else {
                        Text("Sem dias neste perfil")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            Text(model.profileVerdict)
                .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: Classificação de tempo

    private func timeCard(_ model: AnalyticsViewModel) -> some View {
        let totals = model.totals
        return Card("Classificação do tempo", icon: "clock.fill") {
            SegmentBar(segments: [
                (totals.drivingHours, Theme.accent),
                (totals.idleHours, Theme.warning),
                (totals.pausedHours, Theme.muted)
            ])
            LegendItem(color: Theme.accent, label: "Dirigindo", value: Fmt.hours(totals.drivingHours))
            LegendItem(color: Theme.warning, label: "Parado ocioso (esperando chamada)", value: Fmt.hours(totals.idleHours))
            LegendItem(color: Theme.muted, label: "Pausa manual", value: Fmt.hours(totals.pausedHours))
            if totals.hours > 0 {
                Text("\(Fmt.percent(totals.idleHours / totals.hours)) do tempo de turno ativo foi parado esperando chamadas.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    // MARK: Auditoria de odômetro

    private func auditCard(_ model: AnalyticsViewModel) -> some View {
        let audit = model.audit
        return Card("Auditoria de odômetro", icon: "ruler.fill") {
            if audit.days > 0 {
                InfoRow(label: "Dias auditados", value: "\(audit.days)")
                InfoRow(label: "Km no painel", value: Fmt.km(audit.odometerKm))
                InfoRow(label: "Km no GPS", value: Fmt.km(audit.gpsKm))
                InfoRow(label: "Fator odômetro ÷ GPS", value: Fmt.number(audit.factor, digits: 3))
            }
            Text(model.auditVerdict)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            InfoRow(label: "Calibração em uso", value: Fmt.number(engine.settings.gpsCalibration, digits: 3))
            if audit.days > 0 && abs(audit.differencePct) > 2 {
                Button {
                    applyCalibration(audit.factor)
                } label: {
                    Text("Aplicar fator de calibração")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .buttonStyle(TileButtonStyle())
            }
            if engine.settings.gpsCalibration != 1 {
                Button("Voltar calibração para 1,000") {
                    engine.settings.gpsCalibration = 1
                    try? context.save()
                    ShiftManager.shared.reloadConfig()
                }
                .font(.subheadline)
            }
        }
    }

    private func applyCalibration(_ factor: Double) {
        let combined = engine.settings.gpsCalibration * factor
        engine.settings.gpsCalibration = min(1.2, max(0.8, combined))
        try? context.save()
        ShiftManager.shared.reloadConfig()
    }
}
