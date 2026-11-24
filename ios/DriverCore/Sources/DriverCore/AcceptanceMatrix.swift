import Foundation

/// Grupo de categoria da matriz de aceite.
public enum RideClass: String, Codable, Sendable {
    case comfort, standard

    public var label: String {
        switch self {
        case .comfort: return "Comfort"
        case .standard: return "UberX/99"
        }
    }

    /// Comfort e Black usam a régua do Comfort; o resto (UberX, 99Pop, sem categoria lida) usa a do UberX/99.
    public static func of(_ category: String?) -> RideClass {
        guard let c = category?.lowercased() else { return .standard }
        return (c.contains("comfort") || c.contains("black")) ? .comfort : .standard
    }
}

/// Régua de uma categoria.
public struct CategoryRule: Equatable, Codable, Sendable {
    /// R$/km a partir do qual aceita (verde).
    public var acceptPerKm: Double
    /// R$/km mínimo da faixa amarela; abaixo disso recusa.
    public var yellowPerKm: Double
    /// Busca máxima para corridas curtas / longas (km).
    public var pickupShortKm: Double
    public var pickupLongKm: Double
    public var minRating: Double

    public init(acceptPerKm: Double, yellowPerKm: Double, pickupShortKm: Double, pickupLongKm: Double, minRating: Double) {
        self.acceptPerKm = acceptPerKm
        self.yellowPerKm = yellowPerKm
        self.pickupShortKm = pickupShortKm
        self.pickupLongKm = pickupLongKm
        self.minRating = minRating
    }
}

/// Matriz de aceite (valores do motorista; R$/km = valor ÷ (busca + viagem)).
public struct MatrixConfig: Equatable, Codable, Sendable {
    /// Custo por km rodado (CPK), já com combustível.
    public var costPerKm: Double
    /// Abaixo disso por hora, recusa.
    public var hourFloor: Double
    /// A partir disso por hora, ideal; entre o piso e o ideal fica amarela.
    public var hourIdeal: Double
    public var comfort: CategoryRule
    public var standard: CategoryRule
    /// Até essa distância de viagem vale a busca "curta"; a partir de `longTripKm`, a "longa"; no meio, proporcional.
    public var shortTripKm: Double
    public var longTripKm: Double
    public var zones: ZoneConfig
    /// Piso por minuto SEM dinâmico (busca + viagem, tempos da oferta). 0 = desligado.
    public var minPerMinute: Double
    /// Confere se o dinâmico é ganho extra de verdade: o valor sem ele precisa passar nas réguas.
    public var checkSurge: Bool

    public init(
        costPerKm: Double = 0.50, hourFloor: Double = 42, hourIdeal: Double = 54,
        comfort: CategoryRule = CategoryRule(acceptPerKm: 2.30, yellowPerKm: 2.00, pickupShortKm: 5, pickupLongKm: 8, minRating: 4.80),
        standard: CategoryRule = CategoryRule(acceptPerKm: 2.10, yellowPerKm: 1.85, pickupShortKm: 3, pickupLongKm: 6, minRating: 4.85),
        shortTripKm: Double = 5, longTripKm: Double = 20, zones: ZoneConfig = .sorocaba,
        minPerMinute: Double = 1.00, checkSurge: Bool = true
    ) {
        self.costPerKm = costPerKm
        self.hourFloor = hourFloor
        self.hourIdeal = hourIdeal
        self.comfort = comfort
        self.standard = standard
        self.shortTripKm = shortTripKm
        self.longTripKm = longTripKm
        self.zones = zones
        self.minPerMinute = minPerMinute
        self.checkSurge = checkSurge
    }

