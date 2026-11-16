import CoreLocation
import Foundation
import Observation
import SwiftData
import WidgetKit

/// Controla o turno em tempo real: cronômetro líquido, pausas, telemetria GPS,
/// classificação de tempo, alertas, Live Activity e widgets.
@MainActor
@Observable
final class ShiftManager {
    static let shared = ShiftManager()

    private enum Tuning {
        /// Precisão horizontal máxima aceita (m).
        static let maxAccuracy = 20.0
        /// Velocidade mínima para contar deslocamento (m/s ≈ 2,9 km/h) — evita drift no semáforo.
        static let minSpeed = 0.8
        static let minStep = 2.0
        /// Saltos acima disso (m/s) são descartados.
        static let maxSpeed = 70.0
        /// Intervalo máximo entre pontos para contar como "dirigindo" (s).
        static let maxGap = 15.0
        /// Tempo parado até entrar no modo econômico (s).
        static let parkedAfter = 180.0
        static let routeStep = 25.0
    }

    private struct ZoneCache {
        let id: UUID
        let name: String
        let location: CLLocation
        let radius: Double
    }

    // MARK: Estado observável

    private(set) var shift: Shift?
    private(set) var liveKm: Double = 0
    private(set) var drivingSeconds: Double = 0
    private(set) var speedKmh: Double = 0
    private(set) var accuracy: Double = -1
    private(set) var gpsMode: LocationService.Mode = .off
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var entries: [LiveEntry] = []
    private(set) var lastCoordinate: CLLocationCoordinate2D?
    /// Dia cujo resumo deve ser aberto (definido ao encerrar o turno).
    var summaryDay: DayRef?

    // MARK: Estado interno

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private let location = LocationService()
    @ObservationIgnored private var route: [RoutePoint] = []
    @ObservationIgnored private var routeDirty = false
    @ObservationIgnored private var pauses: [PauseRecord] = []
    @ObservationIgnored private var lastLocation: CLLocation?
    @ObservationIgnored private var lastRouteLocation: CLLocation?
    @ObservationIgnored private var parkedAnchor: CLLocation?
    @ObservationIgnored private var lastMovementAt = Date()
    @ObservationIgnored private var lastPersistAt = Date.distantPast
    @ObservationIgnored private var lastBroadcastAt = Date.distantPast
    @ObservationIgnored private var lastWidgetReloadAt = Date.distantPast
    @ObservationIgnored private var lastHourlyAlertAt = Date.distantPast
    @ObservationIgnored private var insideZones: Set<UUID> = []
    @ObservationIgnored private var zones: [ZoneCache] = []
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var calibration = 1.0
    @ObservationIgnored private var minPerHour = 55.0
    @ObservationIgnored private var hourlyAlertEnabled = true
    @ObservationIgnored private var fatigueAlertEnabled = true
    @ObservationIgnored private var zoneAlertEnabled = true

    private init() {
        authorization = location.authorizationStatus
        location.onLocations = { [weak self] locations in
            self?.process(locations)
        }
        location.onAuthorization = { [weak self] status in
            self?.authorization = status
        }
    }

    // MARK: Leitura

    var status: ShiftStatus? { shift?.status }
    var isRunning: Bool { shift?.status == .running }
    var isPaused: Bool { shift?.status == .paused }
    var hasShift: Bool { shift != nil }
    var entriesTotal: Double { entries.reduce(0) { $0 + $1.amount } }

    func activeSeconds(at date: Date = Date()) -> Double {
        shift?.currentActiveSeconds(at: date) ?? 0
    }

    func pausedSeconds(at date: Date = Date()) -> Double {
        shift?.currentPausedSeconds(at: date) ?? 0
    }

    /// Tempo parado ocioso: turno ativo, veículo sem se mover.
    func idleSeconds(at date: Date = Date()) -> Double {
        max(0, activeSeconds(at: date) - drivingSeconds)
    }

    var needsAlwaysAuthorization: Bool {
        authorization == .authorizedWhenInUse
    }

    var locationDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    // MARK: Configuração

    func configure(context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        ShiftCommandCenter.shared.handler = { [weak self] command in
            self?.execute(command) ?? "DriverPro ROI indisponível."
        }
        reloadConfig()
        restoreOpenShift()
        consumePendingCommand()
        broadcast(force: true)
    }

