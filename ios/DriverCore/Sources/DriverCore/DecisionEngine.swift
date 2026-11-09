import Foundation

/**
 * Classificação por vários indicadores ponderados (mesma regra do Android):
 *  nota 0..1 por indicador: 60% da meta → 0 · meta → 0,7 · 125% → 1,0
 *  lucro ≤ 0 → VERMELHO · abaixo do lucro mínimo/distância máxima → no máximo AMARELO.
 * Só recomenda; nunca aceita ou recusa.
 */
public struct DecisionEngine: Sendable {
    public init() {}

    public func decide(_ r: FinancialResult, goals: Goals, config: ScoringConfig = ScoringConfig(), recognitionConfidence: Double? = nil) -> Decision {
        let missingEssentials = OfferField.allCases.filter { OfferField.essential.contains($0) && r.missingInputs.contains($0) }
        guard missingEssentials.isEmpty, let fare = r.grossRevenue else {
            return gray("Dados insuficientes: falta \(missingEssentials.map(\.label).joined(separator: ", ")).", ["Confira a oferta na tela."])
        }
        if let conf = recognitionConfidence, conf < config.minRecognitionConfidence {
            return gray("Leitura incerta (\(Int((conf * 100).rounded()))% de confiança). Confira na tela.", [])
        }

        var scores: [MetricScore] = []
        func higher(_ m: Metric, _ v: Double?, _ t: Double) {
            guard let v, v.isFinite else { return }
            scores.append(MetricScore(metric: m, value: v, target: t, score: Self.scoreHigher(v, t), weight: max(0, config.weights.weight(m))))
        }
        func lower(_ m: Metric, _ v: Double?, _ limit: Double) {
            guard let v, v.isFinite else { return }
            scores.append(MetricScore(metric: m, value: v, target: limit, score: Self.scoreLower(v, limit), weight: max(0, config.weights.weight(m))))
        }
        higher(.revenuePerKm, r.revenuePerKm, goals.minRevenuePerKm)
        higher(.profitPerKm, r.profitPerKm, goals.minProfitPerKm)
        higher(.revenuePerHour, r.revenuePerHour, goals.minRevenuePerHour)
        higher(.profitPerHour, r.profitPerHour, goals.minProfitPerHour)
        lower(.pickupTime, r.unproductiveTimeMin, goals.maxPickupMinutes)
        lower(.unproductiveDistance, r.productiveDistanceShare.map { 1 - $0 }, goals.maxUnproductiveShare)
        lower(.costShare, r.totalCost.flatMap { fare > 0 ? $0 / fare : nil }, goals.maxCostShare)

        if scores.count < 2 {
            return gray("Indicadores insuficientes para recomendar.", ["Informe tempos e custos do veículo."])
        }
        let wsum = scores.reduce(0) { $0 + $1.weight }
        let weighted = wsum > 0 ? scores.reduce(0) { $0 + $1.score * $1.weight } / wsum : scores.reduce(0) { $0 + $1.score } / Double(scores.count)

        var cls: Classification = weighted >= config.greenThreshold ? .green : (weighted >= config.yellowThreshold ? .yellow : .red)
        var hard: [String] = []
        if let p = r.operatingProfit, p <= 0 {
            cls = .red
            hard.append("prejuízo estimado de \(Br.money(-p))")
        } else {
            if let m = goals.minProfitPerTrip, let p = r.operatingProfit, p < m {
                if cls == .green { cls = .yellow }
                hard.append("lucro estimado abaixo da sua meta")
            }
            if let maxT = goals.maxTotalDistanceKm, let t = r.totalDistanceKm, t > maxT {
                if cls == .green { cls = .yellow }
                hard.append("distância total acima do seu limite")
            }
        }

        let weaknesses = scores.filter { !$0.meetsTarget }.sorted { $0.weight * (1 - $0.score) > $1.weight * (1 - $1.score) }.map(\.metric.weakness)
        let strengths = scores.filter(\.meetsTarget).sorted { $0.weight * $0.score > $1.weight * $1.score }.map(\.metric.strength)
        let headlineWeak = Array((Array(weaknesses.prefix(hard.isEmpty ? 2 : 1)) + Array(hard.prefix(1))).uniqued())

        let headline: String
        switch cls {
        case .green:
            let parts = [r.revenuePerKm.map { Br.perKm($0) }, (r.revenuePerHour ?? r.profitPerHour).map { Br.perHour($0) }].compactMap { $0 }
            headline = "Boa rentabilidade: \(Self.joinPt(parts))."
        case .yellow:
            headline = headlineWeak.isEmpty ? "Rentabilidade moderada." : "Rentabilidade moderada: \(Self.joinPt(headlineWeak))."
        case .red:
            headline = headlineWeak.isEmpty ? "Não recomendada: abaixo das suas metas." : "Não recomendada: \(Self.joinPt(headlineWeak))."
        case .gray:
            headline = "Dados insuficientes."
        }

        var reasons = (weaknesses + hard).uniqued().map(\.capitalizedFirst) + strengths.map(\.capitalizedFirst)
        if r.isCostEstimatePartial { reasons.append("Estimativa parcial: custos não configurados.") }
        let partial = r.isCostEstimatePartial || r.missingInputs.contains(.pickupTime) || r.missingInputs.contains(.tripTime)
        return Decision(classification: cls, score: weighted, headline: headline, reasons: reasons, metricScores: scores, isPartial: partial)
    }

    private func gray(_ h: String, _ reasons: [String]) -> Decision {
        Decision(classification: .gray, score: nil, headline: h, reasons: reasons, metricScores: [], isPartial: true)
    }

    public static func scoreHigher(_ v: Double, _ t: Double) -> Double {
        if t <= 0 { return 1 }
        let r = v / t
        if r >= 1.25 { return 1 }
        if r >= 1.0 { return 0.7 + (r - 1) / 0.25 * 0.3 }
        if r >= 0.6 { return (r - 0.6) / 0.4 * 0.7 }
        return 0
    }

    public static func scoreLower(_ v: Double, _ limit: Double) -> Double {
        if v <= 0 { return 1 }
        if limit <= 0 { return 0 }
        return scoreHigher(limit / v, 1)
    }

    public static func joinPt(_ p: [String]) -> String {
        switch p.count {
        case 0: return ""
        case 1: return p[0]
        default: return p.dropLast().joined(separator: ", ") + " e " + p.last!
        }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
