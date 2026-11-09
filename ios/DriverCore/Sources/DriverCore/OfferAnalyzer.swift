import Foundation

public enum ValidationStatus: Sendable { case valid, incomplete, invalid }

/// Plausibilidade da leitura: não corrige valores, só reduz a confiança.
public enum OfferValidator {
    public static func validate(_ o: OfferData) -> (status: ValidationStatus, factor: Double) {
        var errors = 0
        var warnings = 0
        func range(_ v: Double?, _ r: ClosedRange<Double>) { if let v, !(v.isFinite && r.contains(v)) { errors += 1 } }
        range(o.fare, 3...1500)
        range(o.pickupDistanceKm, 0...40)
        range(o.tripDistanceKm, 0.2...400)
        range(o.pickupTimeMin, 0...90)
        range(o.tripTimeMin, 1...600)
        if let km = o.tripDistanceKm, let min = o.tripTimeMin, min > 0, !(2...140).contains(km / (min / 60)) { warnings += 1 }
        if let km = o.pickupDistanceKm, let min = o.pickupTimeMin, min > 0, km > 0, km / (min / 60) > 140 { warnings += 1 }
        if let f = o.fare, let p = o.pickupDistanceKm, let t = o.tripDistanceKm, p + t > 0, !(0.3...25).contains(f / (p + t)) { warnings += 1 }
        let missingEssential = o.fare == nil || o.pickupDistanceKm == nil || o.tripDistanceKm == nil
        let status: ValidationStatus = errors > 0 ? .invalid : (missingEssential ? .incomplete : .valid)
        return (status, pow(0.5, Double(errors)) * pow(0.8, Double(warnings)))
    }
}

/// Parâmetros do motorista usados em cada análise.
public struct AnalysisContext: Equatable, Codable, Sendable {
    public var costs: CostProfile
    public var goals: Goals
    public var scoring: ScoringConfig
    /// Multiplicadores do tempo exibido (os apps costumam subestimar a busca).
    public var pickupTimeFactor: Double
    public var tripTimeFactor: Double
    public var useRealisticTime: Bool

    public init(costs: CostProfile = .empty, goals: Goals = Goals(), scoring: ScoringConfig = ScoringConfig(),
                pickupTimeFactor: Double = 1.35, tripTimeFactor: Double = 1.15, useRealisticTime: Bool = true) {
        self.costs = costs
        self.goals = goals
        self.scoring = scoring
        self.pickupTimeFactor = pickupTimeFactor
        self.tripTimeFactor = tripTimeFactor
        self.useRealisticTime = useRealisticTime
    }
}

public struct OfferAnalysis: Equatable, Sendable {
    public var offer: OfferData
    public var financial: FinancialResult
    /// Mesma conta com tempos corrigidos (nil sem tempos ou com o ajuste desligado).
    public var realistic: FinancialResult?
    public var decision: Decision
    public var confidence: Double
    public var fingerprint: String?
    public var fareTarget: FareTarget?

    /// Resultado usado na classificação.
    public var basis: FinancialResult { realistic ?? financial }
}

public struct OfferAnalyzer: Sendable {
    let parser = OfferTextParser()
    let financial = FinancialEngine()
    let decision = DecisionEngine()

    public init() {}

    /// Texto da tela → análise, ou nil se não for uma tela de oferta.
    public func analyze(frame: OcrFrame, context: AnalysisContext) -> OfferAnalysis? {
        let p = parser.parse(frame)
        guard p.isOfferScreen else { return nil }
        return analyze(offer: p.offer, confidence: p.confidence, fromOcr: true, context: context)
    }

    public func analyze(offer: OfferData, confidence: Double = 1, fromOcr: Bool = false, context ctx: AnalysisContext) -> OfferAnalysis {
        let v = OfferValidator.validate(offer)
        let fin = financial.calculate(offer, costs: ctx.costs)
        var real: FinancialResult?
        if ctx.useRealisticTime, let p = offer.pickupTimeMin, let t = offer.tripTimeMin {
            var adjusted = offer
            adjusted.pickupTimeMin = p * ctx.pickupTimeFactor
            adjusted.tripTimeMin = t * ctx.tripTimeFactor
            real = financial.calculate(adjusted, costs: ctx.costs)
        }
        let basis = real ?? fin
        let conf = fromOcr ? confidence * v.factor : 1
        var dec: Decision
        if v.status == .invalid {
            dec = decision.decide(fin, goals: ctx.goals, config: ctx.scoring, recognitionConfidence: 0)
            dec.headline = "Leitura inconsistente. Confira os valores na tela."
        } else {
            dec = decision.decide(basis, goals: ctx.goals, config: ctx.scoring, recognitionConfidence: fromOcr ? conf : nil)
        }
        return OfferAnalysis(
            offer: offer,
            financial: fin,
            realistic: real,
            decision: dec,
            confidence: conf,
            fingerprint: Self.fingerprint(offer),
            fareTarget: v.status == .invalid ? nil : FareAdvisor.target(basis, goals: ctx.goals)
        )
    }

