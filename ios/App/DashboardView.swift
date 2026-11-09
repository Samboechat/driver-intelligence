import SwiftUI
import DriverCore

/// Painel: meta da semana, turno com hodômetro e as decisões do dia.
struct DashboardView: View {
    @State private var settings = SharedStore.settings
    @State private var trips = SharedStore.trips
    @State private var history = SharedStore.history
    @State private var shifts = SharedStore.shifts
    @State private var now = Date()
    @State private var odometerStart = ""
    @State private var odometerEnd = ""
    @State private var confirmDelete: Shift?
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var week: DateInterval { WeekMath.week(containing: now) }
    private var weekTrips: [TripRecord] { trips.filter { week.contains($0.completedAt) } }
    private var weekRevenue: Double { weekTrips.compactMap(\.fare).reduce(0, +) }
    private var weekHours: Double { WeekMath.hoursOnline(shifts, in: week, now: now) }
    private var openShift: Shift? { shifts.first(where: \.isOpen) }
    private var today: [OfferRecord] { history.filter { Calendar.current.isDateInToday($0.date) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    weekCard
                    shiftCard
                    decisionsCard
                    if !shifts.filter({ !$0.isOpen }).isEmpty { shiftsCard }
                }
                .padding(16)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Painel")
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear(perform: reload)
        .onReceive(timer) { _ in reload() }
        .confirmationDialog("Apagar este turno?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Apagar turno", role: .destructive) {
                if let s = confirmDelete {
                    shifts.removeAll { $0.id == s.id }
                    SharedStore.shifts = shifts
                }
                confirmDelete = nil
            }
        }
    }

    private func reload() {
        settings = SharedStore.settings
        trips = SharedStore.trips
        history = SharedStore.history
        shifts = SharedStore.shifts
        now = Date()
    }

    // MARK: Meta da semana

    private var weekCard: some View {
        let goal = settings.weeklyGoal
        let missing = max(0, goal.revenue - weekRevenue)
        let hoursLeft = max(0, goal.hoursOnline - weekHours)
        let df = DateFormatter()
        df.locale = Locale(identifier: "pt_BR")
        df.dateFormat = "d/MM"
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: week.end) ?? week.end
        return Card {
            HStack {
                Text("Meta da semana").font(.headline)
                Spacer()
                Text("\(df.string(from: week.start)) a \(df.string(from: lastDay))").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                Ring(progress: WeekMath.progress(weekRevenue, of: goal.revenue), color: Palette.positive,
                     title: Br.percent(goal.revenue > 0 ? weekRevenue / goal.revenue : 0), subtitle: "ganho")
                Ring(progress: WeekMath.progress(weekHours, of: goal.hoursOnline), color: Palette.brand,
                     title: Br.percent(goal.hoursOnline > 0 ? weekHours / goal.hoursOnline : 0), subtitle: "horas")
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Br.money(weekRevenue)).font(.title3.bold().monospacedDigit())
                        Text("de \(Br.money(goal.revenue))").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(Br.decimal(weekHours, 1)) h").font(.title3.bold().monospacedDigit())
                        Text("de \(Br.decimal(goal.hoursOnline, 0)) h online").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if missing <= 0 {
                Text("Meta da semana batida! 🎉").font(.footnote.weight(.semibold)).foregroundStyle(Palette.positive)
            } else if hoursLeft > 0.25 {
                Text("Faltam \(Br.money(missing)). Para fechar nas \(Br.decimal(hoursLeft, 1)) h que restam da meta de horas: \(Br.perHour(missing / hoursLeft)).")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Faltam \(Br.money(missing)) e a meta de horas já foi cumprida.").font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                Stat(title: "Corridas", value: "\(weekTrips.count)")
                Stat(title: "R$/h online", value: weekHours > 0.1 ? Br.decimal(weekRevenue / weekHours, 0) : "—")
                Stat(title: "Lucro", value: Br.money(weekTrips.compactMap(\.profit).reduce(0, +)))
            }
            if shifts.isEmpty {
                Text("As horas online contam os turnos abertos abaixo. O ganho soma as corridas registradas.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Turno e hodômetro

    private var shiftCard: some View {
        Card {
            HStack {
                Image(systemName: "gauge.with.dots.needle.67percent").foregroundStyle(Palette.brand)
                Text("Turno e hodômetro").font(.headline)
                Spacer()
                if let s = openShift { Text(s.start, style: .timer).font(.headline.monospacedDigit()).foregroundStyle(Palette.positive) }
            }
            if let s = openShift {
                let earned = revenue(in: s)
                HStack {
                    Stat(title: "Início", value: timeText(s.start))
                    Stat(title: "Km inicial", value: s.odometerStart.map { Br.decimal($0, 0) } ?? "—")
                    Stat(title: "Ganho", value: Br.money(earned))
                }
                OdometerField(title: "Km final do painel", text: $odometerEnd)
                if let end = Self.parse(odometerEnd), let start = s.odometerStart, end < start {
                    Text("O km final é menor que o inicial (\(Br.decimal(start, 0))).").font(.caption).foregroundStyle(Palette.warning)
                }
                Button {
                    closeShift(s)
                } label: {
                    Text("Encerrar turno").font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.negative)
            } else {
                Text("Informe o km do painel ao começar e ao terminar. O app calcula os km rodados, o km morto e o ganho por km de verdade.")
                    .font(.footnote).foregroundStyle(.secondary)
                OdometerField(title: "Km inicial do painel", text: $odometerStart)
                Button {
                    let shift = Shift(start: Date(), odometerStart: Self.parse(odometerStart))
                    shifts.insert(shift, at: 0)
                    SharedStore.shifts = shifts
                    odometerStart = ""
                    odometerEnd = ""
                } label: {
                    Text("Iniciar turno").font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func closeShift(_ s: Shift) {
        guard let i = shifts.firstIndex(where: { $0.id == s.id }) else { return }
        shifts[i].end = Date()
        if let end = Self.parse(odometerEnd), end >= (s.odometerStart ?? 0) { shifts[i].odometerEnd = end }
        SharedStore.shifts = shifts
        odometerEnd = ""
    }

    private func tripsIn(_ s: Shift) -> [TripRecord] {
        let end = s.end ?? now
        return trips.filter { $0.completedAt >= s.start && $0.completedAt <= end }
    }

    private func revenue(in s: Shift) -> Double { tripsIn(s).compactMap(\.fare).reduce(0, +) }

    private var shiftsCard: some View {
        Card {
            Text("Últimos turnos").font(.headline)
            ForEach(shifts.filter { !$0.isOpen }.prefix(7)) { s in
                let t = tripsIn(s)
                let earned = t.compactMap(\.fare).reduce(0, +)
                let paidKm = t.compactMap(\.totalKm).reduce(0, +)
                let hours = s.hours(until: now)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(dayText(s.start)).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(Br.money(earned)).font(.subheadline.monospacedDigit())
                    }
                    HStack {
                        Stat(title: "Horas", value: Br.decimal(hours, 1))
                        Stat(title: "Km rodados", value: s.kmDriven.map { Br.decimal($0, 0) } ?? "—")
                        Stat(title: "R$/km real", value: s.kmDriven.flatMap { $0 > 0 ? Br.decimal(earned / $0) : nil } ?? "—")
                        Stat(title: "Km morto", value: s.kmDriven.flatMap { $0 > 0 ? Br.percent(max(0, $0 - paidKm) / $0) : nil } ?? "—")
                    }
                    if let km = s.kmDriven, km > 0 {
                        Text(costLine(km: km, earned: earned, hours: hours)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .contextMenu { Button("Apagar turno", role: .destructive) { confirmDelete = s } }
                Divider().opacity(0.3)
            }
            Text("Segure um turno para apagar.").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func costLine(km: Double, earned: Double, hours: Double) -> String {
        let cpk = settings.matrix.costPerKm
        let cost = km * cpk
        var line = "Custo do turno (CPK " + Br.money(cpk) + "): " + Br.money(cost) + " · sobra " + Br.money(earned - cost)
        if hours > 0.1 { line += " · " + Br.perHour(earned / hours) }
        return line
    }

    // MARK: Decisões do dia

    private var decisionsCard: some View {
        let green = today.filter { $0.cls == .green }
        let red = today.filter { $0.cls == .red }
        let greenAccepted = green.filter { $0.result == .accepted }.count
        let redAccepted = red.filter { $0.result == .accepted }.count
        return Card {
            HStack {
                Text("Decisões de hoje").font(.headline)
                Spacer()
                Text("\(today.count) chamado(s)").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack {
                Stat(title: "Aceitar", value: "\(green.count)", color: Palette.positive)
                Stat(title: "Avaliar", value: "\(today.filter { $0.cls == .yellow }.count)", color: Palette.warning)
                Stat(title: "Recusar", value: "\(red.count)", color: Palette.negative)
            }
            if !today.isEmpty {
                Text("Você aceitou \(greenAccepted) de \(green.count) recomendadas e \(redAccepted) de \(red.count) que a matriz mandou recusar.")
                    .font(.footnote).foregroundStyle(redAccepted > 0 ? Palette.warning : Color.secondary)
            } else {
                Text("Os chamados lidos hoje aparecem aqui com o veredito da matriz e o que você fez com cada um.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(today.prefix(30)) { r in
                DecisionRow(record: r)
                Divider().opacity(0.3)
            }
        }
    }

    // MARK: Auxiliares

    private func timeText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func dayText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "EEE d/MM · HH:mm"
        return f.string(from: d).capitalized
    }

    /// Hodômetro: aceita "45.210", "45210" ou "45210,5".
    static func parse(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let v = Double(cleaned), v.isFinite, v >= 0 else { return nil }
        return v
    }
}

/// Progresso circular (0...1).
struct Ring: View {
    var progress: Double
    var color: Color
    var title: String
    var subtitle: String

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(title).font(.subheadline.bold().monospacedDigit())
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 78, height: 78)
        .animation(.easeOut(duration: 0.4), value: progress)
    }
}

struct OdometerField: View {
    var title: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(maxWidth: 120)
            Text("km").foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

/// Linha do histórico de decisões: veredito, números, zona e o que o motorista fez.
struct DecisionRow: View {
    var record: OfferRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Pill(text: record.verdict ?? record.cls.shortLabel, color: record.cls.color)
                Text(Br.money(record.fare)).font(.subheadline.bold().monospacedDigit())
                Spacer()
                Text(record.result?.label ?? "—").font(.caption.weight(.semibold))
                    .foregroundStyle(record.result == .accepted ? Palette.positive : Color.secondary)
                Text(record.date, style: .time).font(.caption).foregroundStyle(.secondary)
            }
            Text([
                record.category,
                record.revenuePerKm.map { "\(Br.decimal($0))/km" },
                record.revenuePerHour.map { "\(Br.decimal($0, 0))/h" },
                record.pickupKm.map { "busca \(Br.km($0))" },
                record.rating.map { "★ \(Br.decimal($0))" },
                record.zoneKind?.label,
            ].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            if record.cls != .green { Text(record.headline).font(.caption).foregroundStyle(record.cls.color) }
            if let alert = record.alert { Text("⚠️ \(alert)").font(.caption.weight(.semibold)).foregroundStyle(Palette.warning) }
        }
        .padding(.vertical, 2)
    }
}
