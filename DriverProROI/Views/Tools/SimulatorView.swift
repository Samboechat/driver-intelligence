import Observation
import SwiftUI

@MainActor
@Observable
final class SimulatorViewModel {
    var fare = 0.0
    var tripKm = 0.0
    var returnKm = 0.0
    var minutes = 0.0
    /// Retorno vazio com a mesma distância da ida (corridas intermunicipais).
    var emptyReturn = true

    var effectiveReturnKm: Double { emptyReturn ? tripKm : returnKm }

    /// Tempo total: ida + volta vazia proporcional quando não informado à parte.
    var totalMinutes: Double { emptyReturn ? minutes * 2 : minutes }

    var isReady: Bool { fare > 0 && tripKm > 0 && minutes > 0 }

    func result(engine: FinanceEngine) -> TripSimulation {
        engine.simulate(fare: fare, tripKm: tripKm, returnKm: effectiveReturnKm, minutes: totalMinutes)
    }

    func clear() {
        fare = 0
        tripKm = 0
        returnKm = 0
        minutes = 0
    }
}

/// Simulador rápido de viabilidade de corrida longa ou intermunicipal.
struct SimulatorView: View {
    let engine: FinanceEngine

    @AppStorage("privacyMode") private var privacy = false
    @State private var model = SimulatorViewModel()

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        Form {
            Section {
                DecimalField(title: "Valor da corrida", value: $model.fare, suffix: "R$")
                DecimalField(title: "Distância da corrida", value: $model.tripKm, suffix: "km", digits: 1)
                DecimalField(title: "Tempo estimado (ida)", value: $model.minutes, suffix: "min", digits: 0)
                Toggle("Volta vazia pela mesma distância", isOn: $model.emptyReturn)
                if !model.emptyReturn {
                    DecimalField(title: "Km de retorno vazio", value: $model.returnKm, suffix: "km", digits: 1)
                }
            } header: {
                Text("Corrida")
            } footer: {
                Text("Com a volta vazia ativada, distância e tempo são dobrados. Desative se houver boa chance de corrida de retorno e informe só o trecho vazio.")
            }

            if model.isReady {
                resultSection(model.result(engine: engine))
            }

            Section {
                Button("Limpar") {
                    model.clear()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Simulador de corrida")
        .navigationBarTitleDisplayMode(.inline)
        .privacyToolbar()
    }

    private func resultSection(_ result: TripSimulation) -> some View {
        let color = result.worthIt ? Theme.accent : (result.paysCosts ? Theme.warning : Theme.danger)
        let verdict: String
        if result.worthIt {
            verdict = "Vale a pena: paga os custos e fica dentro das suas metas."
        } else if result.paysCosts {
            verdict = "Paga os custos, mas fica abaixo do seu piso de R$/km ou R$/hora."
        } else {
            verdict = "Não paga nem o custo total do km rodado. Recuse."
        }
        return Section("Resultado") {
            Label(verdict, systemImage: result.worthIt ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(color)
            LazyVGrid(columns: columns, spacing: 10) {
                MetricTile(title: "R$/km (km total)", value: Fmt.money(result.grossPerKm, hidden: privacy), signal: result.kmSignal)
                MetricTile(title: "R$/hora (tempo total)", value: Fmt.money(result.grossPerHour, hidden: privacy), signal: result.hourSignal)
                MetricTile(title: "Lucro da corrida", value: Fmt.money(result.net, hidden: privacy),
                           signal: result.net >= 0 ? .green : .red, caption: "após combustível e desgaste")
                MetricTile(title: "Lucro por hora", value: Fmt.money(result.netPerHour, hidden: privacy))
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            InfoRow(label: "Km total (ida + vazio)", value: Fmt.km(result.totalKm))
            InfoRow(label: "Tempo total", value: Fmt.hours(result.hours))
            InfoRow(label: "Combustível + desgaste", value: Fmt.money(result.variableCost, hidden: privacy))
            InfoRow(label: "Custo cheio (com rateio do veículo)", value: Fmt.money(result.fullCost, hidden: privacy))
        }
    }
}