    /// Identidade estável da oferta (centavos | 100 m | 100 m | minutos).
    public static func fingerprint(_ o: OfferData) -> String? {
        guard let f = o.fare, let t = o.tripDistanceKm, let p = o.pickupDistanceKm else { return nil }
        let tm = o.tripTimeMin.map { String(Int($0.rounded())) } ?? "?"
        return "\(Int((f * 100).rounded()))|\(Int((p * 10).rounded()))|\(Int((t * 10).rounded()))|\(tm)"
    }
}

/**
 * Decide quando notificar:
 *  - confiança ≥ 85% → notifica no 1º frame; abaixo disso, exige 2 frames iguais;
 *  - a mesma oferta não é notificada de novo por [dedupWindow] segundos;
 *  - se a mesma oferta for relida com confiança bem maior, atualiza a notificação existente.
 */
public struct NotificationGate: Sendable {
    public enum Action: Equatable, Sendable { case none, notify(fingerprint: String), update(fingerprint: String) }

    public var instantConfidence = 0.85
    public var dedupWindow: TimeInterval = 120
    public var improveDelta = 0.10

    private var candidate: String?
    private var candidateHits = 0
    private var sent: [String: (at: TimeInterval, confidence: Double)] = [:]

    public init() {}

    public mutating func offer(_ a: OfferAnalysis, at now: TimeInterval) -> Action {
        sent = sent.filter { now - $0.value.at <= dedupWindow }
        guard let fp = a.fingerprint else { return .none }
        if let prev = sent[fp] {
            if a.confidence >= prev.confidence + improveDelta {
                sent[fp] = (prev.at, a.confidence)
                return .update(fingerprint: fp)
            }
            return .none
        }
        candidateHits = candidate == fp ? candidateHits + 1 : 1
        candidate = fp
        guard a.confidence >= instantConfidence || candidateHits >= 2 else { return .none }
        sent[fp] = (now, a.confidence)
        candidate = nil
        candidateHits = 0
        return .notify(fingerprint: fp)
    }
}

/// Texto da notificação, no estilo de leitura rápida.
public enum NotificationFormatter {
    public struct Content: Equatable, Sendable {
        public var title: String
        public var body: String
    }

    public static func format(_ a: OfferAnalysis, goals: Goals) -> Content {
        let f = a.financial
        let b = a.basis
        let d = a.decision
        func dot(_ met: Bool?) -> String {
            switch met {
            case .some(true): return "🟢"
            case .some(false): return "🔴"
            case .none: return "⚪️"
            }
        }
        let kmOk = f.revenuePerKm.map { $0 >= goals.minRevenuePerKm }
        let hourOk = b.revenuePerHour.map { $0 >= goals.minRevenuePerHour }

        var title = "\(d.classification.dot)\(Br.money(f.grossRevenue))"
        if let rk = f.revenuePerKm { title += "  \(dot(kmOk))\(Br.decimal(rk))/km" }
        if let rh = b.revenuePerHour { title += "  \(dot(hourOk))\(Br.decimal(rh, 0))/h" }

        var line1: [String] = [d.classification.shortLabel]
        if let p = f.operatingProfit {
            let margin = f.operatingMargin.map { " (\(Br.percent($0)))" } ?? ""
            line1.append("Lucro: \(Br.money(p))\(margin)")
        }
        if let t = a.fareTarget, d.classification != .gray, let gap = t.gap, gap < 0 {
            line1.append("justo \(Br.money(t.minimumFare))")
        }

        var line2: [String] = []
        if let c = a.offer.category { line2.append(c) }
        if let tm = f.totalTimeMin {
            if let real = a.realistic?.totalTimeMin, abs(real - tm) >= 1 {
                line2.append("\(Br.minutes(tm)) → ~\(Br.minutes(real)) real")
            } else {
                line2.append(Br.minutes(tm))
            }
        }
        if let km = f.totalDistanceKm { line2.append("(\(Br.km(km)))") }
        if let pk = a.offer.pickupDistanceKm { line2.append("· busca \(Br.km(pk))") }

        var body = line1.joined(separator: " · ")
        if !line2.isEmpty { body += "\n" + line2.joined(separator: " ") }
        if d.classification == .gray || d.classification == .red { body += "\n" + d.headline }
        return Content(title: title, body: body)
    }
}
