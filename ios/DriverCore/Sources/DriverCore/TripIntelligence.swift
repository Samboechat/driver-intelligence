import Foundation

// MARK: - Classificação da tela

/// O que o app de corrida está mostrando agora.
public enum ScreenKind: String, Codable, Sendable {
    case offer, goingToPickup, waitingPassenger, onTrip, tripCompleted, onlineIdle, offline, unknown

    public var label: String {
        switch self {
        case .offer: return "Oferta"
        case .goingToPickup: return "Indo buscar"
        case .waitingPassenger: return "Aguardando passageiro"
        case .onTrip: return "Em viagem"
        case .tripCompleted: return "Viagem concluída"
        case .onlineIdle: return "Procurando viagens"
        case .offline: return "Offline"
        case .unknown: return "Outra tela"
        }
    }
}

/// Identifica a tela pelo texto (pt/en). Telas não reconhecidas viram `.unknown` e nunca disparam transições.
public enum ScreenClassifier {
    static let completed = ["viagem concluida", "corrida concluida", "viagem finalizada", "corrida finalizada", "entrega concluida",
                            "avalie o passageiro", "avalie sua viagem", "avaliar passageiro", "como foi a viagem", "voce ganhou",
                            "trip complete", "rate your rider", "rate rider", "you earned"]
    static let onTrip = ["finalizar viagem", "finalizar corrida", "concluir viagem", "concluir corrida", "encerrar viagem",
                         "deixando o passageiro", "levando ", "a caminho do destino", "rumo ao destino", "desembarque",
                         "end trip", "complete trip", "dropping off"]
    static let waiting = ["iniciar viagem", "iniciar corrida", "deslize para iniciar", "aguardando o passageiro", "aguardando passageiro",
                          "voce chegou", "chegou ao local", "esperando o passageiro", "tempo de espera",
                          "start trip", "swipe to start", "waiting for", "you have arrived"]
    static let toPickup = ["a caminho do passageiro", "a caminho do embarque", "indo buscar", "buscar o passageiro",
                           "ir ate o passageiro", "local de embarque", "cheguei", "chegando ao embarque", "embarque em",
                           "picking up", "en route to pickup", "pickup at"]
    static let offline = ["voce esta offline", "voce esta desconectado", "ficar online", "you're offline", "you are offline", "go online"]
    static let idle = ["procurando viagens", "procurando corridas", "buscando viagens", "voce esta online", "aguardando solicitacoes",
                       "finding trips", "you're online", "you are online", "looking for trips"]

    public static func classify(_ frame: OcrFrame, isOfferScreen: Bool) -> ScreenKind {
        if isOfferScreen { return .offer }
        let t = " " + OfferTextParser.normalize(frame.lines.map(\.text).joined(separator: " ")) + " "
        func has(_ l: [String]) -> Bool { l.contains { t.contains($0) } }
        if has(completed) { return .tripCompleted }
        if has(onTrip) { return .onTrip }
        if has(waiting) { return .waitingPassenger }
        if has(toPickup) { return .goingToPickup }
        if has(offline) { return .offline }
        if has(idle) { return .onlineIdle }
        return .unknown
    }
}

// MARK: - Aceite, recusa e corrida em andamento

public enum OfferOutcome: String, Codable, Sendable {
    case accepted, rejected, expired, unknown

    public var label: String {
        switch self {
        case .accepted: return "Aceita"
        case .rejected: return "Recusada"
        case .expired: return "Ignorada"
        case .unknown: return "Sem confirmação"
        }
    }
}

public enum TripPhase: String, Codable, Sendable {
    case none, offer, toPickup, waiting, onTrip

    public var label: String {
        switch self {
        case .none: return "Sem corrida"
        case .offer: return "Oferta na tela"
        case .toPickup: return "Indo buscar"
        case .waiting: return "Aguardando passageiro"
        case .onTrip: return "Em viagem"
        }
    }
}

/// Linha do tempo real de uma corrida aceita (segundos desde 1970).
public struct TripTimeline: Equatable, Sendable {
    public var offer: OfferAnalysis
    public var acceptedAt: TimeInterval
    public var arrivedAt: TimeInterval?
    public var startedAt: TimeInterval?
    public var completedAt: TimeInterval?
    public var manual: Bool = false

    public var actualPickupMin: Double? { (arrivedAt ?? startedAt).map { max(0, $0 - acceptedAt) / 60 } }
    public var actualTripMin: Double? {
        guard let s = startedAt, let c = completedAt else { return nil }
        return max(0, c - s) / 60
    }
    public var totalMin: Double? { completedAt.map { max(0, $0 - acceptedAt) / 60 } }
}

