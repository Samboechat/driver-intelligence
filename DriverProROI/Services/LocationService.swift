import CoreLocation
import Foundation

/// Rastreamento contínuo em segundo plano com gestão de bateria por modo.
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum Mode: String {
        /// GPS desligado (sem turno).
        case off
        /// Turno rodando: máxima precisão.
        case active
        /// Veículo estacionado há mais de 3 min: leitura reduzida até detectar movimento.
        case parked
        /// Turno em pausa manual: leitura mínima, só para manter o app vivo.
        case paused

        var title: String {
            switch self {
            case .off: return "GPS desligado"
            case .active: return "GPS em alta precisão"
            case .parked: return "GPS econômico (estacionado)"
            case .paused: return "GPS mínimo (pausa)"
            }
        }
    }

    private let manager = CLLocationManager()
    private let askedAlwaysKey = "location.askedAlways"
    private(set) var mode: Mode = .off

    var onLocations: (@MainActor ([CLLocation]) -> Void)?
    var onAuthorization: (@MainActor (CLAuthorizationStatus) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    /// Pede "Durante o uso" e, em seguida, "Sempre" (necessário para contar km com a tela bloqueada).
    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            if !UserDefaults.standard.bool(forKey: askedAlwaysKey) {
                UserDefaults.standard.set(true, forKey: askedAlwaysKey)
                manager.requestAlwaysAuthorization()
            }
        default:
            break
        }
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
        switch newMode {
        case .off:
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
        case .active:
            start(accuracy: kCLLocationAccuracyBestForNavigation, distanceFilter: 5)
        case .parked:
            start(accuracy: kCLLocationAccuracyHundredMeters, distanceFilter: 20)
        case .paused:
            start(accuracy: kCLLocationAccuracyThreeKilometers, distanceFilter: 1000)
        }
    }

    private func start(accuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance) {
        manager.desiredAccuracy = accuracy
        manager.distanceFilter = distanceFilter
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    // MARK: CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            self.onLocations?(locations)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse, !UserDefaults.standard.bool(forKey: askedAlwaysKey) {
            UserDefaults.standard.set(true, forKey: askedAlwaysKey)
            manager.requestAlwaysAuthorization()
        }
        MainActor.assumeIsolated {
            self.onAuthorization?(status)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Falhas pontuais de GPS (túnel, garagem) são ignoradas: o próximo ponto válido retoma a contagem.
    }
}
