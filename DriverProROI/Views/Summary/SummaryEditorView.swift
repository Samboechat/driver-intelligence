import SwiftData
import SwiftUI

/// Fechamento / Resumo Geral Diário: ganhos por categoria × km do GPS × horas ativas.
struct SummaryEditorView: View {
    let engine: FinanceEngine
    let allowsDayChange: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("privacyMode") private var privacy = false
    @State private var model: SummaryEditorViewModel
    @State private var showDetails = false
    @State private var showOCR = false
    @State private var confirmDelete = false

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    init(day: Date, engine: FinanceEngine, allowsDayChange: Bool) {
        self.engine = engine
        self.allowsDayChange = allowsDayChange
        _model = State(initialValue: SummaryEditorViewModel(day: day, engine: engine))
    }

    var body: some View {
        Form {
            daySection
            resultSection
            earningsSection
            extrasSection
            operationSection
            costsSection
            notesSection
            if model.hasExisting {
                Section {
                    Button("Excluir resumo deste dia", role: .destructive) {
                        confirmDelete = true
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Resumo do dia")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fechar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") {
                    model.save(context: context, engine: engine)
                    dismiss()
                }
                .fontWeight(.bold)
            }
        }
        .onChange(of: model.day) { _, _ in
            model.load(from: engine)
        }
        .sheet(isPresented: $showOCR) {
            OCRImportView { result, category in
                model.apply(result, category: category)
            }
        }
        .confirmationDialog("Excluir o resumo deste dia?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Excluir", role: .destructive) {
                model.delete(context: context, engine: engine)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    // MARK: Seções

    private var daySection: some View {
        Section {
            if allowsDayChange {
                DatePicker("Dia", selection: $model.day, in: ...Date(), displayedComponents: .date)
                if model.hasExisting {
                    Text("Já existe um resumo neste dia. Ao salvar, ele será atualizado.")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
            } else {
                LabeledContent("Dia", value: Fmt.date(model.day, "EEEE, dd/MM/yyyy"))
            }
            Button {
                showOCR = true
            } label: {
                Label("Importar print do resumo (Uber/99)", systemImage: "doc.text.viewfinder")
            }
        }
    }

    private var resultSection: some View {
        let result = model.preview(engine: engine)
        return Section("Resultado") {
            LazyVGrid(columns: columns, spacing: 10) {
                MetricTile(title: "Lucro líquido real", value: Fmt.money(result.net, hidden: privacy),
                           signal: result.net >= 0 ? .green : .red,
                           caption: "margem \(Fmt.percent(result.margin))")
                MetricTile(title: "Faturamento bruto", value: Fmt.money(result.gross, hidden: privacy))
                MetricTile(title: "R$/km bruto", value: Fmt.money(result.grossPerKm, hidden: privacy),
                           signal: engine.signal(perKm: result.grossPerKm))
                MetricTile(title: "R$/km líquido", value: Fmt.money(result.netPerKm, hidden: privacy))
                MetricTile(title: "R$/hora bruto", value: Fmt.money(result.grossPerHour, hidden: privacy),
                           signal: engine.signal(perHour: result.grossPerHour))
                MetricTile(title: "R$/hora líquida", value: Fmt.money(result.netPerHour, hidden: privacy))
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            InfoRow(label: "Combustível", value: Fmt.money(result.fuel, hidden: privacy))
            InfoRow(label: "Custo fixo do dia", value: Fmt.money(result.fixed, hidden: privacy))
            InfoRow(label: "Reserva de manutenção", value: Fmt.money(result.reserve, hidden: privacy))
            InfoRow(label: "Despesas de rua", value: Fmt.money(result.extras, hidden: privacy))
            if result.excess > 0 {
                InfoRow(label: "Multa de km excedente", value: Fmt.money(result.excess, hidden: privacy), color: Theme.danger)
            }
            if let deadhead = result.deadheadShare {
                InfoRow(label: "Km vazio (sem passageiro)", value: Fmt.percent(deadhead),
                        color: deadhead > 0.45 ? Theme.danger : Color.white)
            }
        }
    }

    private var earningsSection: some View {
        Section {
            ForEach(RideCategory.allCases) { category in
                VStack(spacing: 8) {
                    DecimalField(title: category.title, value: grossBinding(category), suffix: "R$")
                    IntField(title: "Viagens", value: tripsBinding(category))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    if showDetails {
                        DecimalField(title: "Horas na categoria", value: hoursBinding(category), suffix: "h")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                        DecimalField(title: "Km em corrida", value: kmBinding(category), suffix: "km", digits: 1)
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.vertical, 2)
            }
            Toggle("Detalhar horas e km por categoria", isOn: $showDetails)
                .font(.subheadline)
        } header: {
            Text("Ganhos brutos por categoria")
        } footer: {
            Text("Informe a tarifa base de cada categoria. Dinâmico, promoções e gorjetas vão nos campos abaixo. O detalhamento por categoria deixa a análise de rentabilidade exata; sem ele, horas e km são rateados pelo número de viagens.")
        }
    }

    private var extrasSection: some View {
        Section("Extras") {
            DecimalField(title: "Gorjetas", value: $model.tips, suffix: "R$")
            DecimalField(title: "Dinâmico / Promoções", value: $model.surge, suffix: "R$")
            LabeledContent("Quantidade de viagens", value: "\(model.totalTrips)")
        }
    }

    private var operationSection: some View {
        Section {
            DecimalField(title: "Horas ativas", value: $model.activeHours, suffix: "h")
            DecimalField(title: "Horas dirigindo", value: $model.drivingHours, suffix: "h")
            DecimalField(title: "Horas em pausa", value: $model.pausedHours, suffix: "h")
            DecimalField(title: "Km rodados (GPS)", value: $model.gpsKm, suffix: "km", digits: 1)
            DecimalField(title: "Km em corrida (com passageiro)", value: $model.productiveKm, suffix: "km", digits: 1)
            DecimalField(title: "Odômetro inicial", value: $model.odometerStart, suffix: "km", digits: 0)
            DecimalField(title: "Odômetro final", value: $model.odometerEnd, suffix: "km", digits: 0)
            if let difference = model.odometerDifferencePct {
                InfoRow(label: "Odômetro × GPS",
                        value: auditText(difference),
                        color: abs(difference) > 5 ? Theme.warning : Theme.accent)
            }
        } header: {
            Text("Operação e auditoria de odômetro")
        } footer: {
            Text("Horas e km vêm do turno com GPS e podem ser ajustados. Se o odômetro do painel for informado, ele passa a valer para o cálculo de custos. Em dias sem GPS, preencha manualmente.")
        }
    }

    private var costsSection: some View {
        Section {
            Toggle("Informar combustível gasto no dia", isOn: $model.useManualFuel)
            if model.useManualFuel {
                DecimalField(title: "Combustível gasto", value: $model.manualFuel, suffix: "R$")
            } else {
                DecimalField(title: "Combustível por km", value: $model.fuelCostPerKm, suffix: "R$/km", digits: 3)
            }
            DecimalField(title: "Custo fixo do dia", value: $model.fixedCost, suffix: "R$")
            Button("Recalcular custos com o perfil atual") {
                model.refreshCosts(engine: engine)
            }
        } header: {
            Text("Custos do dia")
        } footer: {
            Text("O custo por km vem dos seus abastecimentos reais; o custo fixo vem do perfil do veículo (locação ou rateio do carro próprio).")
        }
    }

    private var notesSection: some View {
        Section("Observações") {
            TextField("Chuva, evento, região trabalhada…", text: $model.notes, axis: .vertical)
                .lineLimit(1...4)
        }
    }

    private func auditText(_ difference: Double) -> String {
        let sign = difference >= 0 ? "+" : ""
        let percent = Fmt.number(difference, digits: 1)
        return Fmt.km(model.odometerKm) + " × " + Fmt.km(model.gpsKm) + " (" + sign + percent + "%)"
    }

    // MARK: Bindings por categoria

    private func grossBinding(_ category: RideCategory) -> Binding<Double> {
        Binding(
            get: { model.figure(category).gross },
            set: { value in model.update(category) { $0.gross = value } }
        )
    }

    private func tripsBinding(_ category: RideCategory) -> Binding<Int> {
        Binding(
            get: { model.figure(category).trips },
            set: { value in model.update(category) { $0.trips = value } }
        )
    }

    private func hoursBinding(_ category: RideCategory) -> Binding<Double> {
        Binding(
            get: { model.figure(category).hours },
            set: { value in model.update(category) { $0.hours = value } }
        )
    }

    private func kmBinding(_ category: RideCategory) -> Binding<Double> {
        Binding(
            get: { model.figure(category).km },
            set: { value in model.update(category) { $0.km = value } }
        )
    }
}
