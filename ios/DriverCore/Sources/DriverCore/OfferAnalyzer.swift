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
    /// Matriz de aceite (categoria, busca, nota, hora e zonas). nil = classificação por pontuação.
    public var matrix: MatrixConfig?

    public init(costs: CostProfile = .empty, goals: Goals = Goals(), scoring: ScoringConfig = ScoringConfig(),
                pickupTimeFactor: Double = 1.35, tripTimeFactor: Double = 1.15, useRealisticTime: Bool = true,
                matrix: MatrixConfig? = nil) {
        self.matrix = matrix
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
    /// Veredito da matriz de aceite (nil quando ela está desligada ou faltam dados).
    public var matrix: MatrixVerdict?

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
        read(frame: frame, context: context).analysis
    }

    /// Como `analyze(frame:)`, mas devolve também a leitura (para saber quando um cartão ficou pela metade).
    public func read(frame: OcrFrame, context: AnalysisContext) -> (parse: ParseResult, analysis: OfferAnalysis?) {
        let p = parser.parse(frame)
        guard p.isOfferScreen else { return (p, nil) }
        return (p, analyze(offer: p.offer, confidence: p.confidence, fromOcr: true, context: context))
    }

    public func analyze(offer: OfferData, confidence: Double = 1, fromOcr: Bool = false, context ctx: AnalysisContext) -> OfferAnalysis {
        let v = OfferValidator.validate(offer)
        // Com a matriz ligada, o lucro usa só o CPK dela.
        let costs = ctx.matrix?.costs ?? ctx.costs
        let fin = financial.calculate(offer, costs: costs)
        var real: FinancialResult?
        if ctx.useRealisticTime, let p = offer.pickupTimeMin, let t = offer.tripTimeMin {
            var adjusted = offer
            adjusted.pickupTimeMin = p * ctx.pickupTimeFactor
            adjusted.tripTimeMin = t * ctx.tripTimeFactor
            real = financial.calculate(adjusted, costs: costs)
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
        var target = v.status == .invalid ? nil : FareAdvisor.target(basis, goals: ctx.goals)
        var verdict: MatrixVerdict?
        let readable = !fromOcr || conf >= ctx.scoring.minRecognitionConfidence
        if let m = ctx.matrix, v.status != .invalid, readable,
           let mv = AcceptanceMatrix().evaluate(basis, offer: offer, config: m) {
            verdict = mv
            dec = Decision(
                classification: mv.classification, score: nil, headline: mv.headline,
                reasons: (mv.refusals + mv.cautions + [mv.alert].compactMap { $0 }).map(\.capitalizedFirst),
                metricScores: [], isPartial: basis.missingInputs.contains(.pickupTime) || basis.missingInputs.contains(.tripTime)
            )
            target = Self.matrixTarget(basis, verdict: mv, config: m)
        }
        return OfferAnalysis(
            offer: offer,
            financial: fin,
            realistic: real,
            decision: dec,
            confidence: conf,
            fingerprint: Self.fingerprint(offer),
            fareTarget: target,
            matrix: verdict
        )
    }

    /// Valor mínimo para a matriz dar "aceitar": R$/km exigido, hora ideal e o mínimo da cidade.
    static func matrixTarget(_ r: FinancialResult, verdict v: MatrixVerdict, config m: MatrixConfig) -> FareTarget? {
        guard let km = r.totalDistanceKm, km > 0 else { return nil }
        var c: [(Double, String)] = []
        let intercityMin = v.zone.kind == .intercity ? v.zone.minimumFare : nil
        if let intercityMin {
            c.append((intercityMin, "mínimo intermunicipal"))
        } else {
            c.append((v.requiredPerKm * km, "valor por km"))
        }
        if let minutes = r.totalTimeMin, minutes > 0 {
            let hour = v.zone.kind == .hot ? m.hourFloor : m.hourIdeal
            c.append((hour * minutes / 60, "valor por hora"))
        }
        guard let best = c.max(by: { $0.0 < $1.0 }) else { return nil }
        return FareTarget(minimumFare: best.0, bindingGoal: best.1, breakEven: r.costPerKm.map { $0 * km },
                          gap: r.grossRevenue.map { $0 - best.0 })
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
/**
 * Texto da notificação, pensado para ser lido de relance:
 *  título     🟢 ACEITAR · R$ 19,20            (veredito e valor)
 *  subtítulo  R$ 2,16/km · R$ 54/h · Comfort   (os dois números que decidem)
 *  corpo      motivo (quando não é aceitar), resumo e alerta de zona
 * O texto evita as palavras e formatos do cartão do Uber ("min (km)", "viagem", "distância"),
 * para a leitura de tela nunca confundir a nossa notificação com um chamado.
 */
public enum NotificationFormatter {
    public struct Content: Equatable, Sendable {
        public var title: String
        public var subtitle: String
        public var body: String
    }

    /// `hourFloor` fica por compatibilidade; o veredito já considera o piso por hora.
    public static func format(_ a: OfferAnalysis, goals: Goals, hourFloor: Double? = nil) -> Content {
        let f = a.financial
        let b = a.basis
        let d = a.decision
        let mv = a.matrix

        let verdict: String
        switch d.classification {
        case .gray: verdict = "CONFERIR"
        default: verdict = mv?.label ?? d.classification.shortLabel
        }
        let title = "\(d.classification.dot) \(verdict) · \(Br.money(f.grossRevenue))"

        var sub: [String] = []
        if let rk = f.revenuePerKm { sub.append(Br.perKm(rk)) }
        if let rh = b.revenuePerHour { sub.append("R$ \(Br.decimal(rh, 0))/h") }
        if let c = a.offer.category { sub.append(c) }

        var lines: [String] = []
        if let mv {
            switch d.classification {
            case .red: lines += mv.shortRefusals.prefix(2).map { "✖︎ \($0)" }
            case .yellow: lines += mv.shortCautions.prefix(2).map { "• \($0)" }
            default: break
            }
        } else if d.classification != .green {
            lines.append(d.headline)
        }

        var summary: [String] = []
        if let p = f.operatingProfit { summary.append("Lucro \(Br.money(p))") }
        if let km = f.totalDistanceKm {
            var s = "Total \(Br.decimal(km, 1)) km"
            if let real = a.realistic?.totalTimeMin { s += " em ~\(Br.minutes(real))" } else if let tm = f.totalTimeMin { s += " em \(Br.minutes(tm))" }
            summary.append(s)
        }
        if !summary.isEmpty { lines.append(summary.joined(separator: " · ")) }

        if let mv {
            if let alert = mv.alert { lines.append("⚠️ \(alert)") }
            if mv.zone.kind == .hot { lines.append("🔥 Zona quente\(mv.zone.name.map { ": \($0.capitalized)" } ?? "")") }
        }
        if d.classification != .gray, mv == nil, let t = a.fareTarget, let gap = t.gap, gap < 0 {
            lines.append("Valor justo: \(Br.money(t.minimumFare))")
        }
        return Content(title: title, subtitle: sub.joined(separator: " · "), body: lines.joined(separator: "\n"))
    }
}
