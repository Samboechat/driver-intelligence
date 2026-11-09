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
    var fastRecognition: Bool = false

    /// Print de cada chamado (álbum "Driver Intelligence").
    var saveScreenshots: Bool = true
    /// Miniatura do print dentro da notificação.
    var attachScreenshot: Bool = true
    /// Detectar aceite/recusa e acompanhar a corrida.
    var autoTrack: Bool = true
    /// Registrar sozinho a corrida concluída, com tempos reais.
    var autoRegisterTrips: Bool = true
    /// Avisar o resumo ao fim de cada corrida.
    var notifyTripSummary: Bool = true

    init() {}

    // Decodificação tolerante: campos novos entram com o padrão sem apagar os ajustes antigos.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DriverSettings()
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        func o<T: Decodable>(_ k: CodingKeys, _ def: T?) -> T? { c.contains(k) ? (try? c.decodeIfPresent(T.self, forKey: k)) ?? nil : def }
        consumptionKmPerLiter = o(.consumptionKmPerLiter, d.consumptionKmPerLiter)
        fuelPrice = o(.fuelPrice, d.fuelPrice)
        otherCostPerKm = o(.otherCostPerKm, d.otherCostPerKm)
        operationalCostOverride = o(.operationalCostOverride, d.operationalCostOverride)
        overrideIncludesFuel = v(.overrideIncludesFuel, d.overrideIncludesFuel)
        dailyGoal = o(.dailyGoal, d.dailyGoal)
        minRevenuePerKm = v(.minRevenuePerKm, d.minRevenuePerKm)
        minRevenuePerHour = v(.minRevenuePerHour, d.minRevenuePerHour)
        minProfitPerKm = v(.minProfitPerKm, d.minProfitPerKm)
        minProfitPerHour = v(.minProfitPerHour, d.minProfitPerHour)
        minProfitPerTrip = o(.minProfitPerTrip, d.minProfitPerTrip)
        maxPickupMinutes = v(.maxPickupMinutes, d.maxPickupMinutes)
        useRealisticTime = v(.useRealisticTime, d.useRealisticTime)
        pickupTimeFactor = v(.pickupTimeFactor, d.pickupTimeFactor)
        tripTimeFactor = v(.tripTimeFactor, d.tripTimeFactor)
        notifySound = v(.notifySound, d.notifySound)
        notifyIncomplete = v(.notifyIncomplete, d.notifyIncomplete)
        fastRecognition = v(.fastRecognition, d.fastRecognition)
        saveScreenshots = v(.saveScreenshots, d.saveScreenshots)
        attachScreenshot = v(.attachScreenshot, d.attachScreenshot)
        autoTrack = v(.autoTrack, d.autoTrack)
        autoRegisterTrips = v(.autoRegisterTrips, d.autoRegisterTrips)
        notifyTripSummary = v(.notifyTripSummary, d.notifyTripSummary)
    }

    var costs: CostProfile {
        CostProfile(
            consumptionKmPerUnit: consumptionKmPerLiter,
            energyPricePerUnit: fuelPrice,
            otherCostsPerKm: otherCostPerKm,
            operationalCostPerKmOverride: operationalCostOverride,
            operationalCostIncludesFuel: overrideIncludesFuel
        )
    }

    /// Contexto de análise. Com corridas medidas, usa os fatores aprendidos no lugar do padrão.
    func context(factors: TimeFactors? = nil) -> AnalysisContext {
        AnalysisContext(
            costs: costs,
            goals: goals,
            pickupTimeFactor: factors?.pickup ?? pickupTimeFactor,
            tripTimeFactor: factors?.trip ?? tripTimeFactor,
            useRealisticTime: useRealisticTime
        )
    }

    var context: AnalysisContext { context(factors: SharedStore.currentFactors(self)) }

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

