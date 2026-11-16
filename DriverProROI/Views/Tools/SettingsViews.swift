import SwiftData
import SwiftUI

/// Perfil híbrido de veículo: alugado ou próprio.
struct VehicleSettingsView: View {
    @Bindable var vehicle: VehicleProfile

    @Environment(\.modelContext) private var context
    @AppStorage("privacyMode") private var privacy = false

    var body: some View {
        Form {
            Section {
                TextField("Nome do veículo", text: $vehicle.name)
                Picker("Modo", selection: $vehicle.mode) {
                    ForEach(VehicleMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if vehicle.mode == .rented {
                Section {
                    Picker("Contrato", selection: $vehicle.rentPeriod) {
                        ForEach(RentPeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    DecimalField(title: "Valor do aluguel", value: $vehicle.rentAmount, suffix: "R$")
                    DecimalField(title: "Franquia de km no período", value: $vehicle.franchiseKm, suffix: "km", digits: 0)
                    DecimalField(title: "Multa por km excedente", value: $vehicle.excessFeePerKm, suffix: "R$/km")
                } header: {
                    Text("Carro alugado")
                } footer: {
                    Text("Deixe a franquia em 0 se o contrato for de km livre. A multa é calculada automaticamente quando os km do período passam da franquia.")
                }
            } else {
                Section {
                    DecimalField(title: "IPVA (ano)", value: $vehicle.ipvaAnnual, suffix: "R$")
                    DecimalField(title: "Seguro (ano)", value: $vehicle.insuranceAnnual, suffix: "R$")
                    DecimalField(title: "Licenciamento e taxas (ano)", value: $vehicle.licensingAnnual, suffix: "R$")
                    DecimalField(title: "Valor FIPE", value: $vehicle.fipeValue, suffix: "R$")
                    DecimalField(title: "Depreciação anual", value: $vehicle.depreciationPct, suffix: "%", digits: 1)
                    DecimalField(title: "Parcela do financiamento (mês)", value: $vehicle.financingMonthly, suffix: "R$")
                } header: {
                    Text("Carro próprio")
                } footer: {
                    Text("IPVA, seguro, depreciação FIPE e financiamento são rateados por dia corrido. O fundo de manutenção por km é configurado em Metas e alertas > Cofre.")
                }
            }

            Section("Custo fixo resultante") {
                InfoRow(label: "Por dia", value: Fmt.money(vehicle.dailyFixedCost, hidden: privacy), color: Theme.warning, bold: true)
                InfoRow(label: "Por semana", value: Fmt.money(vehicle.dailyFixedCost * 7, hidden: privacy))
                InfoRow(label: "Por mês (30 dias)", value: Fmt.money(vehicle.dailyFixedCost * 30, hidden: privacy))
            }

            Section {
                DecimalField(title: "Consumo com etanol", value: $vehicle.kmPerLEthanol, suffix: "km/L", digits: 1)
                DecimalField(title: "Consumo com gasolina", value: $vehicle.kmPerLGasoline, suffix: "km/L", digits: 1)
                DecimalField(title: "Preço do etanol", value: $vehicle.priceEthanol, suffix: "R$/L", digits: 3)
                DecimalField(title: "Preço da gasolina", value: $vehicle.priceGasoline, suffix: "R$/L", digits: 3)
            } header: {
                Text("Consumo de referência")
            } footer: {
                Text("Usado apenas até você registrar abastecimentos; depois disso valem o consumo e os preços reais.")
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Veículo")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            try? context.save()
            ShiftManager.shared.refreshShared()
        }
    }
}

/// Metas do semáforo, meta semanal, cofre virtual e alertas.
struct GoalsSettingsView: View {
    @Bindable var settings: AppSettings

    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            Section {
                DecimalField(title: "Piso de R$/km bruto", value: $settings.minPerKm, suffix: "R$")
                DecimalField(title: "Piso de R$/hora bruto", value: $settings.minPerHour, suffix: "R$")
                DecimalField(title: "Faixa amarela abaixo do piso", value: $settings.yellowMarginPct, suffix: "%", digits: 0)
            } header: {
                Text("Semáforo de meta")
            } footer: {
                Text("Verde = no piso ou acima. Amarelo = até a margem abaixo do piso. Vermelho = abaixo disso.")
            }

            Section {
                DecimalField(title: "Meta semanal de lucro líquido", value: $settings.weeklyNetGoal, suffix: "R$")
            } header: {
                Text("Meta semanal")
            } footer: {
                Text("A meta de cada dia é recalculada sozinha conforme o resultado dos dias anteriores e os dias de trabalho do Cronograma.")
            }

            Section {
                Picker("Reservar por", selection: $settings.vaultMode) {
                    ForEach(VaultMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                if settings.vaultMode == .perKm {
                    DecimalField(title: "Reserva por km rodado", value: $settings.vaultPerKm, suffix: "R$/km", digits: 3)
                } else {
                    DecimalField(title: "Reserva sobre o bruto", value: $settings.vaultPct, suffix: "%", digits: 1)
                }
                DecimalField(title: "Excedente enviado ao banco de folga", value: $settings.dayOffBankPct, suffix: "%", digits: 0)
            } header: {
                Text("Cofre virtual e banco de folga")
            } footer: {
                Text("A reserva de manutenção é descontada do lucro líquido de cada dia e acumulada no cofre (pneus, óleo, caução, parcelas). O banco de folga guarda parte do que passar da meta diária.")
            }

            Section {
                DecimalField(title: "Corrida curta: ticket abaixo de", value: $settings.shortTicketLimit, suffix: "R$")
                DecimalField(title: "Corrida longa: ticket acima de", value: $settings.longTicketLimit, suffix: "R$")
            } header: {
                Text("Perfil de corrida")
            }

            Section {
                Toggle("Queda de rendimento por hora", isOn: $settings.hourlyAlertEnabled)
                Toggle("Fadiga (8h, 10h e 12h)", isOn: $settings.fatigueAlertEnabled)
                Toggle("Zonas de baixa liquidez", isOn: $settings.zoneAlertEnabled)
            } header: {
                Text("Alertas")
            } footer: {
                Text("O alerta de rendimento é discreto (sem som) e usa as corridas lançadas durante o turno.")
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Metas e alertas")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            try? context.save()
            ShiftManager.shared.reloadConfig()
            ShiftManager.shared.refreshShared()
        }
    }
}
