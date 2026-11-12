import SwiftUI
import DriverCore

/**
 * Coração do app enquanto ele está aberto ou acordado em segundo plano:
 * busca o que a leitura de tela publicou, abre/fecha o turno automático, liga o GPS e mantém a Dynamic Island em dia.
 */
final class AppSync {
    static let shared = AppSync()

    private var timer: Timer?
    private var ticks = 0
    private var pullStarted = Date.distantPast
    private var pulling = false
    /// Carro parado e leitura desligada por esse tempo: o turno automático é encerrado.
    private let idleToClose: TimeInterval = 20 * 60

    func start() {
        guard timer == nil else { return }
        DarwinSignal.observe()
        NotificationCenter.default.addObserver(forName: DarwinSignal.received, object: nil, queue: .main) { [weak self] _ in
            self?.pull()
        }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    private func tick() {
        ticks += 1
        // Em segundo plano, o aviso da extensão já dispara a busca; o relógio fica como reserva (a cada 6 s).
        if UIApplication.shared.applicationState != .active, ticks % 3 != 0 {
            apply(changed: false)
            return
        }
        pull()
    }

    /// Busca o que a leitura publicou e aplica.
    func pull() {
        CaptureMonitor.shared.refresh()
        if pulling, Date().timeIntervalSince(pullStarted) < 5 { return }
        pulling = true
        pullStarted = Date()
        Bridge.pull { [weak self] changed in
            DispatchQueue.main.async {
                self?.pulling = false
                self?.apply(changed: changed)
            }
        }
    }

    private func apply(changed: Bool) {
        let now = Date()
        let settings = SharedStore.settings
        let status = SharedStore.status
        let reading = ReadingState.current(status: status, capture: CaptureMonitor.shared, now: now)
        let gps = LocationService.shared

        // Turno automático: abre uma vez por gravação.
        if reading == .reading, settings.autoShift, let session = status.startedAt, SharedStore.autoShiftSession != session {
            SharedStore.autoShiftSession = session
            if !SharedStore.shifts.contains(where: \.isOpen) {
                let start = now.timeIntervalSince(session) < 15 * 60 ? session : now
                SharedStore.updateShifts { $0.insert(Shift(start: start, auto: true), at: 0) }
            }
        }

        gps.sync(reading: reading.isOn)

        // Turno automático: fecha com a leitura desligada e o carro parado (só com GPS, que é quem sabe se o carro andou).
        if reading == .off, settings.gpsTracking, gps.authorized,
           let open = SharedStore.shifts.first(where: { $0.isOpen && $0.auto == true }) {
            let lastActive = [gps.lastMoveAt, SharedStore.pulseAt, status.lastFrameAt, open.start].compactMap { $0 }.max() ?? open.start
            if now.timeIntervalSince(lastActive) > idleToClose {
                gps.persist(force: true)
                SharedStore.updateShifts { shifts in
                    if let i = shifts.firstIndex(where: { $0.id == open.id }) { shifts[i].end = lastActive }
                }
                gps.sync(reading: false)
                Notifier.postInfo("Turno encerrado", "Leitura desligada e carro parado há 20 minutos. Veja o resumo no Painel.", id: "shift")
            }
        }

        // Guarda onde o carro estava quando o chamado chegou (para o mapa de chamados).
        if changed, let loc = gps.lastLocation, now.timeIntervalSince(loc.timestamp) < 20 {
            var geo = SharedStore.offerGeo
            var touched = false
            for r in SharedStore.history.prefix(4) where now.timeIntervalSince(r.date) < 45 && geo[r.id] == nil {
                geo[r.id] = [loc.coordinate.latitude, loc.coordinate.longitude]
                touched = true
            }
            if touched {
                if geo.count > 600 {
                    let keep = Set(SharedStore.history.prefix(500).map(\.id))
                    geo = geo.filter { keep.contains($0.key) }
                }
                SharedStore.offerGeo = geo
            }
        }

        if #available(iOS 16.2, *) { LiveIsland.sync(reading: reading, settings: settings, status: status, now: now) }
    }
}

/// Dynamic Island do lado do app: abre com o app na frente e atualiza a cada chamado, mesmo em segundo plano.
@available(iOS 16.2, *)
enum LiveIsland {
    private static var shown: RideActivityAttributes.ContentState?
    private static var refreshed = Date.distantPast

    static func sync(reading: ReadingState, settings: DriverSettings, status: BroadcastStatus, now: Date) {
        guard settings.liveActivity, reading != .off else {
            if LiveActivityController.isRunning { LiveActivityController.end() }
            shown = nil
            return
        }
        // "Ligando" ou sem sinal da leitura: deixa como está.
        guard reading == .reading else { return }
        let state = SharedStore.liveState ?? .searching(offersToday: status.offersNotified)
        let active = UIApplication.shared.applicationState == .active

        guard LiveActivityController.isRunning else {
            // Abrir só é permitido com o app na frente.
            guard active else { return }
            let error = LiveActivityController.start(state)
            if SharedStore.liveError != error { SharedStore.liveError = error }
            shown = state
            refreshed = now
            return
        }
        if state != shown {
            // Chamado novo (não a mesma leitura refeita): abre a ilha por alguns segundos.
            let isNewOffer = state.phase == .offer
                && (shown?.phase != .offer || shown?.fare != state.fare || shown?.perKm != state.perKm)
            LiveActivityController.update(state, expand: settings.islandAlert && isNewOffer && !active)
            shown = state
            refreshed = now
        } else if now.timeIntervalSince(refreshed) > 100 {
            // Renova para a ilha não ser marcada como desatualizada.
            LiveActivityController.update(state)
            refreshed = now
        }
    }
}