    /// Recarrega ajustes e zonas (chamado ao iniciar e quando o usuário altera configurações).
    func reloadConfig() {
        guard let context else { return }
        let settings = Store.settings(context)
        let factor = settings.gpsCalibration
        calibration = factor > 0.5 && factor < 1.5 ? factor : 1
        minPerHour = settings.minPerHour
        hourlyAlertEnabled = settings.hourlyAlertEnabled
        fatigueAlertEnabled = settings.fatigueAlertEnabled
        zoneAlertEnabled = settings.zoneAlertEnabled
        let stored = (try? context.fetch(FetchDescriptor<LowLiquidityZone>())) ?? []
        zones = stored.filter { $0.isEnabled }.map {
            ZoneCache(id: $0.id, name: $0.name, location: CLLocation(latitude: $0.lat, longitude: $0.lon), radius: $0.radius)
        }
    }

    func appBecameActive() {
        authorization = location.authorizationStatus
        consumePendingCommand()
        if let shift {
            LiveActivityService.shared.startIfNeeded(startedAt: shift.startedAt, state: makeContentState(now: Date()))
        }
        broadcast(force: true)
    }

    func requestLocationAccess() {
        location.requestAuthorization()
    }

    private func restoreOpenShift() {
        guard let context else { return }
        var descriptor = FetchDescriptor<Shift>(sortBy: [SortDescriptor(\Shift.startedAt, order: .reverse)])
        descriptor.fetchLimit = 10
        let recent = (try? context.fetch(descriptor)) ?? []
        guard let open = recent.first(where: { $0.status != .finished }) else { return }
        shift = open
        route = open.route
        pauses = open.pauses
        entries = open.entries
        liveKm = open.gpsKm
        drivingSeconds = open.drivingSeconds
        lastMovementAt = Date()
        if open.status == .running {
            setGPS(.active)
            scheduleFatigue()
        } else {
            setGPS(.paused)
        }
        startTicker()
    }

    private func consumePendingCommand() {
        if let command = PendingCommandStore.pop() {
            execute(command)
        }
    }

    // MARK: Comandos (botões, widgets, Siri/Atalhos)

    @discardableResult
    func execute(_ command: ShiftCommand) -> String {
        switch command {
        case .start:
            if shift != nil { return "Já existe um turno em andamento." }
            start()
            return "Turno iniciado. Boas corridas!"
        case .pause:
            guard isRunning else { return "Não há turno rodando para pausar." }
            pause()
            return "Turno pausado."
        case .resume:
            guard isPaused else { return "Não há turno pausado para retomar." }
            resume()
            return "Turno retomado."
        case .toggle:
            if shift == nil {
                start()
                return "Turno iniciado."
            }
            if isRunning {
                pause()
                return "Turno pausado."
            }
            resume()
            return "Turno retomado."
        case .end:
            guard shift != nil else { return "Não há turno aberto." }
            end()
            return "Turno encerrado. Abra o DriverPro ROI para lançar os ganhos do dia."
        }
    }

    func start() {
        guard shift == nil, let context else { return }
        let now = Date()
        let created = Shift(startedAt: now)
        context.insert(created)
        shift = created
        route = []
        routeDirty = false
        pauses = []
        entries = []
        liveKm = 0
        drivingSeconds = 0
        speedKmh = 0
        lastLocation = nil
        lastRouteLocation = nil
        parkedAnchor = nil
        lastMovementAt = now
        lastHourlyAlertAt = now
        insideZones = []
        reloadConfig()
        location.requestAuthorization()
        NotificationService.shared.requestAuthorization()
        setGPS(.active)
        startTicker()
        scheduleFatigue()
        save()
        LiveActivityService.shared.startIfNeeded(startedAt: now, state: makeContentState(now: now))
        broadcast(force: true)
    }

    func pause() {
        guard let shift, shift.status == .running else { return }
        let now = Date()
        if let resume = shift.lastResumeAt {
            shift.activeSeconds += max(0, now.timeIntervalSince(resume))
        }
        shift.lastResumeAt = nil
        shift.pauseStartedAt = now
        shift.status = .paused
        pauses.append(PauseRecord(start: now, end: nil, lat: lastCoordinate?.latitude, lon: lastCoordinate?.longitude))
        speedKmh = 0
        setGPS(.paused)
        NotificationService.shared.cancelFatigue()
        persist(force: true)
        broadcast(force: true)
    }

