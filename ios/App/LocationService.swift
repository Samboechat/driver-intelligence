import CoreLocation
import DriverCore

/**
 * GPS do turno. Faz duas coisas:
 *  1. mede os km que o carro rodou de verdade (hodômetro por GPS, no núcleo);
 *  2. mantém o app acordado em segundo plano enquanto você usa o Uber, para a Dynamic Island
 *     receber cada chamado na hora (app suspenso não consegue atualizar a ilha).
 * Nada sai do aparelho.
 */
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var isTracking = false
    /// Km do turno aberto.
    @Published private(set) var shiftKm: Double = 0
    @Published private(set) var lastFix: Date?
    @Published private(set) var lastError: String?
    private(set) var lastLocation: CLLocation?

    private let manager: CLLocationManager
    private var tracker: OdometerTracker
    private var trackedShift: String?
    private var lastSave = Date.distantPast

    var authorized: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    var canAsk: Bool { authorization == .notDetermined }
    /// Quando o carro andou pela última vez neste turno.
    var lastMoveAt: Date? { tracker.lastMoveAt.map { Date(timeIntervalSince1970: $0) } }

    private static var backgroundAllowed: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("location") == true
    }

    override private init() {
        let m = CLLocationManager()
        manager = m
        authorization = m.authorizationStatus
        tracker = SharedStore.odometer ?? OdometerTracker()
        trackedShift = SharedStore.odometerShift
        super.init()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyBest
        m.distanceFilter = 8
        m.activityType = .automotiveNavigation
        m.pausesLocationUpdatesAutomatically = false
        if trackedShift != nil { shiftKm = tracker.km }
    }

    func requestPermission() {
        if canAsk { manager.requestWhenInUseAuthorization() }
    }

    /// Liga ou desliga o GPS conforme o momento: ligado com a leitura ativa ou com um turno aberto.
    func sync(reading: Bool) {
        let open = SharedStore.shifts.first(where: \.isOpen)
        if let open, open.id != trackedShift {
            // Turno novo: zera o hodômetro.
            tracker = OdometerTracker()
            trackedShift = open.id
            shiftKm = 0
            persist(force: true)
        } else if open == nil, trackedShift != nil {
            trackedShift = nil
            SharedStore.odometerShift = nil
            SharedStore.odometer = nil
            shiftKm = 0
        }
        let wanted = SharedStore.settings.gpsTracking && authorized && (reading || open != nil)
        if wanted && !isTracking { start() } else if !wanted && isTracking { stop() }
    }

    private func start() {
        if Self.backgroundAllowed {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
        manager.startUpdatingLocation()
        isTracking = true
        lastError = nil
    }

    private func stop() {
        manager.stopUpdatingLocation()
        if Self.backgroundAllowed { manager.allowsBackgroundLocationUpdates = false }
        isTracking = false
        persist(force: true)
    }

    /// Grava os km no turno aberto (a cada 10 s, ou na hora com `force`).
    func persist(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastSave) >= 10 else { return }
        lastSave = Date()
        guard let id = trackedShift else { return }
        SharedStore.odometer = tracker
        SharedStore.odometerShift = id
        let km = tracker.km
        SharedStore.updateShifts { shifts in
            if let i = shifts.firstIndex(where: { $0.id == id && $0.isOpen }) { shifts[i].gpsKm = km }
        }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if !authorized, isTracking { stop() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations {
            // Posição guardada de antes (o iOS entrega a última conhecida ao ligar): não entra na conta.
            guard abs(loc.timestamp.timeIntervalSinceNow) < 20 else { continue }
            lastLocation = loc
            guard trackedShift != nil else { continue }
            tracker.add(GeoPoint(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude,
                                 accuracy: loc.horizontalAccuracy, time: loc.timestamp.timeIntervalSince1970))
        }
        lastFix = lastLocation?.timestamp
        if trackedShift != nil, abs(tracker.km - shiftKm) >= 0.01 { shiftKm = tracker.km }
        persist()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // "Posição ainda desconhecida" é passageiro; o resto vai para o diagnóstico.
        if (error as? CLError)?.code == .locationUnknown { return }
        lastError = error.localizedDescription
    }
}
