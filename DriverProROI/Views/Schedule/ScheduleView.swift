import SwiftData
import SwiftUI

struct WeekdayRef: Identifiable {
    let weekday: Int
    var id: Int { weekday }
}

/// Aba Cronograma: grade semanal editável, lembretes e Planejado vs. Realizado.
struct ScheduleView: View {
    let engine: FinanceEngine

    @Environment(\.modelContext) private var context
    @AppStorage("privacyMode") private var privacy = false
    @Query(sort: \ScheduleBlock.startMinute) private var blocks: [ScheduleBlock]
    @Query private var shifts: [Shift]
    @State private var editing: ScheduleBlock?
    @State private var adding: WeekdayRef?
    @State private var confirmReset = false

    private var signature: String {
        blocks.map { "\($0.id.uuidString)|\($0.weekday)|\($0.startMinute)|\($0.isEnabled)|\($0.kindRaw)|\($0.title)" }
            .joined(separator: ";")
    }

    var body: some View {
        let stats = ScheduleStats(blocks: blocks, shifts: shifts, summaries: engine.summaries, dayOffs: engine.dayOffs)
        return ScrollView {
            VStack(spacing: 14) {
                plannedCard(stats)
                optionsCard
                ForEach(Calendar.weekdayOrder, id: \.self) { weekday in
                    dayCard(weekday, stats: stats)
                }
                Button("Restaurar cronograma padrão", role: .destructive) {
                    confirmReset = true
                }
                .padding(.vertical, 8)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Cronograma")
        .navigationBarTitleDisplayMode(.inline)
        .privacyToolbar()
        .sheet(item: $editing) { block in
            BlockEditorView(block: block, weekday: block.weekday)
        }
        .sheet(item: $adding) { reference in
            BlockEditorView(block: nil, weekday: reference.weekday)
        }
        .confirmationDialog("Restaurar o cronograma padrão?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Apagar meus blocos e restaurar", role: .destructive) {
                resetSchedule()
            }
            Button("Cancelar", role: .cancel) {}
        }
        .task {
            rescheduleReminders()
        }
        .onChange(of: signature) { _, _ in
            rescheduleReminders()
        }
    }

    // MARK: Planejado vs. Realizado

    private func plannedCard(_ stats: ScheduleStats) -> some View {
        Card("Planejado vs. Realizado (semana)", icon: "checklist") {
            ProgressView(value: stats.completion)
                .tint(stats.completion >= 0.9 ? Theme.accent : Theme.info)
            InfoRow(label: "Horas planejadas", value: Fmt.hours(stats.plannedWeek))
            InfoRow(label: "Cumpridas dentro dos blocos", value: "\(Fmt.hours(stats.doneInBlocksWeek)) (\(Fmt.percent(stats.completion)))",
                    color: Theme.accent, bold: true)
            InfoRow(label: "Trabalhadas fora dos blocos", value: Fmt.hours(stats.outsideBlocksWeek))
            InfoRow(label: "Total trabalhado na semana", value: Fmt.hours(stats.workedWeek))
            Text("O R$/hora médio de cada faixa aparece no próprio bloco (últimas 8 semanas com turno registrado pelo GPS).")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: Opções

    private var lunchBinding: Binding<Bool> {
        Binding(
            get: { blocks.contains { $0.kind == .optional && $0.isEnabled } },
            set: { enabled in
                for block in blocks where block.kind == .optional {
                    block.isEnabled = enabled
                }
                try? context.save()
            }
        )
    }

    private var remindersBinding: Binding<Bool> {
        Binding(
            get: { engine.settings.scheduleRemindersEnabled },
            set: { enabled in
                engine.settings.scheduleRemindersEnabled = enabled
                try? context.save()
                rescheduleReminders()
            }
        )
    }

    private var optionsCard: some View {
        let goal = engine.weeklyGoal()
        let sunday = Calendar.br.date(byAdding: .day, value: 6, to: goal.interval.start) ?? goal.interval.start
        let marked = engine.dayOffs.first { Calendar.br.isDate($0.day, inSameDayAs: sunday) }
        return Card("Ajustes da semana", icon: "slider.horizontal.3") {
            Toggle(isOn: lunchBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Janela Extra Almoço 11:30–13:30")
                    Text("Ative apenas em dias de chuva ou tarifa dinâmica.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            Toggle(isOn: remindersBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lembrete 30 min antes de cada bloco")
                    Text("Notificação local, sem internet.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            Divider()
            if let marked {
                InfoRow(label: "Domingo \(Fmt.date(sunday, "dd/MM"))", value: "Folga Remunerada", color: Theme.accent, bold: true)
                Text("Custo fixo de \(Fmt.money(marked.coveredCost, hidden: privacy)) coberto pelo banco de folga.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                Button("Desfazer folga", role: .destructive) {
                    context.delete(marked)
                    try? context.save()
                }
                .font(.subheadline)
            } else {
                Button {
                    context.insert(DayOff(day: sunday, coveredCost: engine.vehicle.dailyFixedCost))
                    try? context.save()
                } label: {
                    Label("Marcar domingo como Folga Remunerada", systemImage: "bed.double.fill")
                        .font(.headline)
                        .foregroundStyle(goal.reached ? Color.black : Color.white)
                }
                .buttonStyle(BigButtonStyle(color: goal.reached ? Theme.accent : Theme.cardRaised,
                                            foreground: goal.reached ? .black : .white))
                Text(goal.reached
                     ? "Meta semanal já atingida — domingo liberado."
                     : "Meta semanal ainda não atingida: faltam \(Fmt.money(goal.remaining, hidden: privacy)). Saldo do banco de folga: \(Fmt.money(engine.dayOffBalance, hidden: privacy)).")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    // MARK: Grade semanal

    private func dayCard(_ weekday: Int, stats: ScheduleStats) -> some View {
        let dayBlocks = blocks.filter { $0.weekday == weekday }
        let planned = dayBlocks.filter { $0.countsAsWork }.reduce(0) { $0 + $1.durationHours }
        return Card {
            HStack {
                Text(Calendar.weekdayName(weekday))
                    .font(.title3.weight(.bold))
                Spacer()
                Text(planned > 0 ? "\(Fmt.hours(planned)) planejadas" : "Sem blocos de trabalho")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            ForEach(dayBlocks) { block in
                blockRow(block, stat: stats.stat(for: block))
            }
            Button {
                adding = WeekdayRef(weekday: weekday)
            } label: {
                Label("Adicionar bloco", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.top, 2)
        }
    }

    private func blockRow(_ block: ScheduleBlock, stat: BandStat) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(block.isEnabled ? block.kind.color : Theme.cardBorder)
                .frame(width: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(block.timeLabel) (\(Fmt.hours(block.durationHours)))")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(block.isEnabled ? Color.white : Theme.muted)
                Text(block.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(block.isEnabled ? block.kind.color : Theme.muted)
                if !block.focus.isEmpty {
                    Text(block.focus)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                if block.countsAsWork {
                    Text(statText(stat))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.info)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                editing = block
            }
            Toggle("Ativo", isOn: Binding(
                get: { block.isEnabled },
                set: { enabled in
                    block.isEnabled = enabled
                    try? context.save()
                }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private func statText(_ stat: BandStat) -> String {
        var parts = ["Semana: \(Fmt.hours(stat.doneHours)) de \(Fmt.hours(stat.plannedHours))"]
        if stat.avgPerHour > 0 {
            parts.append("média \(Fmt.rate(stat.avgPerHour, unit: "h", hidden: privacy))")
        } else {
            parts.append("sem histórico de R$/h")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Ações

    private func rescheduleReminders() {
        let reminders = blocks.filter { $0.countsAsWork }.map {
            BlockReminder(id: $0.id.uuidString, weekday: $0.weekday, startMinute: $0.startMinute,
                          title: $0.title, timeLabel: $0.timeLabel)
        }
        if engine.settings.scheduleRemindersEnabled {
            NotificationService.shared.requestAuthorization()
        }
        NotificationService.shared.rescheduleBlockReminders(reminders, enabled: engine.settings.scheduleRemindersEnabled)
    }

    private func resetSchedule() {
        for block in blocks {
            context.delete(block)
        }
        ScheduleSeeder.seed(into: context)
        try? context.save()
    }
}

/// Edição de um bloco: horários, foco e tipo.
struct BlockEditorView: View {
    private let block: ScheduleBlock?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var weekday: Int
    @State private var start: Date
    @State private var end: Date
    @State private var title: String
    @State private var focus: String
    @State private var kind: BlockKind
    @State private var isEnabled: Bool

    init(block: ScheduleBlock?, weekday: Int) {
        self.block = block
        _weekday = State(initialValue: block?.weekday ?? weekday)
        _start = State(initialValue: BlockEditorView.date(fromMinutes: block?.startMinute ?? 6 * 60))
        _end = State(initialValue: BlockEditorView.date(fromMinutes: block?.endMinute ?? 10 * 60))
        _title = State(initialValue: block?.title ?? "")
        _focus = State(initialValue: block?.focus ?? "")
        _kind = State(initialValue: block?.kind ?? .work)
        _isEnabled = State(initialValue: block?.isEnabled ?? true)
    }

    private static func date(fromMinutes minutes: Int) -> Date {
        Calendar.br.startOfDay(for: Date()).addingTimeInterval(Double(minutes) * 60)
    }

    private static func minutes(from date: Date) -> Int {
        let parts = Calendar.br.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private var durationText: String {
        let startMinute = BlockEditorView.minutes(from: start)
        let endMinute = BlockEditorView.minutes(from: end)
        let duration = endMinute > startMinute ? endMinute - startMinute : endMinute + 1440 - startMinute
        let suffix = endMinute > startMinute ? "" : " (termina no dia seguinte)"
        return Fmt.hours(Double(duration) / 60) + suffix
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Quando") {
                    Picker("Dia da semana", selection: $weekday) {
                        ForEach(Calendar.weekdayOrder, id: \.self) { value in
                            Text(Calendar.weekdayName(value)).tag(value)
                        }
                    }
                    DatePicker("Início", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Fim", selection: $end, displayedComponents: .hourAndMinute)
                    LabeledContent("Duração", value: durationText)
                }
                Section("Estratégia") {
                    TextField("Nome do bloco", text: $title)
                    TextField("Foco da janela (onde e quem buscar)", text: $focus, axis: .vertical)
                        .lineLimit(2...5)
                    Picker("Tipo", selection: $kind) {
                        ForEach(BlockKind.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    Toggle("Bloco ativo", isOn: $isEnabled)
                }
                if block != nil {
                    Section {
                        Button("Remover bloco", role: .destructive) {
                            if let block {
                                context.delete(block)
                                try? context.save()
                            }
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(block == nil ? "Novo bloco" : "Editar bloco")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let startMinute = BlockEditorView.minutes(from: start)
        let endMinute = BlockEditorView.minutes(from: end)
        if let block {
            block.weekday = weekday
            block.startMinute = startMinute
            block.endMinute = endMinute
            block.title = title
            block.focus = focus
            block.kind = kind
            block.isEnabled = isEnabled
        } else {
            context.insert(ScheduleBlock(weekday: weekday, startMinute: startMinute, endMinute: endMinute,
                                         title: title, focus: focus, kind: kind, isEnabled: isEnabled))
        }
        try? context.save()
        dismiss()
    }
}
