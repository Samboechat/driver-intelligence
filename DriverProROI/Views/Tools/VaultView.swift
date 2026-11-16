import SwiftData
import SwiftUI

/// Cofre virtual de reserva (manutenção/renovação) e banco de folga remunerada.
struct VaultView: View {
    let engine: FinanceEngine

    @Environment(\.modelContext) private var context
    @AppStorage("privacyMode") private var privacy = false
    @State private var withdrawKind: VaultKindRef?

    private func money(_ value: Double) -> String {
        Fmt.money(value, hidden: privacy)
    }

    private var movements: [VaultMovement] {
        engine.movements.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Saldo do cofre")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    Text(money(engine.vaultBalance))
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(engine.vaultBalance >= 0 ? Theme.accent : Theme.danger)
                }
                InfoRow(label: "Reservado até hoje", value: money(engine.vaultCredits))
                InfoRow(label: "Já utilizado", value: money(engine.vaultWithdrawals))
                InfoRow(label: "Regra atual", value: ruleText)
                Button {
                    withdrawKind = VaultKindRef(kind: .maintenance)
                } label: {
                    Label("Registrar uso (pneu, óleo, revisão, caução)", systemImage: "wrench.and.screwdriver.fill")
                }
            } header: {
                Text("Cofre de manutenção e renovação")
            } footer: {
                Text("Saldo virtual: é o quanto você deveria ter separado para trocar pneus, óleo e pagar parcelas sem tirar do lucro do mês.")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Saldo do banco de folga")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    Text(money(engine.dayOffBalance))
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(engine.dayOffBalance >= 0 ? Theme.info : Theme.danger)
                }
                InfoRow(label: "Excedentes acumulados", value: money(engine.dayOffCredits))
                InfoRow(label: "Folgas e retiradas", value: money(engine.dayOffDebits))
                InfoRow(label: "Dias de folga cobertos", value: Fmt.number(engine.dayOffDaysCovered, digits: 1), color: Theme.info, bold: true)
                InfoRow(label: "Custo fixo de 1 dia parado", value: money(engine.vehicle.dailyFixedCost))
                Button {
                    withdrawKind = VaultKindRef(kind: .dayOff)
                } label: {
                    Label("Registrar retirada do banco", systemImage: "arrow.down.circle.fill")
                }
            } header: {
                Text("Banco de folga remunerada")
            } footer: {
                Text("Parte do que passa da meta diária entra aqui. Ao marcar uma Folga Remunerada no Cronograma, o custo fixo daquele dia sai deste saldo.")
            }

            if !engine.dayOffs.isEmpty {
                Section("Folgas remuneradas") {
                    ForEach(engine.dayOffs.sorted { $0.day > $1.day }) { dayOff in
                        InfoRow(label: Fmt.date(dayOff.day, "EEEE, dd/MM/yyyy").capitalized, value: money(dayOff.coveredCost))
                    }
                }
            }

            if !movements.isEmpty {
                Section("Retiradas") {
                    ForEach(movements) { movement in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(movement.note.isEmpty ? "Retirada" : movement.note)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(money(movement.amount))
                                    .monospacedDigit()
                            }
                            Text("\(Fmt.date(movement.date, "dd/MM/yyyy")) · \(movement.kind == .maintenance ? "Cofre de manutenção" : "Banco de folga")")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .onDelete { offsets in
                        let list = movements
                        for index in offsets {
                            context.delete(list[index])
                        }
                        try? context.save()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Cofre e folga")
        .navigationBarTitleDisplayMode(.inline)
        .privacyToolbar()
        .sheet(item: $withdrawKind) { reference in
            WithdrawSheet(kind: reference.kind)
        }
    }

    private var ruleText: String {
        switch engine.settings.vaultMode {
        case .perKm: return "\(Fmt.brl(engine.settings.vaultPerKm)) por km"
        case .percent: return "\(Fmt.number(engine.settings.vaultPct, digits: 1))% do bruto"
        }
    }
}

struct VaultKindRef: Identifiable {
    let kind: VaultKind
    var id: String { kind.rawValue }
}

struct WithdrawSheet: View {
    let kind: VaultKind

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var amount = 0.0
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                DecimalField(title: "Valor", value: $amount, suffix: "R$", autoFocus: true)
                TextField(kind == .maintenance ? "O que foi pago (ex.: 2 pneus)" : "Motivo", text: $note)
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(kind == .maintenance ? "Uso do cofre" : "Retirada do banco")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        context.insert(VaultMovement(date: Date(), kind: kind, amount: amount, note: note))
                        try? context.save()
                        dismiss()
                    }
                    .disabled(amount <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
