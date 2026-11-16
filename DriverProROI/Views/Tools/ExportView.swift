import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Exportação completa (CSV + PDF) e backup/restauração local em JSON.
struct ExportView: View {
    let engine: FinanceEngine

    @Environment(\.modelContext) private var context
    @Query private var expenses: [Expense]
    @Query private var fuelEntries: [FuelEntry]
    @State private var files: [URL] = []
    @State private var backupURL: URL?
    @State private var importing = false
    @State private var pendingRestore: Data?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Button {
                    generateReports()
                } label: {
                    Label("Gerar CSV e relatório PDF", systemImage: "doc.badge.gearshape.fill")
                }
                ForEach(files, id: \.self) { url in
                    ShareLink(item: url) {
                        Label(url.lastPathComponent, systemImage: url.pathExtension == "pdf" ? "doc.richtext.fill" : "tablecells.fill")
                            .font(.subheadline)
                    }
                }
            } header: {
                Text("Exportação")
            } footer: {
                Text("Gera os resumos diários, despesas e abastecimentos em CSV (abre no Excel/Numbers) e o DRE em PDF. Toque em cada arquivo para compartilhar ou salvar.")
            }

            Section {
                Button {
                    backupURL = ExportService.exportBackup(context: context)
                    message = backupURL == nil ? "Não foi possível gerar o backup." : "Backup salvo em Arquivos > No Meu iPhone > DriverPro ROI > Backups."
                } label: {
                    Label("Fazer backup agora (JSON)", systemImage: "externaldrive.fill.badge.plus")
                }
                if let backupURL {
                    ShareLink(item: backupURL) {
                        Label(backupURL.lastPathComponent, systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                }
                Button {
                    importing = true
                } label: {
                    Label("Restaurar de um backup", systemImage: "arrow.counterclockwise.circle.fill")
                }
            } header: {
                Text("Backup local")
            } footer: {
                Text("Um backup automático também é gravado sempre que o app vai para segundo plano. Nada é enviado para servidores.")
            }

            if let message {
                Section {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Theme.info)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Exportar e backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .confirmationDialog("Substituir todos os dados pelo backup?",
                            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                            titleVisibility: .visible) {
            Button("Substituir tudo", role: .destructive) {
                restore()
            }
            Button("Cancelar", role: .cancel) {
                pendingRestore = nil
            }
        } message: {
            Text("Resumos, turnos, despesas, abastecimentos, cronograma e ajustes atuais serão apagados.")
        }
    }

    private func generateReports() {
        var generated: [URL] = []
        if let url = ExportService.pdfReport(engine: engine) { generated.append(url) }
        if let url = ExportService.summariesCSV(engine: engine) { generated.append(url) }
        if let url = ExportService.expensesCSV(expenses) { generated.append(url) }
        if let url = ExportService.fuelCSV(fuelEntries) { generated.append(url) }
        files = generated
        message = generated.isEmpty ? "Não foi possível gerar os arquivos." : nil
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            if let data = try? Data(contentsOf: url) {
                pendingRestore = data
            } else {
                message = "Não foi possível ler o arquivo selecionado."
            }
        case .failure(let error):
            message = error.localizedDescription
        }
    }

    private func restore() {
        guard let data = pendingRestore else { return }
        pendingRestore = nil
        if ShiftManager.shared.hasShift {
            message = "Encerre o turno em andamento antes de restaurar um backup."
            return
        }
        do {
            try ExportService.restore(from: data, context: context)
            message = "Backup restaurado com sucesso."
        } catch {
            message = error.localizedDescription
        }
    }
}
