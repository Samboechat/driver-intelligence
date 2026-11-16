import PhotosUI
import SwiftUI
import UIKit

/// Importa um print do resumo diário da Uber/99 e extrai os valores com Apple Vision.
struct OCRImportView: View {
    private let onApply: (OCRResult, RideCategory) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhotosPickerItem?
    @State private var parsed: OCRResult?
    @State private var category: RideCategory = .uberX
    @State private var total = 0.0
    @State private var tips = 0.0
    @State private var promotions = 0.0
    @State private var hours = 0.0
    @State private var trips = 0
    @State private var isReading = false
    @State private var message: String?

    init(onApply: @escaping (OCRResult, RideCategory) -> Void) {
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $selection, matching: .images) {
                        Label("Escolher captura de tela", systemImage: "photo.on.rectangle")
                    }
                    if isReading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Lendo valores…")
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    if let message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(Theme.warning)
                    }
                } footer: {
                    Text("Use o print da tela de ganhos do dia. A leitura acontece no próprio iPhone; confira os valores antes de aplicar.")
                }

                if let parsed {
                    Section("Valores lidos (edite se precisar)") {
                        Picker("Lançar em", selection: $category) {
                            ForEach(RideCategory.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        DecimalField(title: "Ganho total do print", value: $total, suffix: "R$")
                        DecimalField(title: "Gorjetas", value: $tips, suffix: "R$")
                        DecimalField(title: "Dinâmico / Promoções", value: $promotions, suffix: "R$")
                        IntField(title: "Viagens", value: $trips)
                        DecimalField(title: "Horas online", value: $hours, suffix: "h")
                    }
                    Section("Texto reconhecido") {
                        Text(parsed.lines.joined(separator: "\n"))
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Importar print")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") { apply() }
                        .disabled(parsed == nil)
                }
            }
            .onChange(of: selection) { _, item in
                guard let item else { return }
                Task { await read(item) }
            }
        }
    }

    private func read(_ item: PhotosPickerItem) async {
        isReading = true
        message = nil
        defer { isReading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw OCRError.invalidImage
            }
            let result = try await OCRService.recognize(image)
            parsed = result
            category = result.suggestedCategory
            total = result.total ?? 0
            tips = result.tips ?? 0
            promotions = result.promotions ?? 0
            hours = result.onlineHours ?? 0
            trips = result.trips ?? 0
            if !result.hasData {
                message = "Não encontrei valores neste print. Preencha manualmente ou tente outra captura."
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func apply() {
        var result = OCRResult()
        result.total = total
        result.tips = tips
        result.promotions = promotions
        result.trips = trips
        result.onlineHours = hours > 0 ? hours : nil
        onApply(result, category)
        dismiss()
    }
}