    /// Ajustes salvos por versões antigas não têm os campos novos: cada um que faltar usa o padrão.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MatrixConfig()
        costPerKm = try c.decodeIfPresent(Double.self, forKey: .costPerKm) ?? d.costPerKm
        hourFloor = try c.decodeIfPresent(Double.self, forKey: .hourFloor) ?? d.hourFloor
        hourIdeal = try c.decodeIfPresent(Double.self, forKey: .hourIdeal) ?? d.hourIdeal
        comfort = try c.decodeIfPresent(CategoryRule.self, forKey: .comfort) ?? d.comfort
        standard = try c.decodeIfPresent(CategoryRule.self, forKey: .standard) ?? d.standard
        shortTripKm = try c.decodeIfPresent(Double.self, forKey: .shortTripKm) ?? d.shortTripKm
        longTripKm = try c.decodeIfPresent(Double.self, forKey: .longTripKm) ?? d.longTripKm
        zones = try c.decodeIfPresent(ZoneConfig.self, forKey: .zones) ?? d.zones
        minPerMinute = try c.decodeIfPresent(Double.self, forKey: .minPerMinute) ?? d.minPerMinute
        checkSurge = try c.decodeIfPresent(Bool.self, forKey: .checkSurge) ?? d.checkSurge
    }

    public func rule(_ c: RideClass) -> CategoryRule { c == .comfort ? comfort : standard }

    /// Custos usados na conta do lucro: só o CPK.
    public var costs: CostProfile {
        CostProfile(operationalCostPerKmOverride: costPerKm, operationalCostIncludesFuel: true)
    }

    /// Busca máxima para uma viagem desse tamanho.
    public func pickupLimitKm(_ c: RideClass, tripKm: Double) -> Double {
        let r = rule(c)
        if tripKm <= shortTripKm || longTripKm <= shortTripKm { return r.pickupShortKm }
        if tripKm >= longTripKm { return r.pickupLongKm }
        let f = (tripKm - shortTripKm) / (longTripKm - shortTripKm)
        return r.pickupShortKm + f * (r.pickupLongKm - r.pickupShortKm)
    }
}

/**
 * Dinâmico na oferta: quanto é, quanto a corrida pagaria sem ele e se ele é ganho extra de verdade.
 *
 * "Dinâmico de fachada": o valor total passa nas réguas, mas o valor SEM o dinâmico não passaria —
 * o dinâmico só está tapando uma tarifa baixa, e no fim a corrida paga o mesmo que uma comum.
 * Dinâmico real: o valor sem ele já paga o piso, e o dinâmico inteiro é lucro a mais.
 */
public struct SurgeCheck: Equatable, Sendable {
    /// Dinâmico incluído no valor.
    public var amount: Double
    /// Valor sem o dinâmico.
    public var baseFare: Double
    public var basePerKm: Double
    public var basePerMinute: Double?
    /// O mínimo que a corrida deveria pagar sem dinâmico (piso por minuto e R$/km de aceite).
    public var minimumBase: Double
    /// Valor justo com o dinâmico por cima: mínimo sem dinâmico + dinâmico.
    public var fairFare: Double
    /// O valor sem dinâmico já passa nas réguas: o dinâmico é ganho extra.
    public var real: Bool
    /// Quanto do dinâmico é ganho extra de verdade (0 se o valor sem ele ficou abaixo do mínimo).
    public var extraGain: Double

    /// "+R$ 4,00 dinâmico".
    public var short: String { "⚡ +\(Br.money(amount)) dinâmico" }
}

/// Resultado da matriz para uma oferta.
public struct MatrixVerdict: Equatable, Sendable {
    public var classification: Classification
    public var rideClass: RideClass
    public var zone: ZoneMatch
    public var pickupLimitKm: Double
    /// R$/km exigido para o verde nesta oferta (categoria + zona).
    public var requiredPerKm: Double
    public var refusals: [String]
    public var cautions: [String]
    /// Mesmos motivos, em versão curta para a notificação.
    public var shortRefusals: [String] = []
    public var shortCautions: [String] = []
    public var alert: String?
    public var headline: String
    /// R$/min da oferta (valor total ÷ minutos de busca + viagem mostrados no chamado).
    public var perMinute: Double?
    /// Dinâmico (só quando o chamado mostra um).
    public var surge: SurgeCheck?

    /// ACEITAR / AVALIAR / RECUSAR.
    public var label: String {
        switch classification {
        case .green: return "ACEITAR"
        case .yellow: return "AVALIAR"
        case .red: return "RECUSAR"
        case .gray: return "INCOMPLETO"
        }
    }
}

/**
 * Matriz de aceite. Só recomenda; nunca aceita ou recusa.
 *
 * Recusa (vermelho) se qualquer uma valer:
 *  - R$/km abaixo do mínimo da faixa amarela da categoria;
 *  - busca acima do limite (curta→longa conforme a distância da viagem);
 *  - nota do passageiro abaixo da mínima (quando lida);
 *  - R$/h abaixo do piso (quando há tempos);
 *  - R$/min abaixo do piso por minuto (tempos do chamado; padrão R$ 1,00/min);
 *  - destino de periferia pagando menos que o mínimo de periferia;
 *  - destino intermunicipal pagando menos que o mínimo da cidade.
 * Amarelo: R$/km na faixa amarela, R$/h entre o piso e o ideal, ou dinâmico de fachada
 * (o total passa, mas o valor sem o dinâmico não passaria no R$/km de aceite e no piso por minuto).
 * Zona quente: o amarelo vira verde. Periferia: sempre com o alerta de volta vazia.
 * Intermunicipal com o mínimo atingido: o R$/km da faixa não se aplica (o mínimo já embute a volta vazia).
 */
