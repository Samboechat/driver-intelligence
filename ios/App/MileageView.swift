import SwiftUI
import DriverCore

/// Calculadora de rodagem: quanto o carro rodou de verdade, quanto custou e quanto sobrou.
/// Os campos já vêm preenchidos com o período escolhido (GPS/painel, corridas e horas) e podem ser alterados à mão.
struct MileageView: View {
    @State private var settings = SharedStore.settings
    @State private var period = 0
    @State private var km: Double?
    @State private var paidKm: Double?
    @State private var revenue: Double?
    @State private var hours: Double?
    @State private var fillKm: Double?
    @State private var fillLiters: Double?
    /// Muda quando os campos são preenchidos pelo app (para os campos de texto se redesenharem).
    @State private var fieldsVersion = 0
    @State private var costsVersion = 0

    private var result: DrivingResult? {
        guard let km, let revenue else { return nil }
        return DrivingCalculator.calculate(DrivingInput(
            kmDriven: km, paidKm: paidKm, revenue: revenue, hours: hours,
            consumptionKmPerLiter: settings.consumptionKmPerLiter, fuelPrice: settings.fuelPrice,
            otherCostPerKm: settings.otherCostPerKm ?? 0, fallbackCostPerKm: settings.matrix.costPerKm))
    }

    private var realConsumption: Double? {
        guard let fillKm, let fillLiters else { return nil }
        return DrivingCalculator.consumption(km: fillKm, liters: fillLiters)
    }