/// Oferta analisada (chamado), guardada para o histórico e a galeria.
struct OfferRecord: Codable, Identifiable, Equatable {
    var id: String
    var fingerprint: String?
    var date: Date
    var fare: Double?
    var revenuePerKm: Double?
    var revenuePerHour: Double?
    var profit: Double?
    var totalKm: Double?
    var totalMin: Double?
    var realisticMin: Double?
    var pickupKm: Double?
    var classification: String
    var category: String?
    var origin: String?
    var destination: String?
    var headline: String
    var confidence: Double
    var outcome: String?
    var screenshot: String?

    var cls: Classification { Classification(rawValue: classification) ?? .gray }
    var result: OfferOutcome? { outcome.flatMap(OfferOutcome.init(rawValue:)) }

    init(_ a: OfferAnalysis, date: Date = Date(), screenshot: String? = nil) {
        fingerprint = a.fingerprint
        id = (a.fingerprint ?? UUID().uuidString) + "@" + String(Int(date.timeIntervalSince1970))
        self.date = date
        fare = a.offer.fare
        revenuePerKm = a.financial.revenuePerKm
        revenuePerHour = a.basis.revenuePerHour
        profit = a.financial.operatingProfit
        totalKm = a.financial.totalDistanceKm
        totalMin = a.financial.totalTimeMin
        realisticMin = a.realistic?.totalTimeMin
        pickupKm = a.offer.pickupDistanceKm
        classification = a.decision.classification.rawValue
        category = a.offer.category
        origin = a.offer.origin
        destination = a.offer.destination
        headline = a.decision.headline
        confidence = a.confidence
        self.screenshot = screenshot
    }
}

/// Corrida realizada (aceita e concluída), com os tempos reais medidos.
struct TripRecord: Codable, Identifiable, Equatable {
    var id: String
    var acceptedAt: Date
    var completedAt: Date
    var fare: Double?
    var category: String?
    var totalKm: Double?
    var offeredMin: Double?
    var predictedMin: Double?
    var actualPickupMin: Double?
    var actualTripMin: Double?
    var totalMin: Double?
    var cost: Double?
    var profit: Double?
    var revenuePerHour: Double?
    var classification: String
    var manual: Bool
    var screenshot: String?

    var cls: Classification { Classification(rawValue: classification) ?? .gray }
}

/// Estado da extensão, para o app mostrar se a leitura está funcionando.
struct BroadcastStatus: Codable, Equatable {
    var running = false
    var startedAt: Date?
    var lastFrameAt: Date?
    var framesAnalyzed = 0
    var offersNotified = 0
    var screenshotsSaved = 0
    var lastOcrMs: Int?
    var lastError: String?
    var screen: String?
    var tripPhase: String?
    var tripAcceptedAt: Date?
    var tripFare: Double?
    var tripPredictedMin: Double?
}

/// Pedido do app para a extensão (ex.: botão "Aceitei" na notificação).
struct AppCommand: Codable, Equatable {
    enum Action: String, Codable { case accept, finish, reset }
    var id = UUID().uuidString
    var action: Action
    var fingerprint: String?
    var at = Date()
}

/**
 * Armazenamento compartilhado via App Group.
 * Instaladores (AltStore/SideStore/ESign) podem renomear o grupo: ele é descoberto em tempo de execução
 * (`ALTAppGroups` no Info.plist, ou o grupo padrão se o sistema liberar o contêiner).
 */
enum SharedStore {
    static let defaultGroup = "group.com.samboechat.driverintelligence"

