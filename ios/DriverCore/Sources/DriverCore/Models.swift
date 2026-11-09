import Foundation

/// Dados de uma oferta. `nil` = não identificado (nunca presumido).
public struct OfferData: Equatable, Codable, Sendable {
    public var fare: Double?
    public var pickupDistanceKm: Double?
    public var tripDistanceKm: Double?
    public var pickupTimeMin: Double?
    public var tripTimeMin: Double?
    public var category: String?
    public var origin: String?
    public var destination: String?
    public var surgeAmount: Double?
    public var displayedRatePerKm: Double?
    public var passengerRating: Double?

    public init(
        fare: Double? = nil, pickupDistanceKm: Double? = nil, tripDistanceKm: Double? = nil,
        pickupTimeMin: Double? = nil, tripTimeMin: Double? = nil, category: String? = nil,
        origin: String? = nil, destination: String? = nil, surgeAmount: Double? = nil,
        displayedRatePerKm: Double? = nil, passengerRating: Double? = nil
    ) {
        self.fare = fare
        self.pickupDistanceKm = pickupDistanceKm
        self.tripDistanceKm = tripDistanceKm
        self.pickupTimeMin = pickupTimeMin
        self.tripTimeMin = tripTimeMin
        self.category = category
        self.origin = origin
        self.destination = destination
        self.surgeAmount = surgeAmount
        self.displayedRatePerKm = displayedRatePerKm
        self.passengerRating = passengerRating
    }
}

public enum OfferField: String, CaseIterable, Sendable {
    case fare, pickupDistance, tripDistance, pickupTime, tripTime

    public var label: String {
        switch self {
        case .fare: return "valor da corrida"
        case .pickupDistance: return "distância até o embarque"
        case .tripDistance: return "distância da viagem"
        case .pickupTime: return "tempo até o embarque"
        case .tripTime: return "tempo da viagem"
        }
    }

    public static let essential: Set<OfferField> = [.fare, .pickupDistance, .tripDistance]
}

public enum CostComponent: String, CaseIterable, Sendable {
    case fuel, maintenance, tires, oil, depreciation, other

    public var label: String {
        switch self {
        case .fuel: return "Combustível"
        case .maintenance: return "Manutenção"
        case .tires: return "Pneus"
        case .oil: return "Óleo"
        case .depreciation: return "Depreciação"
        case .other: return "Outros custos"
        }
    }
}

/// Custos do veículo. Tudo opcional: dá para começar só com consumo e preço do combustível.
public struct CostProfile: Equatable, Codable, Sendable {
    public var consumptionKmPerUnit: Double?
    public var energyPricePerUnit: Double?
    public var maintenancePerKm: Double?
    public var tiresPerKm: Double?
    public var oilPerKm: Double?
    public var depreciationPerKm: Double?
    public var otherCostsPerKm: Double?
    /// Custo operacional por km informado como valor único (substitui a soma dos itens).
    public var operationalCostPerKmOverride: Double?
    /// O valor único JÁ inclui combustível (evita descontar duas vezes).
    public var operationalCostIncludesFuel: Bool

    public init(
        consumptionKmPerUnit: Double? = nil, energyPricePerUnit: Double? = nil, maintenancePerKm: Double? = nil,
        tiresPerKm: Double? = nil, oilPerKm: Double? = nil, depreciationPerKm: Double? = nil,
        otherCostsPerKm: Double? = nil, operationalCostPerKmOverride: Double? = nil,
        operationalCostIncludesFuel: Bool = false
    ) {
        self.consumptionKmPerUnit = consumptionKmPerUnit
        self.energyPricePerUnit = energyPricePerUnit
        self.maintenancePerKm = maintenancePerKm
        self.tiresPerKm = tiresPerKm
        self.oilPerKm = oilPerKm
        self.depreciationPerKm = depreciationPerKm
        self.otherCostsPerKm = otherCostsPerKm
        self.operationalCostPerKmOverride = operationalCostPerKmOverride
        self.operationalCostIncludesFuel = operationalCostIncludesFuel
    }

    public static let empty = CostProfile()
}

public struct FinancialResult: Equatable, Sendable {
    public var input: OfferData
    public var totalDistanceKm: Double?
    public var totalTimeMin: Double?
    public var grossRevenue: Double?
    public var revenuePerKm: Double?
    public var revenuePerHour: Double?
    public var fuelCost: Double?
    public var fuelIncludedInOperational: Bool
    public var operationalCost: Double?
    public var totalCost: Double?
    public var costPerKm: Double?
    public var revenueAfterFuel: Double?
    public var operatingProfit: Double?
    public var profitPerKm: Double?
    public var profitPerHour: Double?
    public var operatingMargin: Double?
    public var productiveDistanceShare: Double?
    public var unproductiveDistanceKm: Double?
    public var unproductiveTimeMin: Double?
    public var missingInputs: Set<OfferField>
    public var missingCosts: Set<CostComponent>
    public var issues: [String]

    public var hasEssentials: Bool { missingInputs.isDisjoint(with: OfferField.essential) }
    public var isCostEstimatePartial: Bool { !missingCosts.isEmpty }
}

public enum Classification: String, Codable, CaseIterable, Sendable {
    case green, yellow, red, gray

