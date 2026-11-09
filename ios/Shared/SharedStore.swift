import Foundation
import DriverCore

/// Ajustes do motorista no iPhone (compartilhados entre o app e a extensão de transmissão).
struct DriverSettings: Codable, Equatable {
    var consumptionKmPerLiter: Double? = 11
    var fuelPrice: Double? = 6.20
    var otherCostPerKm: Double? = nil
    var operationalCostOverride: Double? = nil
    var overrideIncludesFuel: Bool = false

    var dailyGoal: Double? = nil
    var minRevenuePerKm: Double = 2.0
    var minRevenuePerHour: Double = 40
    var minProfitPerKm: Double = 1.2
    var minProfitPerHour: Double = 30
    var minProfitPerTrip: Double? = nil
    var maxPickupMinutes: Double = 10

    var useRealisticTime: Bool = true
    var pickupTimeFactor: Double = 1.35
    var tripTimeFactor: Double = 1.15

    var notifySound: Bool = true
    var notifyIncomplete: Bool = false
    /// Leitura rápida (menos memória/bateria, um pouco menos precisa).
    var fastRecognition: Bool = false

    var context: AnalysisContext {
        AnalysisContext(
            costs: CostProfile(
                consumptionKmPerUnit: consumptionKmPerLiter,
                energyPricePerUnit: fuelPrice,
                otherCostsPerKm: otherCostPerKm,
                operationalCostPerKmOverride: operationalCostOverride,
                operationalCostIncludesFuel: overrideIncludesFuel
            ),
            goals: goals,
            pickupTimeFactor: pickupTimeFactor,
            tripTimeFactor: tripTimeFactor,
            useRealisticTime: useRealisticTime
        )
    }

    var goals: Goals {
        Goals(
            dailyRevenue: dailyGoal,
            minRevenuePerKm: minRevenuePerKm,
            minRevenuePerHour: minRevenuePerHour,
            minProfitPerKm: minProfitPerKm,
            minProfitPerHour: minProfitPerHour,
            minProfitPerTrip: minProfitPerTrip,
            maxPickupMinutes: maxPickupMinutes
        )
    }
}

/// Oferta analisada, guardada para o histórico do app.
struct OfferRecord: Codable, Identifiable, Equatable {
    var id: String
    var date: Date
    var fare: Double?
    var revenuePerKm: Double?
    var revenuePerHour: Double?
    var profit: Double?
    var totalKm: Double?
    var totalMin: Double?
    var realisticMin: Double?
    var classification: String
    var category: String?
    var headline: String
    var confidence: Double

    var cls: Classification { Classification(rawValue: classification) ?? .gray }

    init(_ a: OfferAnalysis, date: Date = Date()) {
        id = (a.fingerprint ?? UUID().uuidString) + "@" + String(Int(date.timeIntervalSince1970))
        self.date = date
        fare = a.offer.fare
        revenuePerKm = a.financial.revenuePerKm
        revenuePerHour = a.basis.revenuePerHour
        profit = a.financial.operatingProfit
        totalKm = a.financial.totalDistanceKm
        totalMin = a.financial.totalTimeMin
        realisticMin = a.realistic?.totalTimeMin
        classification = a.decision.classification.rawValue
        category = a.offer.category
        headline = a.decision.headline
        confidence = a.confidence
    }
}

/// Estado da extensão, para o app mostrar se a leitura está funcionando.
struct BroadcastStatus: Codable, Equatable {
    var running = false
    var startedAt: Date?
    var lastFrameAt: Date?
    var framesAnalyzed = 0
    var offersNotified = 0
    var lastOcrMs: Int?
    var lastError: String?
}

/**
 * Armazenamento compartilhado via App Group.
 * Ferramentas de instalação (AltStore/SideStore) podem renomear o grupo e informam o nome
 * em `ALTAppGroups` no Info.plist — por isso o grupo é descoberto em tempo de execução.
 */
enum SharedStore {
    static let defaultGroup = "group.com.samboechat.driverintelligence"

    static let groupId: String? = {
        var candidates: [String] = []
        let bundles = [Bundle.main, containingAppBundle].compactMap { $0 }
        for b in bundles {
            if let groups = b.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] { candidates += groups }
        }
        candidates.append(defaultGroup)
        return candidates.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
    }()

    /// Na extensão, o bundle do app que a contém (…/App.app/PlugIns/Ext.appex).
    private static var containingAppBundle: Bundle? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "appex" else { return nil }
        return Bundle(url: url.deletingLastPathComponent().deletingLastPathComponent())
    }

    static var isShared: Bool { groupId != nil }

    private static var defaults: UserDefaults {
        groupId.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    private static func load<T: Decodable>(_ key: String, _ type: T.Type) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ key: String, _ value: T) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    static var settings: DriverSettings {
        get { load("settings", DriverSettings.self) ?? DriverSettings() }
        set { save("settings", newValue) }
    }

    static var status: BroadcastStatus {
        get { load("status", BroadcastStatus.self) ?? BroadcastStatus() }
        set { save("status", newValue) }
    }

    static var history: [OfferRecord] {
        get { load("history", [OfferRecord].self) ?? [] }
        set { save("history", Array(newValue.prefix(300))) }
    }

    static func append(_ r: OfferRecord) {
        var h = history
        h.removeAll { $0.id.split(separator: "@").first == r.id.split(separator: "@").first && abs($0.date.timeIntervalSince(r.date)) < 120 }
        h.insert(r, at: 0)
        history = h
    }
}