public struct AcceptanceMatrix: Sendable {
    public init() {}

    /// `r` deve ser a conta usada na classificação (com tempo realista, se ligado). Sem valor ou distâncias → nil.
    public func evaluate(_ r: FinancialResult, offer: OfferData, config m: MatrixConfig) -> MatrixVerdict? {
        guard let fare = r.grossRevenue, let perKm = r.revenuePerKm,
              let tripKm = offer.tripDistanceKm, let pickupKm = offer.pickupDistanceKm else { return nil }

        // Tolerância para arredondamento de ponto flutuante nos limites (2,30 conta como 2,30).
        let eps = 1e-9
        let cls = RideClass.of(offer.category)
        let rule = m.rule(cls)
        let zone = SorocabaZone.classify(offer.destination, config: m.zones)
        let intercityOK = zone.kind == .intercity && fare >= (zone.minimumFare ?? 0) - eps
        let pickupLimit = intercityOK ? rule.pickupLongKm : m.pickupLimitKm(cls, tripKm: tripKm)

        var refusals: [String] = []
        var cautions: [String] = []
        var shortRefusals: [String] = []
        var shortCautions: [String] = []
        var alert: String?

        // 1. Zona
        switch zone.kind {
        case .intercity:
            if let minFare = zone.minimumFare, fare < minFare - eps {
                refusals.append("\(zone.name ?? "intermunicipal") exige \(Br.money(minFare)) (volta vazia); paga \(Br.money(fare))")
                shortRefusals.append("\(zone.name ?? "Intermunicipal") paga \(Br.money(fare)) · mínimo \(Br.money(minFare))")
            }
            alert = "Intermunicipal: volta vazia"
        case .periphery:
            if perKm < m.zones.peripheryMinPerKm - eps {
                refusals.append("periferia exige \(Br.perKm(m.zones.peripheryMinPerKm)); paga \(Br.perKm(perKm))")
                shortRefusals.append("Periferia: \(Br.decimal(perKm)) por km · mínimo \(Br.decimal(m.zones.peripheryMinPerKm))")
            }
            alert = m.zones.peripheryAlert
        case .hot, .neutral:
            break
        }

        // 2. R$/km da categoria (não se aplica ao intermunicipal que atingiu o mínimo)
        if !intercityOK {
            if perKm < rule.yellowPerKm - eps {
                refusals.append("\(Br.perKm(perKm)) abaixo de \(Br.perKm(rule.yellowPerKm)) (\(cls.label))")
                shortRefusals.append("Km baixo: \(Br.decimal(perKm)) · mínimo \(Br.decimal(rule.yellowPerKm))")
            } else if perKm < rule.acceptPerKm - eps {
                cautions.append("\(Br.perKm(perKm)) na faixa amarela (\(cls.label) aceita a partir de \(Br.perKm(rule.acceptPerKm)))")
                shortCautions.append("Km na faixa amarela: \(Br.decimal(perKm)) · ideal \(Br.decimal(rule.acceptPerKm))")
            }
        }

        // 3. Busca
        if pickupKm > pickupLimit + eps {
            refusals.append("busca de \(Br.km(pickupKm)) acima do limite de \(Br.km(pickupLimit))")
            shortRefusals.append("Busca longa: \(Br.decimal(pickupKm, 1)) · máximo \(Br.decimal(pickupLimit, 1))")
        }

        // 4. Nota
        if let rating = offer.passengerRating, rating < rule.minRating - eps {
            refusals.append("nota \(Br.decimal(rating)) abaixo de \(Br.decimal(rule.minRating))")
            shortRefusals.append("Nota baixa: \(Br.decimal(rating)) · mínimo \(Br.decimal(rule.minRating))")
        }

        // 5. Minuto: piso por minuto, com os tempos que aparecem no chamado (o motorista confere de cabeça).
        let shownMinutes: Double? = {
            if let p = offer.pickupTimeMin, let t = offer.tripTimeMin, p + t > 0 { return p + t }
            return nil
        }()
        let perMinute = shownMinutes.map { fare / $0 }
        if m.minPerMinute > 0, !intercityOK, let perMinute, perMinute < m.minPerMinute - eps {
            refusals.append("\(Br.money(perMinute))/min abaixo do piso de \(Br.money(m.minPerMinute))/min")
            shortRefusals.append("Minuto baixo: \(Br.decimal(perMinute)) · piso \(Br.decimal(m.minPerMinute))")
        }

        // 6. Dinâmico: o valor sem ele precisa passar nas réguas; senão é dinâmico de fachada.
        var surge: SurgeCheck?
        let totalKm = pickupKm + tripKm
        if m.checkSurge, let amount = offer.surgeAmount, amount > 0.009, amount < fare * 0.8, totalKm > 0 {
            let base = fare - amount
            let basePerKm = base / totalKm
            let basePerMinute = shownMinutes.map { base / $0 }
            let byKm = rule.acceptPerKm * totalKm
            let byMinute = m.minPerMinute > 0 ? (shownMinutes.map { m.minPerMinute * $0 } ?? 0) : 0
            let minimumBase = intercityOK ? min(base, zone.minimumFare ?? base) : max(byKm, byMinute)
            let real = base >= minimumBase - eps
            let extra = max(0, min(amount, fare - minimumBase))
            surge = SurgeCheck(amount: amount, baseFare: base, basePerKm: basePerKm, basePerMinute: basePerMinute,
                               minimumBase: minimumBase, fairFare: minimumBase + amount, real: real, extraGain: real ? amount : extra)
            if !real && refusals.isEmpty {
                let what = [Br.perKm(basePerKm), basePerMinute.map { "\(Br.money($0))/min" }].compactMap { $0 }.joined(separator: " · ")
                cautions.append("dinâmico de fachada: sem os \(Br.money(amount)) de dinâmico seria \(Br.money(base)) (\(what)); "
                                + "o justo com dinâmico seria \(Br.money(minimumBase + amount))")
                shortCautions.append("Dinâmico de fachada: sem ele \(Br.money(base)) · justo \(Br.money(minimumBase + amount))")
            }
        }

        // 7. Hora
        if let perHour = r.revenuePerHour {
            if perHour < m.hourFloor - eps {
                refusals.append("\(Br.perHour(perHour)) abaixo do piso de \(Br.perHour(m.hourFloor))")
                shortRefusals.append("Hora baixa: \(Br.decimal(perHour, 0)) · piso \(Br.decimal(m.hourFloor, 0))")
            } else if perHour < m.hourIdeal - eps {
                cautions.append("\(Br.perHour(perHour)) abaixo do ideal de \(Br.perHour(m.hourIdeal))")
                shortCautions.append("Hora abaixo do ideal: \(Br.decimal(perHour, 0)) · ideal \(Br.decimal(m.hourIdeal, 0))")
            }
        }

        var classification: Classification = !refusals.isEmpty ? .red : (cautions.isEmpty ? .green : .yellow)
        var promoted = false
        let fakeSurge = surge.map { !$0.real } ?? false
        // Zona quente libera o amarelo, menos o dinâmico de fachada (aí o motorista precisa decidir).
        if classification == .yellow, zone.kind == .hot, !fakeSurge {
            classification = .green
            promoted = true
        }

        let numbers = DecisionEngine.joinPt([Br.perKm(perKm), r.revenuePerHour.map { Br.perHour($0) },
                                             perMinute.map { "\(Br.money($0))/min" }].compactMap { $0 })
        let headline: String
        switch classification {
        case .red:
            headline = "Recusar: \(DecisionEngine.joinPt(Array(refusals.prefix(2))))."
        case .yellow:
            headline = "Avaliar: \(DecisionEngine.joinPt(Array(cautions.prefix(2))))."
        default:
            if promoted {
                headline = "Aceitar: \(numbers). Zona quente (\(zone.name ?? "destino")) libera a faixa amarela."
            } else if intercityOK {
                headline = "Aceitar: \(zone.name ?? "intermunicipal") paga \(Br.money(fare)), acima do mínimo de \(Br.money(zone.minimumFare))."
            } else {
                headline = "Aceitar: \(numbers)."
            }
        }
        var finalHeadline = headline
        if let surge, surge.real, classification != .red {
            finalHeadline += " Dinâmico real: os \(Br.money(surge.amount)) são lucro a mais."
        }
        if fakeSurge, alert == nil { alert = "Dinâmico de fachada" }

        let required = zone.kind == .periphery ? max(rule.acceptPerKm, m.zones.peripheryMinPerKm)
            : (zone.kind == .hot ? rule.yellowPerKm : rule.acceptPerKm)
        return MatrixVerdict(classification: classification, rideClass: cls, zone: zone, pickupLimitKm: pickupLimit,
                             requiredPerKm: required, refusals: refusals, cautions: cautions,
                             shortRefusals: shortRefusals, shortCautions: shortCautions, alert: alert, headline: finalHeadline,
                             perMinute: perMinute, surge: surge)
    }
}