    var body: some View {
        Form {
            Section {
                Picker("Período", selection: $period) {
                    Text("Turno").tag(0)
                    Text("Semana").tag(1)
                    Text("Mês").tag(2)
                }
                .pickerStyle(.segmented)
                NumberField(title: "Km rodados", value: $km, suffix: "km").id("km-\(fieldsVersion)")
                NumberField(title: "Km em corrida", value: $paidKm, suffix: "km").id("paid-\(fieldsVersion)")
                NumberField(title: "Ganho bruto", value: $revenue, suffix: "R$").id("revenue-\(fieldsVersion)")
                NumberField(title: "Horas", value: $hours, suffix: "h").id("hours-\(fieldsVersion)")
            } header: {
                Text("O que você rodou")
            } footer: {
                Text("Km rodados vem do GPS do turno (ou do painel do carro, quando informado). Km em corrida e ganho são das corridas registradas dentro desses turnos. Você pode corrigir qualquer número.")
            }

            if let r = result {
                Section("Resultado") { resultView(r) }
            } else {
                Section {
                    Text("Informe os km rodados e o ganho para ver o resultado.").foregroundStyle(.secondary)
                }
            }

            Section {
                NumberField(title: "Consumo", value: $settings.consumptionKmPerLiter, suffix: "km/L").id("consumption-\(costsVersion)")
                NumberField(title: "Preço do combustível", value: $settings.fuelPrice, suffix: "R$/L")
                NumberField(title: "Outros custos", value: $settings.otherCostPerKm, suffix: "R$/km")
            } header: {
                Text("Custos do carro")
            } footer: {
                Text("Outros custos: manutenção, pneus, óleo, seguro, depreciação… por km. Sem consumo ou preço do combustível, a conta usa o CPK da matriz (\(Br.money(settings.matrix.costPerKm))/km).")
            }

            Section {
                NumberField(title: "Km desde o último tanque cheio", value: $fillKm, suffix: "km")
                NumberField(title: "Litros que couberam agora", value: $fillLiters, suffix: "L")
                if let c = realConsumption {
                    HStack {
                        Text("Consumo real: \(Br.decimal(c, 1)) km/L").font(.headline)
                        Spacer()
                        Button("Usar") {
                            settings.consumptionKmPerLiter = (c * 10).rounded() / 10
                            costsVersion += 1
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
            } header: {
                Text("Descobrir o consumo real")
            } footer: {
                Text("Encha o tanque, zere o parcial do painel e rode. No próximo abastecimento completo, informe os km do parcial e os litros que entraram.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Rodagem")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { fill() }
        .onChange(of: period) { _ in fill() }
        .onChange(of: settings) { new in
            SharedStore.settings = new
            Bridge.publishSettings(new)
        }
    }

    // MARK: Resultado

    @ViewBuilder private func resultView(_ r: DrivingResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SOBROU").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(Br.money(r.profit))
                        .font(.system(size: 34, weight: .bold).monospacedDigit())
                        .foregroundStyle(r.profit >= 0 ? Palette.positive : Palette.negative)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("DE CADA R$ 100").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(r.margin.map { "R$ \(Br.decimal($0 * 100, 0)) ficam" } ?? "—").font(.headline.monospacedDigit())
                }
            }
            if let dead = r.deadKm, let share = r.deadShare, let km {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 4).fill(Palette.positive)
                                .frame(width: max(4, geo.size.width * (1 - share)))
                            RoundedRectangle(cornerRadius: 4).fill(Palette.warning)
                        }
                    }
                    .frame(height: 10)
                    Text("\(Br.km(km - dead)) em corrida · \(Br.km(dead)) de km morto (\(Br.percent(share)))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            HStack {
                Stat(title: "Custo total", value: Br.money(r.totalCost))
                Stat(title: "Custo por km", value: Br.money(r.costPerKm))
                Stat(title: "Sobra por km", value: Br.money(r.profitPerKm), color: r.profitPerKm >= 0 ? .primary : Palette.negative)
            }
            if r.detailed, let liters = r.fuelLiters, let fuel = r.fuelCost, let other = r.otherCost {
                Text("Combustível: \(Br.decimal(liters, 1)) L = \(Br.money(fuel)) · outros custos: \(Br.money(other))")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Custo estimado pelo CPK de \(Br.money(settings.matrix.costPerKm))/km. Preencha consumo e preço do combustível para a conta detalhada.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                Stat(title: "Ganho/km rodado", value: Br.money(r.revenuePerKm))
                Stat(title: "Ganho/km em corrida", value: r.revenuePerPaidKm.map { Br.money($0) } ?? "—")
                Stat(title: "Sobra por hora", value: r.profitPerHour.map { Br.money($0) } ?? "—")
            }
            if let breakEven = r.breakEvenPerPaidKm {
                Text("Para pagar todos os km rodados (inclusive o km morto), cada km em corrida precisa render pelo menos \(Br.money(breakEven)). Abaixo disso a corrida dá prejuízo.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let perHour = r.profitPerHour, let h = hours, h > 0, let km {
                let weekHours = settings.weeklyGoal.hoursOnline
                Text("Nesse ritmo, uma semana de \(Br.decimal(weekHours, 0)) h rende \(Br.money(perHour * weekHours)) limpos, rodando \(Br.decimal(km / h * weekHours, 0)) km.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            // Custo real diferente do CPK usado para julgar os chamados.
            if r.detailed, abs(r.costPerKm - settings.matrix.costPerKm) >= 0.03 {
                let real = (r.costPerKm * 100).rounded() / 100
                HStack {
                    Text("Seu custo real é \(Br.money(real))/km; a matriz de aceite usa \(Br.money(settings.matrix.costPerKm)).")
                        .font(.footnote)
                    Spacer()
                    Button("Usar \(Br.decimal(real))") { settings.matrix.costPerKm = real }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Preenchimento pelo período

    private func fill() {
        let now = Date()
        // Grava os últimos km do GPS antes de ler os turnos.
        LocationService.shared.persist(force: true)
        let shifts = SharedStore.shifts
        let picked: [Shift]
        switch period {
        case 0:
            // Turno aberto; sem ele, o último encerrado.
            picked = (shifts.first(where: \.isOpen) ?? shifts.first).map { [$0] } ?? []
        case 1:
            let week = WeekMath.week(containing: now)
            picked = shifts.filter { week.contains($0.start) }
        default:
            let month = Calendar.current.dateInterval(of: .month, for: now) ?? DateInterval(start: now.addingTimeInterval(-30 * 86400), end: now)
            picked = shifts.filter { month.contains($0.start) }
        }
        let sum = MileageMath.summary(shifts: picked, trips: SharedStore.trips, now: now)
        km = sum.km > 0 ? (sum.km * 10).rounded() / 10 : nil
        paidKm = sum.paidKm > 0 ? (sum.paidKm * 10).rounded() / 10 : nil
        revenue = sum.revenue > 0 ? sum.revenue : nil
        hours = sum.hours > 0.05 ? (sum.hours * 10).rounded() / 10 : nil
        fieldsVersion += 1
    }
}

/// Soma de um conjunto de turnos: km rodados, e as corridas feitas dentro desses turnos.
enum MileageMath {
    struct Summary {
        var km = 0.0
        var paidKm = 0.0
        var revenue = 0.0
        var hours = 0.0
        var trips = 0
    }

    /// Só entram turnos com km (GPS ou painel), para o ganho e os km falarem do mesmo período.
    static func summary(shifts: [Shift], trips: [TripRecord], now: Date) -> Summary {
        var out = Summary()
        for s in shifts {
            guard let km = s.kmDriven else { continue }
            let end = s.end ?? now
            out.km += km
            out.hours += s.hours(until: now)
            for t in trips where t.completedAt >= s.start && t.completedAt <= end {
                out.paidKm += t.totalKm ?? 0
                out.revenue += t.fare ?? 0
                out.trips += 1
            }
        }
        return out
    }
}