public enum TrackerEvent: Sendable {
    case observe(ScreenKind, OfferAnalysis?, TimeInterval)
    case manualAccept(OfferAnalysis, TimeInterval)
    case manualFinish(TimeInterval)
    case reset
}

public enum TrackerEffect: Equatable, Sendable {
    case outcome(OfferAnalysis, OfferOutcome, TimeInterval)
    case phase(TripPhase, TripTimeline?)
    case finished(TripTimeline)
    case cancelled(TripTimeline)
}

/**
 * Entende o que o motorista fez com a oferta e acompanha a corrida aceita (mesma lógica do Android):
 *  oferta → tela de busca/espera/viagem → ACEITA → … → concluída
 *  oferta → "procurando viagens" → RECUSADA (ou IGNORADA, se ficou até o tempo acabar)
 * Uma tela só conta depois de aparecer em 2 leituras seguidas.
 */
public struct TripTracker: Sendable {
    public var stableFrames = 2
    public var expireAfter: TimeInterval = 13
    public var unknownAfter: TimeInterval = 25
    public var maxTrip: TimeInterval = 4 * 3600

    public private(set) var phase: TripPhase = .none
    public private(set) var offer: OfferAnalysis?
    public private(set) var timeline: TripTimeline?
    private var offerShownAt: TimeInterval = 0
    private var offerLastSeen: TimeInterval = 0
    private var pending: ScreenKind?
    private var pendingCount = 0
    private var pendingSince: TimeInterval = 0

    public init() {}

    public mutating func handle(_ e: TrackerEvent) -> [TrackerEffect] {
        switch e {
        case .reset:
            self = TripTracker()
            return []
        case let .manualAccept(o, t):
            if offer?.fingerprint != o.fingerprint { offerShownAt = t }
            offer = o
            return accept(at: t, phase: .toPickup, manual: true)
        case let .manualFinish(t):
            guard let tl = timeline else { return [] }
            return finish(tl, at: t)
        case let .observe(kind, o, t):
            return observe(kind, o, t)
        }
    }

    private mutating func clear() -> [TrackerEffect] {
        let had = phase != .none
        phase = .none; offer = nil; timeline = nil
        return had ? [.phase(.none, nil)] : []
    }

    private mutating func observe(_ kind: ScreenKind, _ o: OfferAnalysis?, _ t: TimeInterval) -> [TrackerEffect] {
        if pending == kind { pendingCount += 1 } else { pending = kind; pendingCount = 1; pendingSince = t }
        let stable = pendingCount >= stableFrames
        if let tl = timeline, t - tl.acceptedAt > maxTrip { return clear() }

        switch phase {
        case .none:
            if kind == .offer, let o, o.fingerprint != nil {
                phase = .offer; offer = o; offerShownAt = t; offerLastSeen = t
                return [.phase(.offer, nil)]
            }
            return []

        case .offer:
            guard let current = offer else { return clear() }
            switch kind {
            case .offer:
                if let o, let fp = o.fingerprint, fp != current.fingerprint {
                    let out = outcomeOnDisappear()
                    offer = o; offerShownAt = t; offerLastSeen = t
                    return [.outcome(current, out, t)]
                }
                offerLastSeen = t
                if let o, o.fingerprint == current.fingerprint { offer = o }
                return []
            case .goingToPickup, .waitingPassenger, .onTrip:
                return stable ? accept(at: pendingSince, phase: phaseFor(kind), manual: false) : []
            case .onlineIdle, .offline:
                guard stable else { return [] }
                let out = outcomeOnDisappear()
                return [.outcome(current, out, t)] + clear()
            default:
                if t - offerLastSeen > unknownAfter { return [.outcome(current, .unknown, t)] + clear() }
                return []
            }

        case .toPickup, .waiting:
            guard var tl = timeline else { return clear() }
            switch kind {
            case .waitingPassenger where stable && phase == .toPickup:
                tl.arrivedAt = pendingSince
                return move(.waiting, tl)
            case .onTrip where stable:
                tl.startedAt = pendingSince
                tl.arrivedAt = tl.arrivedAt ?? pendingSince
                return move(.onTrip, tl)
            case .tripCompleted, .onlineIdle, .offline:
                if pendingCount >= stableFrames + 1 { return [.cancelled(tl)] + clear() }
                return []
            default:
                return []
            }

        case .onTrip:
            guard let tl = timeline else { return clear() }
            switch kind {
            case .tripCompleted: return finish(tl, at: pendingSince)
            case .onlineIdle, .offline: return stable ? finish(tl, at: pendingSince) : []
            default: return []
            }
        }
    }

