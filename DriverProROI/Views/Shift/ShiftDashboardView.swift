import SwiftData
import SwiftUI

/// Tela principal: controle do turno em tempo real.
struct ShiftDashboardView: View {
    let engine: FinanceEngine

    @AppStorage("privacyMode") private var privacy = false
    @Bindable private var manager = ShiftManager.shared
    @State private var entryCategory: RideCategory?
    @State private var expenseCategory: ExpenseCategory?
    @State private var confirmEnd = false

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    private let expenseColumns = [
        GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                content(now: timeline.date)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Turno")
        .navigationBarTitleDisplayMode(.inline)
        .privacyToolbar()
        .sheet(item: $entryCategory) { category in
            LiveEntrySheet(category: category)
        }
        .sheet(item: $expenseCategory) { category in
            QuickExpenseSheet(category: category)
        }
        .sheet(item: $manager.summaryDay) { reference in
            NavigationStack {
                SummaryEditorView(day: reference.day, engine: engine, allowsDayChange: false)
            }
        }
        .confirmationDialog("Encerrar o turno?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Encerrar e abrir o resumo do dia", role: .destructive) {
                manager.end()
            }
            Button("Continuar rodando", role: .cancel) {}
        } message: {
            Text("O GPS será desligado e os km e horas serão consolidados no Resumo Geral Diário.")
        }
    }

    // MARK: Conteúdo

    private func content(now: Date) -> some View {
        let day = manager.shift?.day ?? Calendar.br.startOfDay(for: now)
        let live = engine.liveDay(
            day: day,
            shiftGross: manager.entriesTotal,
            shiftKm: manager.hasShift ? manager.liveKm : 0,
            shiftSeconds: manager.activeSeconds(at: now)
        )
        let goal = engine.weeklyGoal(now: now)
        return VStack(spacing: 14) {
            statusCard(now: now)
            controls
            permissionBanner
            fatigueBanner(hours: live.hours)
            if manager.hasShift {
                earningsCard
            }
            breakEvenCard(live)
            signalsCard(live, goal: goal)
            expensesCard(day: day)
            if manager.hasShift {
                timeCard(now: now)
            } else {
                todayCard(day: day)
            }
        }
    }

    // MARK: Status e controles

    private var statusTitle: String {
        if manager.isRunning { return "RODANDO" }
        if manager.isPaused { return "PAUSADO" }
        return "TURNO PARADO"
    }

    private var statusColor: Color {
        if manager.isRunning { return Theme.accent }
        if manager.isPaused { return Theme.warning }
        return Theme.muted
    }

    private func statusCard(now: Date) -> some View {
        Card {
            HStack {
                Circle().fill(statusColor).frame(width: 12, height: 12)
                Text(statusTitle)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(statusColor)
                Spacer()
                if manager.hasShift {
                    Text(manager.gpsMode.title)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            Text(Fmt.clock(manager.activeSeconds(at: now)))
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
            Text("tempo de trabalho líquido")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .center)
            LazyVGrid(columns: expenseColumns, spacing: 10) {
                MetricTile(title: "Km no GPS", value: Fmt.number(manager.liveKm, digits: 1))
                MetricTile(title: "Em pausa", value: Fmt.hoursMinutes(manager.pausedSeconds(at: now)))
                MetricTile(title: "Velocidade", value: "\(Int(manager.speedKmh.rounded())) km/h")
            }
            if manager.isRunning {
                Text(accuracyText)
                    .font(.caption)
                    .foregroundStyle(accuracyColor)
            }
        }
    }

    private var accuracyText: String {
        if manager.gpsMode == .parked {
            return "Veículo parado há mais de 3 min — GPS em modo econômico até voltar a andar."
        }
        if manager.accuracy < 0 { return "Aguardando sinal de GPS…" }
        let meters = Int(manager.accuracy.rounded())
        if manager.accuracy <= 20 { return "Sinal de GPS bom (±\(meters) m)" }
        return "Sinal de GPS fraco (±\(meters) m) — leituras acima de 20 m são ignoradas"
    }

    private var accuracyColor: Color {
        if manager.gpsMode == .parked { return Theme.muted }
        return manager.accuracy >= 0 && manager.accuracy <= 20 ? Theme.accent : Theme.warning
    }

    @ViewBuilder
    private var controls: some View {
        if !manager.hasShift {
            Button {
                manager.start()
            } label: {
                Label("Iniciar Turno", systemImage: "play.fill")
            }
            .buttonStyle(BigButtonStyle(color: Theme.accent))
        } else {
            HStack(spacing: 12) {
                if manager.isRunning {
                    Button {
                        manager.pause()
                    } label: {
                        Label("Pausar", systemImage: "pause.fill")
                    }
                    .buttonStyle(BigButtonStyle(color: Theme.warning))
                } else {
                    Button {
                        manager.resume()
                    } label: {
                        Label("Retomar", systemImage: "play.fill")
                    }
                    .buttonStyle(BigButtonStyle(color: Theme.accent))
                }
                Button {
                    confirmEnd = true
                } label: {
                    Label("Encerrar", systemImage: "stop.fill")
                }
                .buttonStyle(BigButtonStyle(color: Theme.danger, foreground: .white))
            }
        }
    }

    @ViewBuilder
    private var permissionBanner: some View {
        if manager.locationDenied {
            banner(
                icon: "location.slash.fill",
                color: Theme.danger,
                text: "Localização negada. Sem ela os km não são contados. Libere em Ajustes > DriverPro ROI > Localização."
            )
        } else if manager.needsAlwaysAuthorization && manager.hasShift {
            banner(
                icon: "location.fill",
                color: Theme.warning,
                text: "Para contar km com a tela bloqueada ou com a Uber/99 aberta, mude a Localização para \"Sempre\" nos Ajustes do iPhone."
            )
        }
    }

    @ViewBuilder
    private func fatigueBanner(hours: Double) -> some View {
        if hours >= 12 {
            banner(icon: "exclamationmark.octagon.fill", color: Theme.danger,
                   text: "12h de direção hoje. Pausa obrigatória: encerre o turno e descanse.")
        } else if hours >= 10 {
            banner(icon: "exclamationmark.triangle.fill", color: Theme.danger,
                   text: "Mais de 10h ao volante hoje. O risco de acidente está alto — faça uma pausa longa.")
        } else if hours >= 8 {
            banner(icon: "bed.double.fill", color: Theme.warning,
                   text: "Você passou de 8h de direção hoje. Recomendado parar pelo menos 15 minutos.")
        }
    }

    private func banner(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color.opacity(0.6), lineWidth: 1))
    }

    // MARK: Ganhos do turno

    private var earningsCard: some View {
        Card("Lançar corrida", icon: "plus.circle.fill") {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(RideCategory.allCases) { category in
                    Button {
                        entryCategory = category
                    } label: {
                        Text(category.short)
                            .font(.headline)
                            .foregroundStyle(category.color)
                    }
                    .buttonStyle(TileButtonStyle())
                }
            }
            HStack {
                Text("\(manager.entries.count) corrida(s) no turno")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(Fmt.money(manager.entriesTotal, hidden: privacy))
                    .font(.headline)
                    .monospacedDigit()
                if !manager.entries.isEmpty {
                    Button {
                        manager.removeLastEntry()
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.muted)
                    }
                    .accessibilityLabel("Desfazer última corrida")
                }
            }
        }
    }

    // MARK: Break-even e semáforo

    private func breakEvenCard(_ live: LiveDay) -> some View {
        Card("Pago o dia", icon: "flag.checkered") {
            ProgressView(value: live.breakEvenProgress)
                .tint(live.isPaid ? Theme.accent : Theme.info)
                .scaleEffect(x: 1, y: 2.4, anchor: .center)
                .padding(.vertical, 6)
            if live.isPaid {
                Text("Dia pago! Daqui em diante é lucro livre.")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                InfoRow(label: "Acima do custo do dia", value: Fmt.money(live.gross - live.breakEvenTarget, hidden: privacy), color: Theme.accent)
            } else {
                InfoRow(label: "Falta para pagar o dia", value: Fmt.money(live.missing, hidden: privacy), color: Theme.warning, bold: true)
            }
            InfoRow(label: "Custo fixo de hoje", value: Fmt.money(live.fixed, hidden: privacy))
            InfoRow(label: "Combustível gasto (estimado)", value: Fmt.money(live.fuel, hidden: privacy))
            if live.extras > 0 {
                InfoRow(label: "Despesas de rua", value: Fmt.money(live.extras, hidden: privacy))
            }
        }
    }

    private func signalsCard(_ live: LiveDay, goal: WeeklyGoalStatus) -> some View {
        let kmSignal = engine.signal(perKm: live.grossPerKm)
        let hourSignal = engine.signal(perHour: live.grossPerHour)
        let target = goal.todayTarget
        let progress = target > 0 ? min(1, max(0, live.net / target)) : 0
        return Card("Semáforo de meta", icon: "trafficlight") {
            LazyVGrid(columns: columns, spacing: 10) {
                MetricTile(title: "R$/km bruto", value: Fmt.money(live.grossPerKm, hidden: privacy),
                           signal: kmSignal, caption: "piso \(Fmt.brl(engine.settings.minPerKm))")
                MetricTile(title: "R$/hora bruto", value: Fmt.money(live.grossPerHour, hidden: privacy),
                           signal: hourSignal, caption: "piso \(Fmt.brl(engine.settings.minPerHour))")
                MetricTile(title: "Faturado hoje", value: Fmt.money(live.gross, hidden: privacy))
                MetricTile(title: "Lucro líquido hoje", value: Fmt.money(live.net, hidden: privacy),
                           signal: live.net >= 0 ? .green : .red)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Meta de lucro de hoje")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text(Fmt.money(target, hidden: privacy))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                ProgressView(value: progress)
                    .tint(progress >= 1 ? Theme.accent : Theme.info)
                Text(goalCaption(goal))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func goalCaption(_ goal: WeeklyGoalStatus) -> String {
        if goal.reached { return "Meta semanal já atingida. O que entrar agora é excedente." }
        if privacy { return "Meta reajustada automaticamente pelo desempenho da semana." }
        if goal.adjustment < -1 {
            return "Meta de hoje reduzida em \(Fmt.brl(-goal.adjustment)) porque você está adiantado na semana."
        }
        if goal.adjustment > 1 {
            return "Meta de hoje aumentada em \(Fmt.brl(goal.adjustment)) para compensar o déficit da semana."
        }
        return "Meta semanal dividida pelos dias de trabalho restantes."
    }

    // MARK: Despesas de rua

    private func expensesCard(day: Date) -> some View {
        Card("Despesa de rua", icon: "creditcard.fill") {
            LazyVGrid(columns: expenseColumns, spacing: 10) {
                ForEach(ExpenseCategory.allCases) { category in
                    Button {
                        expenseCategory = category
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: category.icon)
                                .font(.title3)
                                .foregroundStyle(Theme.warning)
                            Text(category.title)
                                .font(.caption)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(TileButtonStyle())
                }
            }
            InfoRow(label: "Gasto na rua hoje", value: Fmt.money(engine.extras(on: day), hidden: privacy))
        }
    }

    // MARK: Classificação de tempo

    private func timeCard(now: Date) -> some View {
        let driving = manager.drivingSeconds
        let idle = manager.idleSeconds(at: now)
        let paused = manager.pausedSeconds(at: now)
        return Card("Classificação do tempo", icon: "clock.fill") {
            SegmentBar(segments: [
                (driving, Theme.accent),
                (idle, Theme.warning),
                (paused, Theme.muted)
            ])
            LegendItem(color: Theme.accent, label: "Dirigindo", value: Fmt.hoursMinutes(driving))
            LegendItem(color: Theme.warning, label: "Parado ocioso (turno ativo)", value: Fmt.hoursMinutes(idle))
            LegendItem(color: Theme.muted, label: "Pausa manual", value: Fmt.hoursMinutes(paused))
        }
    }

    // MARK: Sem turno aberto

    private func todayCard(day: Date) -> some View {
        Card("Resumo de hoje", icon: "doc.text.fill") {
            if let today = engine.breakdown(on: day) {
                InfoRow(label: "Faturado", value: Fmt.money(today.gross, hidden: privacy))
                InfoRow(label: "Lucro líquido real", value: Fmt.money(today.net, hidden: privacy),
                        color: today.net >= 0 ? Theme.accent : Theme.danger, bold: true)
                InfoRow(label: "Rodado", value: "\(Fmt.km(today.km)) em \(Fmt.hours(today.hours))")
            } else {
                Text("Nenhum resumo lançado hoje. Inicie o turno para contar km e horas automaticamente.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            Button {
                manager.summaryDay = DayRef(day: day)
            } label: {
                Label(engine.breakdown(on: day) == nil ? "Lançar resumo de hoje" : "Editar resumo de hoje",
                      systemImage: "square.and.pencil")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .buttonStyle(TileButtonStyle())
        }
    }
}
