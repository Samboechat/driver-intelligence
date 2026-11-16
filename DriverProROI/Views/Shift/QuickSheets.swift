import SwiftData
import SwiftUI

/// Lançamento rápido do valor de uma corrida durante o turno.
struct LiveEntrySheet: View {
    let category: RideCategory

    @Environment(\.dismiss) private var dismiss
    @State private var amount = 0.0

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Valor recebido na corrida")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("R$")
                        .font(.title.weight(.bold))
                        .foregroundStyle(Theme.muted)
                    DecimalField(title: "", value: $amount, autoFocus: true, large: true)
                }
                .padding(.horizontal, 24)
                Button {
                    ShiftManager.shared.addEntry(category, amount: amount)
                    dismiss()
                } label: {
                    Label("Lançar corrida", systemImage: "checkmark")
                }
                .buttonStyle(BigButtonStyle(color: amount > 0 ? Theme.accent : Theme.cardRaised,
                                            foreground: amount > 0 ? .black : Theme.muted))
                .disabled(amount <= 0)
                .padding(.horizontal, 16)
                Spacer()
            }
            .padding(.top, 24)
            .screenBackground()
            .navigationTitle(category.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Despesa de rua: 1 toque no valor sugerido já registra.
struct QuickExpenseSheet: View {
    let category: ExpenseCategory

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var custom = 0.0

    private let columns = [
        GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Toque no valor para registrar")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(category.quickAmounts, id: \.self) { value in
                        Button {
                            save(value)
                        } label: {
                            Text(Fmt.brl(value))
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(TileButtonStyle())
                    }
                }
                HStack(spacing: 12) {
                    DecimalField(title: "Outro valor (R$)", value: $custom)
                        .padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Button {
                        save(custom)
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(width: 56, height: 52)
                            .background(custom > 0 ? Theme.accent : Theme.cardRaised,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(custom <= 0)
                }
                Spacer()
            }
            .padding(16)
            .screenBackground()
            .navigationTitle(category.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save(_ amount: Double) {
        guard amount > 0 else { return }
        context.insert(Expense(date: Date(), category: category, amount: amount))
        try? context.save()
        ShiftManager.shared.refreshShared()
        dismiss()
    }
}