    func resume() {
        guard let shift, shift.status == .paused else { return }
        let now = Date()
        if let start = shift.pauseStartedAt {
            shift.pausedSeconds += max(0, now.timeIntervalSince(start))
        }
        closeOpenPause(at: now)
        shift.pauseStartedAt = nil
        shift.lastResumeAt = now
        shift.status = .running
        // Não conta o deslocamento feito durante a pausa.
        lastLocation = nil
        parkedAnchor = nil
        lastMovementAt = now
        reloadConfig()
        setGPS(.active)
        scheduleFatigue()
        persist(force: true)
        broadcast(force: true)
    }

    func end() {
        guard let shift, let context else { return }
        let now = Date()
        if shift.status == .running, let resume = shift.lastResumeAt {
            shift.activeSeconds += max(0, now.timeIntervalSince(resume))
        } else if shift.status == .paused, let start = shift.pauseStartedAt {
            shift.pausedSeconds += max(0, now.timeIntervalSince(start))
            closeOpenPause(at: now)
        }
        shift.lastResumeAt = nil
        shift.pauseStartedAt = nil
        shift.endedAt = now
        shift.status = .finished
        shift.gpsKm = liveKm
        shift.drivingSeconds = min(drivingSeconds, shift.activeSeconds)
        if let coordinate = lastCoordinate {
            shift.endLat = coordinate.latitude
            shift.endLon = coordinate.longitude
        }
        shift.route = route
        shift.pauses = pauses
        shift.entries = entries

        let day = SummaryBuilder.merge(shift, into: context)
        try? context.save()

        setGPS(.off)
        stopTicker()
        NotificationService.shared.cancelFatigue()
        var finalState = makeContentState(now: now)
        finalState.isPaused = true
        LiveActivityService.shared.end(finalState)

        self.shift = nil
        route = []
        pauses = []
        entries = []
        liveKm = 0
        drivingSeconds = 0
        speedKmh = 0
        lastLocation = nil
        broadcast(force: true)
        summaryDay = DayRef(day: day)
    }

    private func closeOpenPause(at date: Date) {
        if let index = pauses.lastIndex(where: { $0.end == nil }) {
            pauses[index].end = date
        }
    }

    // MARK: Corridas lançadas durante o turno

    func addEntry(_ category: RideCategory, amount: Double) {
        guard let shift, amount > 0 else { return }
        entries.append(LiveEntry(date: Date(), category: category.rawValue, amount: amount))
        shift.entries = entries
        save()
        broadcast(force: true)
    }

    func removeLastEntry() {
        guard let shift, !entries.isEmpty else { return }
        entries.removeLast()
        shift.entries = entries
        save()
        broadcast(force: true)
    }

    // MARK: Telemetria GPS

    private func setGPS(_ mode: LocationService.Mode) {
        location.setMode(mode)
        gpsMode = mode
    }

    private func process(_ locations: [CLLocation]) {
        for item in locations {
            handle(item)
        }
    }

    private func handle(_ location: CLLocation) {
        accuracy = location.horizontalAccuracy
        guard location.horizontalAccuracy >= 0 else { return }
        guard abs(location.timestamp.timeIntervalSinceNow) < 20 else { return }
        if location.horizontalAccuracy <= 100 {
            lastCoordinate = location.coordinate
        }
        guard let shift, shift.status == .running else { return }

        if gpsMode == .parked {
            handleParked(location)
            return
        }

        // Filtro de precisão: ignora leituras com erro acima de 20 m.
        guard location.horizontalAccuracy <= Tuning.maxAccuracy else { return }
        if shift.startLat == nil {
            shift.startLat = location.coordinate.latitude
            shift.startLon = location.coordinate.longitude
        }
        defer { lastLocation = location }

        guard let previous = lastLocation else {
            appendRoute(location, speed: max(0, location.speed), force: true)
            checkZones(location)
            return
        }
        let elapsed = location.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else { return }
        let distance = location.distance(from: previous)
        let speed = location.speed >= 0 ? location.speed : distance / elapsed
        speedKmh = max(0, speed * 3.6)

        // Filtro de velocidade mínima: parado no semáforo não soma "drift" de GPS.
        if speed >= Tuning.minSpeed && distance >= Tuning.minStep && distance / elapsed <= Tuning.maxSpeed {
            liveKm += distance / 1000 * calibration
            if elapsed <= Tuning.maxGap {
                drivingSeconds += elapsed
            }
            lastMovementAt = Date()
            appendRoute(location, speed: speed, force: false)
        }
        checkZones(location)
        persist(force: false)
    }

