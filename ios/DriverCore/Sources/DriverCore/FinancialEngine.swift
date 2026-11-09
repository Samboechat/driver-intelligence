import Foundation

/**
 * Motor financeiro — mesmas fórmulas do Android:
 *  distância total = busca + viagem · tempo total = busca + viagem
 *  R$/km = valor ÷ distância total · R$/h = valor ÷ (tempo total ÷ 60)
 *  combustível = (distância ÷ consumo) × preço · custo operacional = distância × custo/km
 *  lucro operacional = valor − combustível − custo operacional
 * Anti-duplicidade: custo único marcado "inclui combustível" não desconta o combustível de novo.
 */
public struct FinancialEngine: Sendable {
    public init() {}

    public func calculate(_ offer: OfferData, costs: CostProfile) -> FinancialResult {
        var issues: [String] = []
        var missing = Set<OfferField>()

        func input(_ v: Double?, _ f: OfferField, allowZero: Bool) -> Double? {
            guard let v else { missing.insert(f); return nil }
            if !v.isFinite || v < 0 || (!allowZero && v == 0) {
                issues.append("Valor inválido para \(f.label).")
                missing.insert(f)
                return nil
            }
            return v
        }

        let fare = input(offer.fare, .fare, allowZero: false)
        let pickupKm = input(offer.pickupDistanceKm, .pickupDistance, allowZero: true)
        let tripKm = input(offer.tripDistanceKm, .tripDistance, allowZero: false)
        let pickupMin = input(offer.pickupTimeMin, .pickupTime, allowZero: true)
        let tripMin = input(offer.tripTimeMin, .tripTime, allowZero: true)

        let totalKm = (pickupKm != nil && tripKm != nil) ? pickupKm! + tripKm! : nil
        let totalMin = (pickupMin != nil && tripMin != nil) ? pickupMin! + tripMin! : nil

        var missingCosts = Set<CostComponent>()
        let consumption = costs.consumptionKmPerUnit.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let price = costs.energyPricePerUnit.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        if costs.consumptionKmPerUnit != nil && consumption == nil { issues.append("Consumo do veículo inválido.") }
        let fuelPerKm = (consumption != nil && price != nil) ? price! / consumption! : nil

        let override = costs.operationalCostPerKmOverride.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        var operationalPerKm: Double?
        if let override {
            operationalPerKm = override
        } else {
            var sum = 0.0
            var any = false
            for (c, v) in [(CostComponent.maintenance, costs.maintenancePerKm), (.tires, costs.tiresPerKm), (.oil, costs.oilPerKm), (.depreciation, costs.depreciationPerKm)] {
                if let v, v.isFinite, v >= 0 { sum += v; any = true } else { missingCosts.insert(c) }
            }
            if let o = costs.otherCostsPerKm, o.isFinite, o >= 0 { sum += o; any = true }
            operationalPerKm = any ? sum : nil
        }

        let fuelIncluded = costs.operationalCostIncludesFuel && override != nil
        if !fuelIncluded && fuelPerKm == nil { missingCosts.insert(.fuel) }

        let fuelCost = (totalKm != nil && fuelPerKm != nil) ? totalKm! * fuelPerKm! : nil
        let operationalCost = (totalKm != nil && operationalPerKm != nil) ? totalKm! * operationalPerKm! : nil
        let deductedFuel = fuelIncluded ? 0.0 : fuelPerKm
        let costPerKm: Double? = (deductedFuel == nil && operationalPerKm == nil) ? nil : (deductedFuel ?? 0) + (operationalPerKm ?? 0)
        let totalCost = (totalKm != nil && costPerKm != nil) ? totalKm! * costPerKm! : nil
        let profit = (fare != nil && totalCost != nil) ? fare! - totalCost! : nil

        return FinancialResult(
            input: offer,
            totalDistanceKm: totalKm,
            totalTimeMin: totalMin,
            grossRevenue: fare,
            revenuePerKm: Self.div(fare, totalKm),
            revenuePerHour: Self.perHour(fare, totalMin),
            fuelCost: fuelCost,
            fuelIncludedInOperational: fuelIncluded,
            operationalCost: operationalCost,
            totalCost: totalCost,
            costPerKm: costPerKm,
            revenueAfterFuel: (fare != nil && fuelCost != nil) ? fare! - fuelCost! : nil,
            operatingProfit: profit,
            profitPerKm: Self.div(profit, totalKm),
            profitPerHour: Self.perHour(profit, totalMin),
            operatingMargin: Self.div(profit, fare),
            productiveDistanceShare: (tripKm != nil && totalKm != nil && totalKm! > 0) ? tripKm! / totalKm! : nil,
            unproductiveDistanceKm: pickupKm,
            unproductiveTimeMin: pickupMin,
            missingInputs: missing,
            missingCosts: missingCosts,
            issues: issues
        )
    }

    static func div(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b, b > 0 else { return nil }
        let r = a / b
        return r.isFinite ? r : nil
    }

    static func perHour(_ a: Double?, _ minutes: Double?) -> Double? {
        guard let a, let minutes, minutes > 0 else { return nil }
        let r = a / (minutes / 60)
        return r.isFinite ? r : nil
    }
}

/// Valor mínimo que a corrida deveria pagar para cumprir todas as metas.
public struct FareTarget: Equatable, Sendable {
    public var minimumFare: Double
    public var bindingGoal: String
    public var breakEven: Double?
    /// Valor oferecido − mínimo (positivo = acima das metas).
    public var gap: Double?
}

public enum FareAdvisor {
    public static func target(_ r: FinancialResult, goals: Goals) -> FareTarget? {
        guard let km = r.totalDistanceKm, km > 0 else { return nil }
        let hours = r.totalTimeMin.flatMap { $0 > 0 ? $0 / 60 : nil }
        let cost = r.costPerKm.map { $0 * km }
        var c: [(Double, String)] = [(goals.minRevenuePerKm * km, "valor por km")]
        if let hours { c.append((goals.minRevenuePerHour * hours, "valor por hora")) }
        if let cost {
            c.append((cost + goals.minProfitPerKm * km, "lucro por km"))
            if let hours { c.append((cost + goals.minProfitPerHour * hours, "lucro por hora")) }
            if let m = goals.minProfitPerTrip { c.append((cost + m, "lucro mínimo por corrida")) }
        }
        guard let best = c.filter({ $0.0.isFinite && $0.0 > 0 }).max(by: { $0.0 < $1.0 }) else { return nil }
        return FareTarget(minimumFare: best.0, bindingGoal: best.1, breakEven: cost, gap: r.grossRevenue.map { $0 - best.0 })
    }
}