    static let groupId: String? = {
        var candidates: [String] = []
        for b in [Bundle.main, containingAppBundle].compactMap({ $0 }) {
            if let groups = b.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] { candidates += groups }
        }
        candidates.append(defaultGroup)
        return candidates.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
    }()

    private static var containingAppBundle: Bundle? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "appex" else { return nil }
        return Bundle(url: url.deletingLastPathComponent().deletingLastPathComponent())
    }

    static var isShared: Bool { groupId != nil }

    private static var defaults: UserDefaults {
        groupId.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// Pasta dos prints (no contêiner compartilhado; sem ele, na pasta do próprio processo).
    static var screenshotsDir: URL {
        let base = groupId.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Capturas", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func screenshotURL(_ name: String) -> URL { screenshotsDir.appendingPathComponent(name) }

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
        set { save("history", Array(newValue.prefix(500))) }
    }

    static var trips: [TripRecord] {
        get { load("trips", [TripRecord].self) ?? [] }
        set { save("trips", Array(newValue.prefix(2000))) }
    }

    static var samples: [TimingSample] {
        get { load("samples", [TimingSample].self) ?? [] }
        set { save("samples", Array(newValue.suffix(200))) }
    }

    static var command: AppCommand? {
        get { load("command", AppCommand.self) }
        set { if let newValue { save("command", newValue) } else { defaults.removeObject(forKey: "command") } }
    }

    /// Prints já copiados para o álbum de Fotos.
    static var savedToPhotos: Set<String> {
        get { Set(load("savedToPhotos", [String].self) ?? []) }
        set { save("savedToPhotos", Array(newValue)) }
    }

    /// Identificador local do álbum "Driver Intelligence" (criado pelo app).
    static var albumId: String? {
        get { defaults.string(forKey: "albumId") }
        set { defaults.set(newValue, forKey: "albumId") }
    }

    static func append(_ r: OfferRecord) {
        var h = history
        h.removeAll { $0.fingerprint != nil && $0.fingerprint == r.fingerprint && abs($0.date.timeIntervalSince(r.date)) < 120 }
        h.insert(r, at: 0)
        history = h
        pruneScreenshots(keep: Set(h.compactMap(\.screenshot) + trips.compactMap(\.screenshot)))
    }

    static func setOutcome(fingerprint: String?, _ outcome: OfferOutcome) {
        guard let fingerprint else { return }
        var h = history
        if let i = h.firstIndex(where: { $0.fingerprint == fingerprint }) {
            h[i].outcome = outcome.rawValue
            history = h
        }
    }

    static func screenshotFor(fingerprint: String?) -> String? {
        guard let fingerprint else { return nil }
        return history.first { $0.fingerprint == fingerprint }?.screenshot
    }

    /// Fatores de tempo: aprendidos com as corridas medidas, ou o padrão do motorista.
    static func currentFactors(_ s: DriverSettings, hour: Int = Calendar.current.component(.hour, from: Date())) -> TimeFactors {
        TimeCalibration(samples: samples, defaultPickup: s.pickupTimeFactor, defaultTrip: s.tripTimeFactor).factors(hour: hour)
    }

    /// Mantém no máximo os prints ainda referenciados (e um teto de arquivos).
    private static func pruneScreenshots(keep: Set<String>) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: screenshotsDir, includingPropertiesForKeys: [.creationDateKey]) else { return }
        guard files.count > 320 else { return }
        for f in files where !keep.contains(f.lastPathComponent) { try? fm.removeItem(at: f) }
    }

    /// CSV (separador ";", compatível com Excel em português).
    static func csv() -> String {
        func n(_ v: Double?, _ d: Int = 2) -> String { v.map { Br.decimal($0, d).replacingOccurrences(of: ".", with: "") } ?? "" }
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy HH:mm"
        var out = "\u{FEFF}tipo;data;valor;categoria;km;min_app;min_real;rs_km;rs_hora;lucro;classificacao;resultado\r\n"
        for t in trips {
            out += "corrida;\(df.string(from: t.acceptedAt));\(n(t.fare));\(t.category ?? "");\(n(t.totalKm, 1));\(n(t.offeredMin, 0));\(n(t.totalMin, 0));\(n(t.fare.flatMap { f in t.totalKm.map { f / $0 } }));\(n(t.revenuePerHour));\(n(t.profit));\(t.cls.label);realizada\r\n"
        }
        for o in history {
            out += "oferta;\(df.string(from: o.date));\(n(o.fare));\(o.category ?? "");\(n(o.totalKm, 1));\(n(o.totalMin, 0));\(n(o.realisticMin, 0));\(n(o.revenuePerKm));\(n(o.revenuePerHour));\(n(o.profit));\(o.cls.label);\(o.result?.label ?? "")\r\n"
        }
        return out
    }
}