    /// Modo econômico: só observa se o carro voltou a andar.
    private func handleParked(_ location: CLLocation) {
        guard let anchor = parkedAnchor else {
            parkedAnchor = location
            return
        }
        let moved = location.distance(from: anchor)
        let threshold = max(40, location.horizontalAccuracy * 1.5)
        guard location.speed >= 2 || moved > threshold else { return }
        if location.horizontalAccuracy <= 65 && moved < 1000 {
            liveKm += moved / 1000 * calibration
        }
        parkedAnchor = nil
        lastLocation = nil
        lastMovementAt = Date()
        setGPS(.active)
    }

    private func appendRoute(_ location: CLLocation, speed: Double, force: Bool) {
        if !force, let last = lastRouteLocation, location.distance(from: last) < Tuning.routeStep {
            return
        }
        lastRouteLocation = location
        route.append(RoutePoint(lat: location.coordinate.latitude,
                                lon: location.coordinate.longitude,
                                t: location.timestamp,
                                speed: max(0, speed)))
        routeDirty = true
    }

    private func checkZones(_ location: CLLocation) {
        guard zoneAlertEnabled else { return }
        for zone in zones {
            let distance = location.distance(from: zone.location)
            if distance <= zone.radius {
                if !insideZones.contains(zone.id) {
                    insideZones.insert(zone.id)
                    NotificationService.shared.notify(
                        id: "zone.\(zone.id.uuidString)",
                        title: "Zona de baixa liquidez",
                        body: "Você entrou em \(zone.name). Histórico ruim de retorno vazio — avalie antes de aceitar corridas para dentro."
                    )
                }
            } else if distance > zone.radius * 1.25 {
                insideZones.remove(zone.id)
            }
        }
    }

    // MARK: Relógio interno

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let shift else {
            stopTicker()
            return
        }
        let now = Date()
        if shift.status == .running {
            // Gestão de bateria: estacionado há mais de 3 min → GPS econômico.
            if gpsMode == .active, now.timeIntervalSince(lastMovementAt) > Tuning.parkedAfter {
                parkedAnchor = lastLocation
                speedKmh = 0
                setGPS(.parked)
            }
            checkHourlyDrop(shift: shift, now: now)
        }
        persist(force: false)
        broadcast(force: false)
    }

    private func checkHourlyDrop(shift: Shift, now: Date) {
        guard hourlyAlertEnabled, !entries.isEmpty, minPerHour > 0 else { return }
        let hours = shift.currentActiveSeconds(at: now) / 3600
        guard hours >= 1, now.timeIntervalSince(lastHourlyAlertAt) >= 45 * 60 else { return }
        let perHour = entriesTotal / hours
        guard perHour < minPerHour else { return }
        lastHourlyAlertAt = now
        NotificationService.shared.notify(
            id: "hourly.drop",
            title: "Rendimento abaixo do piso",
            body: "Média do turno: \(Fmt.brl(perHour))/h (piso \(Fmt.brl(minPerHour))/h). Considere mudar de região ou pausar.",
            discreet: true
        )
    }

    private func scheduleFatigue() {
        NotificationService.shared.cancelFatigue()
        guard fatigueAlertEnabled, let shift, shift.status == .running, let context else { return }
        let summaries = (try? context.fetch(FetchDescriptor<DailySummary>())) ?? []
        let day = shift.day
        let previous = summaries.first(where: { Calendar.br.isDate($0.day, inSameDayAs: day) })?.activeHours ?? 0
        NotificationService.shared.scheduleFatigue(alreadyWorked: previous * 3600 + shift.activeSeconds)
    }

    // MARK: Persistência e difusão (widgets / Live Activity)

    private func save() {
        try? context?.save()
    }

    private func persist(force: Bool) {
        guard let shift else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastPersistAt) >= 30 else { return }
        lastPersistAt = now
        shift.gpsKm = liveKm
        shift.drivingSeconds = drivingSeconds
        shift.pauses = pauses
        if routeDirty {
            shift.route = route
            routeDirty = false
        }
        save()
    }

    /// Atualiza widgets e Live Activity agora (chamado após lançamentos e mudanças de ajustes).
    func refreshShared() {
        broadcast(force: true)
    }

    private func liveNumbers(now: Date) -> (live: LiveDay, goal: Double)? {
        guard let context else { return nil }
        let engine = Store.engine(context)
        let day = shift?.day ?? Calendar.br.startOfDay(for: now)
        let live = engine.liveDay(
            day: day,
            shiftGross: entriesTotal,
            shiftKm: shift == nil ? 0 : liveKm,
            shiftSeconds: activeSeconds(at: now)
        )
        return (live, engine.weeklyGoal(now: now).todayTarget)
    }

    private func makeContentState(now: Date) -> ShiftActivityAttributes.ContentState {
        let numbers = liveNumbers(now: now)
        let active = activeSeconds(at: now)
        return ShiftActivityAttributes.ContentState(
            isPaused: !isRunning,
            timerReference: now.addingTimeInterval(-active),
            activeSeconds: active,
            km: liveKm,
            net: max(0, numbers?.live.net ?? 0),
            goal: numbers?.goal ?? 0,
            privacy: UserDefaults.standard.bool(forKey: "privacyMode")
        )
    }

    private func broadcast(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastBroadcastAt) >= 45 else { return }
        lastBroadcastAt = now
        guard let numbers = liveNumbers(now: now) else { return }
        let live = numbers.live
        let active = activeSeconds(at: now)
        let worked = shift != nil || live.gross > 0

        var state = SharedShiftState()
        if isRunning {
            state.status = .running
        } else if isPaused {
            state.status = .paused
        } else {
            state.status = .idle
        }
        state.timerReference = now.addingTimeInterval(-active)
        state.activeSeconds = active
        state.km = live.km
        state.grossToday = live.gross
        state.netToday = worked ? live.net : 0
        state.goalToday = numbers.goal
        state.privacy = UserDefaults.standard.bool(forKey: "privacyMode")
        state.updatedAt = now
        state.save()

        if force || now.timeIntervalSince(lastWidgetReloadAt) >= 15 * 60 {
            lastWidgetReloadAt = now
            WidgetCenter.shared.reloadAllTimelines()
        }
        if shift != nil {
            LiveActivityService.shared.update(makeContentState(now: now))
            notifyBreakEvenIfNeeded(live: live, now: now)
        }
    }

    private func notifyBreakEvenIfNeeded(live: LiveDay, now: Date) {
        guard live.isPaid, let shift else { return }
        let key = "breakeven.notified"
        let stamp = Fmt.date(shift.day, "yyyy-MM-dd")
        guard UserDefaults.standard.string(forKey: key) != stamp else { return }
        UserDefaults.standard.set(stamp, forKey: key)
        NotificationService.shared.notify(
            id: "breakeven",
            title: "Dia pago!",
            body: "O faturamento já cobriu o custo fixo e o combustível de hoje. Daqui em diante é lucro livre."
        )
    }
}

