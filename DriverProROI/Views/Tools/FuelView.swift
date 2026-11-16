import SwiftData
import SwiftUI

/// Calculadora Inteligente Flex + registro de abastecimentos.
struct FuelView: View {
    let engine: FinanceEngine

    @Environment(\.modelContext) private var context
    @AppStorage("privacyMode") private var privacy = false
    @Query(sort: \FuelEntry.date, order: .reverse) private var entries: [FuelEntry]
    @State private var adding = false

    var body: some View {
        let fuel = engine.fuel
        return List {
            Section("Qual combustível compensa") {
                recommendation(fuel)
            }
            Section("Consumo e custo por km") {
                ForEach(FuelType.allCases) { type in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(type.title)
                                .font(.headline)
                            Spacer()
                            Text(Fmt.rate(fuel.costPerKm(type), unit: "km", hidden: privacy))
                                .font(.headline)
                                .monospacedDigit()
                                .foregroundStyle(fuel.recommended == type ? Theme.accent : Color.white)
                        }
                        Text("\(Fmt.number(fuel.efficiency(type), digits: 1)) km/L \(fuel.isMeasured(type) ? "(medido nos seus abastecimentos)" : "(estimativa do perfil do veículo)") · \(Fmt.brl(fuel.pricePerLiter(type)))/L")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 2)
                }
            }
            Section {
                if entries.isEmpty {
                    Text("Registre os abastecimentos (de preferência completando o tanque) para o app medir o consumo real do seu carro.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(Fmt.date(entry.date, "dd/MM/yyyy")) · \(entry.fuel.title)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(Fmt.money(entry.totalPaid, hidden: privacy))
                                .monospacedDigit()
                        }
                        Text("\(Fmt.number(entry.liters, digits: 2)) L a \(Fmt.brl(entry.pricePerLiter))/L · odômetro \(Fmt.number(entry.odometer, digits: 0)) km\(entry.fullTank ? " · tanque cheio" : "")")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        context.delete(entries[index])
                    }
                    try? context.save()
                }
            } header: {
                Text("Abastecimentos")
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Calculadora Flex")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    adding = true
                } label: {
                    Label("Novo abastecimento", systemImage: "plus.circle.fill")
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $adding) {
            FuelEntrySheet(lastOdometer: entries.map { $0.odometer }.max() ?? 0)
        }
    }

    @ViewBuilder
    private func recommendation(_ fuel: FuelAnalysis) -> some View {
        let best = fuel.recommended
        VStack(alignment: .leading, spacing: 8) {
            Text("Abasteça com \(best.title)")
                .font(.title2.weight(.heavy))
                .foregroundStyle(Theme.accent)
            Text("Economia de \(Fmt.money(fuel.savingsPer100Km, hidden: privacy)) a cada 100 km frente ao outro combustível.")
                .font(.subheadline)
        }
        .padding(.vertical, 4)
        InfoRow(label: "Rendimento real etanol ÷ gasolina", value: Fmt.percent(fuel.efficiencyRatio))
        InfoRow(label: "Preço etanol ÷ gasolina", value: Fmt.percent(fuel.priceRatio))
        InfoRow(label: "Etanol compensa até", value: "\(Fmt.brl(fuel.ethanolBreakEvenPrice))/L", color: Theme.accent)
        Text(verbatim: "A regra genérica dos 70% não vale para todo carro: o cálculo usa a relação de consumo medida no seu veículo.")
            .font(.caption)
            .foregroundStyle(Theme.muted)
    }
}

struct FuelEntrySheet: View {
    let lastOdometer: Double

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var date = Date()
    @State private var fuel: FuelType = .ethanol
    @State private var liters = 0.0
    @State private var totalPaid = 0.0
    @State private var odometer = 0.0
    @State private var fullTank = true

    private var isValid: Bool {
        liters > 0 && totalPaid > 0 && odometer > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Data", selection: $date, in: ...Date(), displayedComponents: .date)
                    Picker("Combustível", selection: $fuel) {
                        ForEach(FuelType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    DecimalField(title: "Litros", value: $liters, suffix: "L", digits: 2)
                    DecimalField(title: "Valor pago", value: $totalPaid, suffix: "R$")
                    DecimalField(title: "Odômetro", value: $odometer, suffix: "km", digits: 0)
                    Toggle("Completei o tanque", isOn: $fullTank)
                } footer: {
                    Text(lastOdometer > 0
                         ? "Último odômetro registrado: \(Fmt.number(lastOdometer, digits: 0)) km. O consumo é medido entre dois abastecimentos de tanque cheio."
                         : "O consumo é medido entre dois abastecimentos de tanque cheio.")
                }
                if liters > 0 && totalPaid > 0 {
                    Section {
                        LabeledContent("Preço por litro", value: Fmt.brl(totalPaid / liters))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Novo abastecimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        context.insert(FuelEntry(date: date, fuel: fuel, liters: liters, totalPaid: totalPaid,
                                                 odometer: odometer, fullTank: fullTank))
                        try? context.save()
                        ShiftManager.shared.refreshShared()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