    public var label: String {
        switch self {
        case .green: return "Rentável"
        case .yellow: return "Rentabilidade moderada"
        case .red: return "Abaixo da meta"
        case .gray: return "Dados insuficientes"
        }
    }

    public var shortLabel: String {
        switch self {
        case .green: return "RENTÁVEL"
        case .yellow: return "MODERADA"
        case .red: return "ABAIXO DA META"
        case .gray: return "INCOMPLETO"
        }
    }

    /// Emoji usado nas notificações (cor semântica, legível de relance).
    public var dot: String {
        switch self {
        case .green: return "🟢"
        case .yellow: return "🟡"
        case .red: return "🔴"
        case .gray: return "⚪️"
        }
    }
}

/// Metas do motorista. Valores padrão são ponto de partida, não média de mercado.
public struct Goals: Equatable, Codable, Sendable {
    public var dailyRevenue: Double?
    public var minRevenuePerKm: Double
    public var minRevenuePerHour: Double
    public var minProfitPerKm: Double
    public var minProfitPerHour: Double
    public var minProfitPerTrip: Double?
    public var maxPickupMinutes: Double
    public var maxUnproductiveShare: Double
    public var maxCostShare: Double
    public var maxTotalDistanceKm: Double?

    public init(
        dailyRevenue: Double? = nil, minRevenuePerKm: Double = 2.0, minRevenuePerHour: Double = 40.0,
        minProfitPerKm: Double = 1.2, minProfitPerHour: Double = 30.0, minProfitPerTrip: Double? = nil,
        maxPickupMinutes: Double = 10.0, maxUnproductiveShare: Double = 0.35, maxCostShare: Double = 0.50,
        maxTotalDistanceKm: Double? = nil
    ) {
        self.dailyRevenue = dailyRevenue
        self.minRevenuePerKm = minRevenuePerKm
        self.minRevenuePerHour = minRevenuePerHour
        self.minProfitPerKm = minProfitPerKm
        self.minProfitPerHour = minProfitPerHour
        self.minProfitPerTrip = minProfitPerTrip
        self.maxPickupMinutes = maxPickupMinutes
        self.maxUnproductiveShare = maxUnproductiveShare
        self.maxCostShare = maxCostShare
        self.maxTotalDistanceKm = maxTotalDistanceKm
    }
}

public enum Metric: String, CaseIterable, Sendable {
    case revenuePerKm, profitPerKm, revenuePerHour, profitPerHour, pickupTime, unproductiveDistance, costShare

    public var label: String {
        switch self {
        case .revenuePerKm: return "Valor por km"
        case .profitPerKm: return "Lucro por km"
        case .revenuePerHour: return "Valor por hora"
        case .profitPerHour: return "Lucro por hora"
        case .pickupTime: return "Tempo até o passageiro"
        case .unproductiveDistance: return "Distância de busca"
        case .costShare: return "Peso dos custos"
        }
    }

    public var weakness: String {
        switch self {
        case .revenuePerKm: return "valor por km abaixo da meta"
        case .profitPerKm: return "lucro por km abaixo da meta"
        case .revenuePerHour: return "valor por hora abaixo da meta"
        case .profitPerHour: return "lucro por hora abaixo da meta"
        case .pickupTime: return "tempo de busca elevado"
        case .unproductiveDistance: return "distância de busca elevada"
        case .costShare: return "custo operacional alto em relação ao valor"
        }
    }

    public var strength: String {
        switch self {
        case .revenuePerKm: return "bom valor por km"
        case .profitPerKm: return "bom lucro por km"
        case .revenuePerHour: return "bom valor por hora"
        case .profitPerHour: return "bom lucro por hora"
        case .pickupTime: return "busca rápida"
        case .unproductiveDistance: return "pouca distância improdutiva"
        case .costShare: return "custos baixos em relação ao valor"
        }
    }
}

public struct ScoringWeights: Equatable, Codable, Sendable {
    public var revenuePerKm = 0.25
    public var profitPerKm = 0.20
    public var revenuePerHour = 0.20
    public var profitPerHour = 0.15
    public var pickupTime = 0.10
    public var unproductiveDistance = 0.05
    public var costShare = 0.05

    public init() {}

    public func weight(_ m: Metric) -> Double {
        switch m {
        case .revenuePerKm: return revenuePerKm
        case .profitPerKm: return profitPerKm
        case .revenuePerHour: return revenuePerHour
        case .profitPerHour: return profitPerHour
        case .pickupTime: return pickupTime
        case .unproductiveDistance: return unproductiveDistance
        case .costShare: return costShare
        }
    }
}

public struct ScoringConfig: Equatable, Codable, Sendable {
    public var weights = ScoringWeights()
    public var greenThreshold = 0.70
    public var yellowThreshold = 0.45
    public var minRecognitionConfidence = 0.60
    public init() {}
}

public struct MetricScore: Equatable, Sendable {
    public var metric: Metric
    public var value: Double
    public var target: Double
    public var score: Double
    public var weight: Double
    public var meetsTarget: Bool { score >= 0.7 - 1e-9 }
}

public struct Decision: Equatable, Sendable {
    public var classification: Classification
    public var score: Double?
    public var headline: String
    public var reasons: [String]
    public var metricScores: [MetricScore]
    public var isPartial: Bool
}