/// Consolida um turno encerrado no Resumo Geral Diário do dia em que ele começou.
@MainActor
enum SummaryBuilder {
    @discardableResult
    static func merge(_ shift: Shift, into context: ModelContext) -> Date {
        let day = shift.day
        guard !shift.mergedIntoSummary else { return day }
        let all = (try? context.fetch(FetchDescriptor<DailySummary>())) ?? []
        let summary: DailySummary
        if let existing = all.first(where: { Calendar.br.isDate($0.day, inSameDayAs: day) }) {
            summary = existing
        } else {
            summary = DailySummary(day: day)
            context.insert(summary)
        }

        summary.gpsKm += shift.gpsKm
        summary.activeHours += shift.activeSeconds / 3600
        summary.pausedHours += shift.pausedSeconds / 3600
        summary.drivingHours += shift.drivingSeconds / 3600
        if summary.startLat == nil {
            summary.startLat = shift.startLat
            summary.startLon = shift.startLon
        }
        if shift.endLat != nil {
            summary.endLat = shift.endLat
            summary.endLon = shift.endLon
        }

        var figures = summary.figures
        for entry in shift.entries {
            guard let category = RideCategory(rawValue: entry.category) else { continue }
            var item = figures[category] ?? CategoryFigures()
            item.gross += entry.amount
            item.trips += 1
            figures[category] = item
        }
        summary.figures = figures

        let engine = Store.engine(context)
        if summary.fuelCostPerKm <= 0 {
            summary.fuelCostPerKm = engine.fuel.currentCostPerKm
        }
        if summary.fixedCost <= 0 {
            summary.fixedCost = engine.vehicle.dailyFixedCost
        }
        summary.reserveCost = engine.reserveCost(gross: summary.totalGross, km: summary.costKm)
        shift.mergedIntoSummary = true
        return day
    }
}
