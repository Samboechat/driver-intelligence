import Foundation
import Observation
import SwiftData

/// Estado do formulário de Fechamento / Resumo Geral Diário.
@MainActor
@Observable
final class SummaryEditorViewModel {
    var day: Date
    var figures: [RideCategory: CategoryFigures] = [:]
    var tips = 0.0
    var surge = 0.0
    var activeHours = 0.0
    var pausedHours = 0.0
    var drivingHours = 0.0
    var gpsKm = 0.0
    var productiveKm = 0.0
    var odometerStart = 0.0
    var odometerEnd = 0.0
    var useManualFuel = false
    var manualFuel = 0.0
    var fuelCostPerKm = 0.0
    var fixedCost = 0.0
    var notes = ""
    private(set) var hasExisting = false
    private(set) var isManual = true

    init(day: Date, engine: FinanceEngine) {
        self.day = Calendar.br.startOfDay(for: day)
        load(from: engine)
    }

    /// Carrega o resumo existente do dia selecionado ou um formulário em branco.
    func load(from engine: FinanceEngine) {
        let normalized = Calendar.br.startOfDay(for: day)
        if normalized != day { day = normalized }
        if let summary = engine.summary(on: normalized) {
            figures = summary.figures
            tips = summary.tips
            surge = summary.surge
            activeHours = summary.activeHours
            pausedHours = summary.pausedHours
            drivingHours = summary.drivingHours
            gpsKm = summary.gpsKm
            productiveKm = summary.productiveKm
            odometerStart = summary.odometerStart
            odometerEnd = summary.odometerEnd
            useManualFuel = summary.manualFuelCost != nil
            manualFuel = summary.manualFuelCost ?? 0
            fuelCostPerKm = summary.fuelCostPerKm > 0 ? summary.fuelCostPerKm : engine.fuel.currentCostPerKm
            fixedCost = summary.fixedCost
            notes = summary.notes
            hasExisting = true
            isManual = summary.isManual
        } else {
            var empty: [RideCategory: CategoryFigures] = [:]
            for category in RideCategory.allCases {
                empty[category] = CategoryFigures()
            }
            figures = empty
            tips = 0
            surge = 0
            activeHours = 0
            pausedHours = 0
            drivingHours = 0
            gpsKm = 0
            productiveKm = 0
            odometerStart = 0
            odometerEnd = 0
            useManualFuel = false
            manualFuel = 0
            fuelCostPerKm = engine.fuel.currentCostPerKm
            fixedCost = engine.vehicle.dailyFixedCost
            notes = ""
            hasExisting = false
            isManual = true
        }
    }

    // MARK: Derivados

    var categoriesGross: Double { figures.values.reduce(0) { $0 + $1.gross } }
    var totalTrips: Int { figures.values.reduce(0) { $0 + $1.trips } }
    var totalGross: Double { categoriesGross + tips + surge }

    var odometerKm: Double {
        odometerStart > 0 && odometerEnd > odometerStart ? odometerEnd - odometerStart : 0
    }

    var costKm: Double { odometerKm > 0 ? odometerKm : gpsKm }

    /// Diferença do odômetro do painel frente ao GPS (%).
    var odometerDifferencePct: Double? {
        guard odometerKm > 0, gpsKm > 0 else { return nil }
        return (odometerKm / gpsKm - 1) * 100
    }

    func figure(_ category: RideCategory) -> CategoryFigures {
        figures[category] ?? CategoryFigures()
    }

    func update(_ category: RideCategory, _ change: (inout CategoryFigures) -> Void) {
        var item = figure(category)
        change(&item)
        figures[category] = item
    }

    /// Resultado calculado ao vivo, antes de salvar.
    func preview(engine: FinanceEngine) -> DayBreakdown {
        engine.previewBreakdown(
            day: day,
            gross: totalGross,
            tips: tips,
            surge: surge,
            trips: totalTrips,
            km: costKm,
            productiveKm: productiveKm,
            hours: activeHours,
            drivingHours: min(drivingHours, activeHours),
            pausedHours: pausedHours,
            fuelPerKm: fuelCostPerKm,
            manualFuel: useManualFuel ? manualFuel : nil,
            fixed: fixedCost
        )
    }

    /// Recalcula combustível/km e custo fixo com o perfil atual do veículo.
    func refreshCosts(engine: FinanceEngine) {
        fuelCostPerKm = engine.fuel.currentCostPerKm
        fixedCost = engine.vehicle.dailyFixedCost
    }

    /// Soma ao formulário os valores lidos de um print (OCR).
    func apply(_ result: OCRResult, category: RideCategory) {
        let tipsValue = result.tips ?? 0
        let promotions = result.promotions ?? 0
        let base = max(0, (result.total ?? 0) - tipsValue - promotions)
        update(category) { item in
            item.gross += base
            item.trips += result.trips ?? 0
        }
        tips += tipsValue
        surge += promotions
        if let hours = result.onlineHours, activeHours <= 0 {
            activeHours = hours
        }
    }

    func save(context: ModelContext, engine: FinanceEngine) {
        let target: DailySummary
        if let existing = engine.summary(on: day) {
            target = existing
        } else {
            target = DailySummary(day: day)
            target.isManual = true
            context.insert(target)
        }
        target.figures = figures
        target.tips = tips
        target.surge = surge
        target.activeHours = activeHours
        target.pausedHours = pausedHours
        target.drivingHours = min(drivingHours, activeHours)
        target.gpsKm = gpsKm
        target.productiveKm = productiveKm
        target.odometerStart = odometerStart
        target.odometerEnd = odometerEnd
        target.fuelCostPerKm = fuelCostPerKm
        target.manualFuelCost = useManualFuel ? manualFuel : nil
        target.fixedCost = fixedCost
        target.reserveCost = engine.reserveCost(gross: target.totalGross, km: target.costKm)
        target.notes = notes
        try? context.save()
        ShiftManager.shared.refreshShared()
    }

    func delete(context: ModelContext, engine: FinanceEngine) {
        if let existing = engine.summary(on: day) {
            context.delete(existing)
            try? context.save()
            ShiftManager.shared.refreshShared()
        }
    }
}
