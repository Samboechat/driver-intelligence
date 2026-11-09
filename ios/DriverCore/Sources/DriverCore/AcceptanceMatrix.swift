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

    public init(
        costPerKm: Double = 0.50, hourFloor: Double = 42, hourIdeal: Double = 54,
        comfort: CategoryRule = CategoryRule(acceptPerKm: 2.30, yellowPerKm: 2.00, pickupShortKm: 5, pickupLongKm: 8, minRating: 4.80),
        standard: CategoryRule = CategoryRule(acceptPerKm: 2.10, yellowPerKm: 1.85, pickupShortKm: 3, pickupLongKm: 6, minRating: 4.85),
        shortTripKm: Double = 5, longTripKm: Double = 20, zones: ZoneConfig = .sorocaba
    ) {
        self.costPerKm = costPerKm
        self.hourFloor = hourFloor
        self.hourIdeal = hourIdeal
        self.comfort = comfort
        self.standard = standard
        self.shortTripKm = shortTripKm
        self.longTripKm = longTripKm
        self.zones = zones
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
    public var alert: String?
    public var headline: String

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
 *  - destino de periferia pagando menos que o mínimo de periferia;
 *  - destino intermunicipal pagando menos que o mínimo da cidade.
 * Amarelo: R$/km na faixa amarela, ou R$/h entre o piso e o ideal.
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
        var alert: String?

        // 1. Zona
        switch zone.kind {
        case .intercity:
            if let minFare = zone.minimumFare, fare < minFare - eps {
                refusals.append("\(zone.name ?? "intermunicipal") exige \(Br.money(minFare)) (volta vazia); paga \(Br.money(fare))")
            }
            alert = "Intermunicipal: volta vazia"
        case .periphery:
            if perKm < m.zones.peripheryMinPerKm - eps {
                refusals.append("periferia exige \(Br.perKm(m.zones.peripheryMinPerKm)); paga \(Br.perKm(perKm))")
            }
            alert = m.zones.peripheryAlert
        case .hot, .neutral:
            break
        }

        // 2. R$/km da categoria (não se aplica ao intermunicipal que atingiu o mínimo)
        if !intercityOK {
            if perKm < rule.yellowPerKm - eps {
                refusals.append("\(Br.perKm(perKm)) abaixo de \(Br.perKm(rule.yellowPerKm)) (\(cls.label))")
            } else if perKm < rule.acceptPerKm - eps {
                cautions.append("\(Br.perKm(perKm)) na faixa amarela (\(cls.label) aceita a partir de \(Br.perKm(rule.acceptPerKm)))")
            }
        }

        // 3. Busca
        if pickupKm > pickupLimit + eps {
            refusals.append("busca de \(Br.km(pickupKm)) acima do limite de \(Br.km(pickupLimit))")
        }

        // 4. Nota
        if let rating = offer.passengerRating, rating < rule.minRating - eps {
            refusals.append("nota \(Br.decimal(rating)) abaixo de \(Br.decimal(rule.minRating))")
        }

        // 5. Hora
        if let perHour = r.revenuePerHour {
            if perHour < m.hourFloor - eps {
                refusals.append("\(Br.perHour(perHour)) abaixo do piso de \(Br.perHour(m.hourFloor))")
            } else if perHour < m.hourIdeal - eps {
                cautions.append("\(Br.perHour(perHour)) abaixo do ideal de \(Br.perHour(m.hourIdeal))")
            }
        }

        var classification: Classification = !refusals.isEmpty ? .red : (cautions.isEmpty ? .green : .yellow)
        var promoted = false
        if classification == .yellow, zone.kind == .hot {
            classification = .green
            promoted = true
        }

        let numbers = DecisionEngine.joinPt([Br.perKm(perKm), r.revenuePerHour.map { Br.perHour($0) }].compactMap { $0 })
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

        let required = zone.kind == .periphery ? max(rule.acceptPerKm, m.zones.peripheryMinPerKm)
            : (zone.kind == .hot ? rule.yellowPerKm : rule.acceptPerKm)
        return MatrixVerdict(classification: classification, rideClass: cls, zone: zone, pickupLimitKm: pickupLimit,
                             requiredPerKm: required, refusals: refusals, cautions: cautions, alert: alert, headline: headline)
    }
}
