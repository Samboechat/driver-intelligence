import Foundation
import SwiftData
import UIKit

enum BackupError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        "O arquivo selecionado não é um backup válido do DriverPro ROI."
    }
}

/// Exportação CSV/PDF e backup local em JSON (tudo no aparelho, sem servidor).
@MainActor
enum ExportService {
    // MARK: Arquivos

    static var documentsFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
    }

    static var backupsFolder: URL {
        let folder = documentsFolder.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func exportFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DriverProExport", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func write(_ text: String, name: String) -> URL? {
        let url = exportFolder().appendingPathComponent(name)
        // BOM para o Excel abrir acentos corretamente.
        let content = "\u{FEFF}" + text
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func stamp() -> String {
        Fmt.date(Date(), "yyyy-MM-dd")
    }

    // MARK: CSV

    private static func num(_ value: Double, _ digits: Int = 2) -> String {
        Fmt.number(value, digits: digits)
    }

    private static func text(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"").replacingOccurrences(of: "\n", with: " ") + "\""
    }

    static func summariesCSV(engine: FinanceEngine) -> URL? {
        var header = ["Data"]
        for category in RideCategory.allCases {
            header.append("Bruto \(category.short)")
            header.append("Viagens \(category.short)")
        }
        header.append(contentsOf: [
            "Gorjetas", "Dinâmico/Promoções", "Bruto total", "Viagens", "Horas ativas", "Horas dirigindo",
            "Horas paradas ociosas", "Horas em pausa", "Km (custo)", "Km GPS", "Km em corrida", "Odômetro inicial",
            "Odômetro final", "Combustível", "Custo fixo", "Reserva manutenção", "Despesas de rua",
            "Multa km excedente", "Lucro líquido", "Margem %", "R$/km bruto", "R$/km líquido",
            "R$/h bruto", "R$/h líquido", "Observações"
        ])
        var rows = [header.joined(separator: ";")]
        for (index, summary) in engine.summaries.enumerated() {
            let day = engine.breakdowns[index]
            let figures = summary.figures
            var columns = [Fmt.date(summary.day, "dd/MM/yyyy")]
            for category in RideCategory.allCases {
                let item = figures[category] ?? CategoryFigures()
                columns.append(num(item.gross))
                columns.append("\(item.trips)")
            }
            let earnings: [String] = [
                num(summary.tips), num(summary.surge), num(day.gross), "\(day.trips)"
            ]
            let operation: [String] = [
                num(day.hours), num(day.drivingHours), num(day.idleHours), num(day.pausedHours),
                num(day.km, 1), num(summary.gpsKm, 1), num(summary.productiveKm, 1),
                num(summary.odometerStart, 0), num(summary.odometerEnd, 0)
            ]
            let costs: [String] = [
                num(day.fuel), num(day.fixed), num(day.reserve), num(day.extras), num(day.excess)
            ]
            let results: [String] = [
                num(day.net), num(day.margin * 100, 1), num(day.grossPerKm), num(day.netPerKm),
                num(day.grossPerHour), num(day.netPerHour), text(summary.notes)
            ]
            columns.append(contentsOf: earnings + operation + costs + results)
            rows.append(columns.joined(separator: ";"))
        }
        return write(rows.joined(separator: "\r\n"), name: "driverpro-resumos-\(stamp()).csv")
    }

    static func expensesCSV(_ expenses: [Expense]) -> URL? {
        var rows = ["Data;Hora;Categoria;Valor;Observação"]
        for expense in expenses.sorted(by: { $0.date < $1.date }) {
            rows.append([
                Fmt.date(expense.date, "dd/MM/yyyy"), Fmt.date(expense.date, "HH:mm"),
                expense.category.title, num(expense.amount), text(expense.note)
            ].joined(separator: ";"))
        }
        return write(rows.joined(separator: "\r\n"), name: "driverpro-despesas-\(stamp()).csv")
    }

    static func fuelCSV(_ entries: [FuelEntry]) -> URL? {
        var rows = ["Data;Combustível;Litros;Valor pago;Preço por litro;Odômetro;Tanque cheio"]
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            rows.append([
                Fmt.date(entry.date, "dd/MM/yyyy"), entry.fuel.title, num(entry.liters), num(entry.totalPaid),
                num(entry.pricePerLiter, 3), num(entry.odometer, 0), entry.fullTank ? "Sim" : "Não"
            ].joined(separator: ";"))
        }
        return write(rows.joined(separator: "\r\n"), name: "driverpro-abastecimentos-\(stamp()).csv")
    }

    // MARK: PDF

    /// Relatório PDF: DRE da semana, do mês e do ano + projeção + últimos dias.
    static func pdfReport(engine: FinanceEngine, now: Date = Date()) -> URL? {
        let calendar = Calendar.br
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 40
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let titleFont = UIFont.boldSystemFont(ofSize: 20)
        let headingFont = UIFont.boldSystemFont(ofSize: 14)
        let bodyFont = UIFont.systemFont(ofSize: 11)
        let boldFont = UIFont.boldSystemFont(ofSize: 11)

        var sections: [(title: String, report: DREReport)] = []
        if let week = calendar.dateInterval(of: .weekOfYear, for: now) {
            sections.append(("Semana atual", engine.dre(week, now: now)))
        }
        if let month = calendar.dateInterval(of: .month, for: now) {
            sections.append(("Mês atual — \(Fmt.date(now, "MMMM 'de' yyyy"))", engine.dre(month, now: now)))
        }
        if let year = calendar.dateInterval(of: .year, for: now) {
            sections.append(("Ano de \(Fmt.date(now, "yyyy"))", engine.dre(year, now: now)))
        }
        let runRate = engine.runRate(now: now)
        let recent = Array(engine.breakdowns.suffix(31).reversed())

        let data = renderer.pdfData { context in
            var y: CGFloat = margin
            context.beginPage()

            func ensureSpace(_ height: CGFloat) {
                if y + height > page.height - margin {
                    context.beginPage()
                    y = margin
                }
            }

            func draw(_ string: String, font: UIFont, color: UIColor = .black) {
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                (string as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: attributes)
            }

            func line(_ label: String, _ value: String, bold: Bool = false) {
                ensureSpace(16)
                draw(label, font: bold ? boldFont : bodyFont)
                let attributes: [NSAttributedString.Key: Any] = [.font: bold ? boldFont : bodyFont, .foregroundColor: UIColor.black]
                let width = (value as NSString).size(withAttributes: attributes).width
                (value as NSString).draw(at: CGPoint(x: page.width - margin - width, y: y), withAttributes: attributes)
                y += 16
            }

            draw("DriverPro ROI — Relatório de Lucro Real", font: titleFont)
            y += 28
            draw("Gerado em \(Fmt.date(now, "dd/MM/yyyy 'às' HH:mm"))", font: bodyFont, color: .darkGray)
            y += 24

            for section in sections {
                let report = section.report
                ensureSpace(200)
                draw(section.title, font: headingFont)
                y += 22
                line("Receita bruta", Fmt.brl(report.totals.gross), bold: true)
                line("   Gorjetas", Fmt.brl(report.totals.tips))
                line("   Dinâmico e promoções", Fmt.brl(report.totals.surge))
                line("(−) Combustível", Fmt.brl(report.totals.fuel))
                line("(−) Despesas de rua", Fmt.brl(report.totals.extras))
                line("(−) Reserva de manutenção", Fmt.brl(report.totals.reserve))
                line("(−) Multa de km excedente", Fmt.brl(report.totals.excess))
                line("(−) Custo fixo dos dias trabalhados", Fmt.brl(report.totals.fixed))
                line("(−) Custo fixo de \(report.idleDays) dia(s) parado(s)", Fmt.brl(report.idleFixedCost))
                line("Lucro líquido", Fmt.brl(report.net), bold: true)
                line("Margem líquida", Fmt.percent(report.margin), bold: true)
                line("Dias trabalhados / km / horas",
                     "\(report.totals.days) / \(Fmt.number(report.totals.km, digits: 0)) km / \(Fmt.hours(report.totals.hours))")
                line("R$/km bruto · R$/km líquido",
                     "\(Fmt.brl(report.totals.grossPerKm)) · \(Fmt.brl(report.totals.netPerKm))")
                line("R$/h bruto · R$/h líquido",
                     "\(Fmt.brl(report.totals.grossPerHour)) · \(Fmt.brl(report.totals.netPerHour))")
                y += 14
            }

            ensureSpace(90)
            draw("Projeção do mês (run-rate)", font: headingFont)
            y += 22
            line("Lucro médio por dia trabalhado", Fmt.brl(runRate.avgNetPerWorkedDay))
            line("Dias de trabalho restantes", "\(runRate.remainingWorkDays)")
            line("Faturamento projetado", Fmt.brl(runRate.projectedGross))
            line("Lucro líquido projetado", Fmt.brl(runRate.projectedNet), bold: true)
            y += 14

            ensureSpace(60)
            draw("Últimos dias", font: headingFont)
            y += 22
            for day in recent {
                line("\(Fmt.date(day.day, "EEE dd/MM"))  ·  \(Fmt.number(day.km, digits: 0)) km  ·  \(Fmt.hours(day.hours))",
                     "bruto \(Fmt.brl(day.gross))   líquido \(Fmt.brl(day.net))")
            }
        }

        let url = exportFolder().appendingPathComponent("driverpro-relatorio-\(stamp()).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Backup JSON

    private static func fetchAll<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    static func backupData(context: ModelContext) -> Data? {
        let file = BackupFile(
            shifts: fetchAll(Shift.self, context).map { ShiftDTO($0) },
            summaries: fetchAll(DailySummary.self, context).map { SummaryDTO($0) },
            expenses: fetchAll(Expense.self, context).map { ExpenseDTO($0) },
            fuel: fetchAll(FuelEntry.self, context).map { FuelDTO($0) },
            movements: fetchAll(VaultMovement.self, context).map { MovementDTO($0) },
            dayOffs: fetchAll(DayOff.self, context).map { DayOffDTO($0) },
            zones: fetchAll(LowLiquidityZone.self, context).map { ZoneDTO($0) },
            blocks: fetchAll(ScheduleBlock.self, context).map { BlockDTO($0) },
            vehicle: VehicleDTO(Store.vehicle(context)),
            settings: SettingsDTO(Store.settings(context))
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(file)
    }

    /// Gera um backup datado em Documentos/Backups (visível no app Arquivos) e devolve a URL.
    static func exportBackup(context: ModelContext) -> URL? {
        guard let data = backupData(context: context) else { return nil }
        let url = backupsFolder.appendingPathComponent("driverpro-backup-\(Fmt.date(Date(), "yyyy-MM-dd-HHmm")).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Backup automático silencioso, sobrescrito sempre que o app vai para segundo plano.
    static func autoBackup() {
        let context = Store.container.mainContext
        guard let data = backupData(context: context) else { return }
        let url = backupsFolder.appendingPathComponent("driverpro-backup-automatico.json")
        try? data.write(to: url, options: .atomic)
    }

    /// Substitui todos os dados do app pelo conteúdo do backup.
    static func restore(from data: Data, context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(BackupFile.self, from: data) else {
            throw BackupError.unreadable
        }

        for item in fetchAll(Shift.self, context) { context.delete(item) }
        for item in fetchAll(DailySummary.self, context) { context.delete(item) }
        for item in fetchAll(Expense.self, context) { context.delete(item) }
        for item in fetchAll(FuelEntry.self, context) { context.delete(item) }
        for item in fetchAll(VaultMovement.self, context) { context.delete(item) }
        for item in fetchAll(DayOff.self, context) { context.delete(item) }
        for item in fetchAll(LowLiquidityZone.self, context) { context.delete(item) }
        for item in fetchAll(ScheduleBlock.self, context) { context.delete(item) }

        for item in file.shifts { context.insert(item.makeModel()) }
        for item in file.summaries { context.insert(item.makeModel()) }
        for item in file.expenses { context.insert(item.makeModel()) }
        for item in file.fuel { context.insert(item.makeModel()) }
        for item in file.movements { context.insert(item.makeModel()) }
        for item in file.dayOffs { context.insert(item.makeModel()) }
        for item in file.zones { context.insert(item.makeModel()) }
        for item in file.blocks { context.insert(item.makeModel()) }
        file.vehicle.apply(to: Store.vehicle(context))
        file.settings.apply(to: Store.settings(context))
        try context.save()
        ShiftManager.shared.reloadConfig()
        ShiftManager.shared.refreshShared()
    }
}