    private func outcomeOnDisappear() -> OfferOutcome {
        offerLastSeen - offerShownAt >= expireAfter ? .expired : .rejected
    }

    private func phaseFor(_ k: ScreenKind) -> TripPhase {
        switch k {
        case .waitingPassenger: return .waiting
        case .onTrip: return .onTrip
        default: return .toPickup
        }
    }

    private mutating func accept(at t: TimeInterval, phase p: TripPhase, manual: Bool) -> [TrackerEffect] {
        guard let o = offer, timeline == nil else { return [] }
        let tl = TripTimeline(
            offer: o, acceptedAt: t,
            arrivedAt: (p == .waiting || p == .onTrip) ? t : nil,
            startedAt: p == .onTrip ? t : nil,
            manual: manual
        )
        timeline = tl
        phase = p
        return [.outcome(o, .accepted, t), .phase(p, tl)]
    }

    private mutating func move(_ p: TripPhase, _ tl: TripTimeline) -> [TrackerEffect] {
        timeline = tl
        phase = p
        return [.phase(p, tl)]
    }

    private mutating func finish(_ tl: TripTimeline, at t: TimeInterval) -> [TrackerEffect] {
        var done = tl
        let started = tl.startedAt ?? tl.arrivedAt ?? tl.acceptedAt
        done.startedAt = started
        done.arrivedAt = tl.arrivedAt ?? started
        done.completedAt = max(t, started)
        return [.finished(done)] + clear()
    }
}

// MARK: - Aprendizado do tempo real

public struct TimingSample: Codable, Equatable, Sendable {
    public var at: TimeInterval
    public var offeredPickupMin: Double?
    public var actualPickupMin: Double?
    public var offeredTripMin: Double?
    public var actualTripMin: Double?

    public init(at: TimeInterval, offeredPickupMin: Double?, actualPickupMin: Double?, offeredTripMin: Double?, actualTripMin: Double?) {
        self.at = at
        self.offeredPickupMin = offeredPickupMin
        self.actualPickupMin = actualPickupMin
        self.offeredTripMin = offeredTripMin
        self.actualTripMin = actualTripMin
    }
}

public struct TimeFactors: Equatable, Sendable {
    public var pickup: Double
    public var trip: Double
    public var pickupSamples: Int
    public var tripSamples: Int
    public var learned: Bool
}

/**
 * Quanto os tempos da oferta atrasam na prática: mediana das últimas corridas medidas,
 * só do mesmo horário (±1 h) quando há amostras suficientes. Sem amostras, usa o padrão do motorista.
 */
public struct TimeCalibration: Sendable {
    let samples: [TimingSample]
    let defaultPickup: Double
    let defaultTrip: Double
    let minSamples: Int

    public init(samples: [TimingSample], defaultPickup: Double, defaultTrip: Double, minSamples: Int = 5) {
        self.samples = Array(samples.sorted { $0.at > $1.at }.prefix(40))
        self.defaultPickup = defaultPickup
        self.defaultTrip = defaultTrip
        self.minSamples = minSamples
    }

    public func factors(hour: Int?, calendar: Calendar = .current) -> TimeFactors {
        func ratios(_ pick: (TimingSample) -> (Double?, Double?)) -> [(Int, Double)] {
            samples.compactMap { s in
                let (o, a) = pick(s)
                guard let o, let a, o >= 1, a > 0 else { return nil }
                let r = a / o
                guard (0.3...5).contains(r) else { return nil }
                return (calendar.component(.hour, from: Date(timeIntervalSince1970: s.at)), r)
            }
        }
        func choose(_ list: [(Int, Double)], _ def: Double) -> (Double, Int, Bool) {
            if let hour {
                let near = list.filter { min(abs($0.0 - hour), 24 - abs($0.0 - hour)) <= 1 }
                if near.count >= minSamples { return (Self.clamp(Self.median(near.map(\.1))), near.count, true) }
            }
            if list.count >= minSamples { return (Self.clamp(Self.median(list.map(\.1))), list.count, true) }
            return (def, list.count, false)
        }
        let p = choose(ratios { ($0.offeredPickupMin, $0.actualPickupMin) }, defaultPickup)
        let t = choose(ratios { ($0.offeredTripMin, $0.actualTripMin) }, defaultTrip)
        return TimeFactors(pickup: p.0, trip: t.0, pickupSamples: p.1, tripSamples: t.1, learned: p.2 || t.2)
    }

    static func median(_ v: [Double]) -> Double {
        let s = v.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    static func clamp(_ v: Double) -> Double { min(3, max(0.6, v)) }
}
