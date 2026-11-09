import SwiftUI
import DriverCore

// MARK: - Simular (análise manual)

struct SimulatorView: View {
    @State private var fare: Double? = nil
    @State private var pickupKm: Double? = nil
    @State private var pickupMin: Double? = nil
    @State private var tripKm: Double? = nil
    @State private var tripMin: Double? = nil

    private var analysis: OfferAnalysis? {
        guard fare != nil || tripKm != nil else { return nil }
        return OfferAnalyzer().analyze(
            offer: OfferData(fare: fare, pickupDistanceKm: pickupKm, tripDistanceKm: tripKm, pickupTimeMin: pickupMin, tripTimeMin: tripMin),
            context: SharedStore.settings.context
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Oferta") {
                    NumberField(title: "Valor", value: $fare, suffix: "R$")
                    NumberField(title: "Até o passageiro", value: $pickupKm, suffix: "km")
                    NumberField(title: "Tempo de busca", value: $pickupMin, suffix: "min")
                    NumberField(title: "Viagem", value: $tripKm, suffix: "km")
                    NumberField(title: "Tempo de viagem", value: $tripMin, suffix: "min")
                }
                if let a = analysis {
                    Section("Resultado") { AnalysisSummary(a: a) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Simular oferta")
        }
    }
}

struct AnalysisSummary: View {
    var a: OfferAnalysis

    var body: some View {
        let f = a.financial
        let d = a.decision
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Br.money(f.grossRevenue)).font(.system(size: 30, weight: .bold).monospacedDigit())
                Spacer()
                Pill(text: d.classification.shortLabel, color: d.classification.color)
            }
            Text(d.headline).font(.subheadline).foregroundStyle(d.classification == .gray ? .secondary : d.classification.color)
            HStack {
                Stat(title: "R$/km", value: Br.decimal(f.revenuePerKm))
                Stat(title: a.realistic != nil ? "R$/h real" : "R$/h", value: Br.decimal(a.basis.revenuePerHour, 0))
                Stat(title: "Lucro", value: Br.money(f.operatingProfit), color: (f.operatingProfit ?? 0) > 0 ? Palette.positive : Palette.negative)
            }
            if let real = a.realistic?.totalTimeMin, let shown = f.totalTimeMin {
                Text("App diz \(Br.minutes(shown)) · na prática ~\(Br.minutes(real))").font(.footnote).foregroundStyle(.secondary)
            }
            if let t = a.fareTarget, let gap = t.gap {
                Text(gap >= 0 ? "\(Br.money(gap)) acima do mínimo das suas metas" : "Valor justo: \(Br.money(t.minimumFare)) · faltam \(Br.money(-gap))")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(gap >= 0 ? Palette.positive : Palette.warning)
            }
            if f.isCostEstimatePartial {
                Text("Estimativa parcial: configure os custos do carro em Ajustes.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Histórico

struct HistoryView: View {
    @State private var history = SharedStore.history

    var body: some View {
        NavigationStack {
            List {
                if history.isEmpty {
                    Text("As ofertas lidas durante a transmissão aparecem aqui.").foregroundStyle(.secondary)
                }
                ForEach(groupedDays, id: \.0) { day, items in
                    Section(day) {
                        ForEach(items) { OfferRow(record: $0) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Histórico")
            .toolbar {
                if !history.isEmpty {
                    Button("Limpar", role: .destructive) {
                        SharedStore.history = []
                        history = []
                    }
                }
            }
            .refreshable { history = SharedStore.history }
            .onAppear { history = SharedStore.history }
        }
    }

    private var groupedDays: [(String, [OfferRecord])] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "EEEE, d 'de' MMMM"
        var out: [(String, [OfferRecord])] = []
        for r in history {
            let key = f.string(from: r.date).capitalized
            if let i = out.firstIndex(where: { $0.0 == key }) { out[i].1.append(r) } else { out.append((key, [r])) }
        }
        return out
    }
}

// MARK: - Ajustes

struct SettingsView: View {
    @State private var s = SharedStore.settings

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NumberField(title: "Consumo", value: $s.consumptionKmPerLiter, suffix: "km/L")
                    NumberField(title: "Preço do combustível", value: $s.fuelPrice, suffix: "R$/L")
                    NumberField(title: "Outros custos", value: $s.otherCostPerKm, suffix: "R$/km")
                } header: {
                    Text("Veículo")
                } footer: {
                    Text("Outros custos: manutenção, pneus, óleo, depreciação… somados por km. Sem eles, o lucro é marcado como estimativa parcial.")
                }
                Section {
                    NumberField(title: "Custo total por km", value: $s.operationalCostOverride, suffix: "R$/km")
                    Toggle("Esse valor já inclui combustível", isOn: $s.overrideIncludesFuel)
                } header: {
                    Text("Avançado (opcional)")
                } footer: {
                    Text("Se você já sabe seu custo total por km, informe aqui. Ele substitui \"Outros custos\" e evita descontar o combustível duas vezes.")
                }
                Section("Metas por corrida") {
                    NumberField(title: "Valor mínimo por km", value: $s.minRevenuePerKm.optional, suffix: "R$")
                    NumberField(title: "Valor mínimo por hora", value: $s.minRevenuePerHour.optional, suffix: "R$")
                    NumberField(title: "Lucro mínimo por km", value: $s.minProfitPerKm.optional, suffix: "R$")
                    NumberField(title: "Lucro mínimo por hora", value: $s.minProfitPerHour.optional, suffix: "R$")
                    NumberField(title: "Lucro mínimo por corrida", value: $s.minProfitPerTrip, suffix: "R$")
                    NumberField(title: "Busca máxima", value: $s.maxPickupMinutes.optional, suffix: "min")
                }
                Section {
                    Toggle("Usar tempo realista", isOn: $s.useRealisticTime)
                    Stepper("Busca: +\(Int(((s.pickupTimeFactor - 1) * 100).rounded()))%", value: $s.pickupTimeFactor, in: 1...2.5, step: 0.05)
                    Stepper("Viagem: +\(Int(((s.tripTimeFactor - 1) * 100).rounded()))%", value: $s.tripTimeFactor, in: 1...2, step: 0.05)
                } header: {
                    Text("Tempo realista")
                } footer: {
                    Text("Os apps costumam mostrar menos minutos do que a corrida leva. A análise usa o tempo corrigido por esses percentuais.")
                }
                Section {
                    Toggle("Som nas notificações", isOn: $s.notifySound)
                    Toggle("Avisar leituras incompletas", isOn: $s.notifyIncomplete)
                    Toggle("Leitura rápida (economiza bateria)", isOn: $s.fastRecognition)
                } header: {
                    Text("Notificações e leitura")
                }
                Section {
                    Text("Processamento 100% no iPhone. Nenhuma imagem da tela é salva ou enviada.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Ajustes")
            .onChange(of: s) { new in SharedStore.settings = new }
        }
    }
}
