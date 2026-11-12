import Foundation

/// Posição do GPS (só o que o hodômetro precisa).
public struct GeoPoint: Equatable, Codable, Sendable {
    public var lat: Double
    public var lon: Double
    /// Precisão horizontal em metros (negativa = inválida).
    public var accuracy: Double
    /// Segundos desde 1970.
    public var time: TimeInterval

    public init(lat: Double, lon: Double, accuracy: Double, time: TimeInterval) {
        self.lat = lat
        self.lon = lon
        self.accuracy = accuracy
        self.time = time
    }

    /// Distância em metros (haversine).
    public func distance(to o: GeoPoint) -> Double {
        let r = 6_371_000.0
        let p1 = lat * .pi / 180, p2 = o.lat * .pi / 180
        let dp = (o.lat - lat) * .pi / 180, dl = (o.lon - lon) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}

/**
 * Hodômetro por GPS: soma a distância entre posições confiáveis.
 *
 *  - posição imprecisa (pior que `maxAccuracy`) é ignorada;
 *  - carro parado: o GPS "treme" alguns metros; só conta quando o deslocamento passa de `minStep`
 *    e da própria imprecisão das leituras;
 *  - salto impossível (mais rápido que `maxSpeed`) é ignorado; se insistir, a posição nova vira a referência
 *    sem somar nada;
 *  - buraco de sinal (túnel, app fechado): até `maxGap` segundos, soma a linha reta entre os dois pontos
 *    (fica um pouco abaixo do real); além disso, recomeça sem somar.
 */
public struct OdometerTracker: Equatable, Codable, Sendable {
    public private(set) var meters: Double = 0
    public private(set) var last: GeoPoint?
    /// Quando o carro andou pela última vez (segundos desde 1970).
    public private(set) var lastMoveAt: TimeInterval?
    private var rejected = 0

    public var maxAccuracy: Double = 50
    public var minStep: Double = 12
    public var maxSpeed: Double = 56 // m/s ≈ 200 km/h
    public var maxGap: TimeInterval = 1800

    public init() {}

    public var km: Double { meters / 1000 }

    /// Devolve os metros somados por esta posição.
    @discardableResult
    public mutating func add(_ p: GeoPoint) -> Double {
        guard p.accuracy >= 0, p.accuracy <= maxAccuracy, p.lat.isFinite, p.lon.isFinite else { return 0 }
        guard let l = last else {
            last = p
            return 0
        }
        let dt = p.time - l.time
        guard dt > 0 else { return 0 }
        if dt > maxGap {
            last = p
            rejected = 0
            return 0
        }
        let d = l.distance(to: p)
        guard d >= max(minStep, max(p.accuracy, l.accuracy)) else { return 0 }
        if d / dt > maxSpeed {
            rejected += 1
            if rejected >= 3 {
                last = p
                rejected = 0
            }
            return 0
        }
        rejected = 0
        meters += d
        last = p
        lastMoveAt = p.time
        return d
    }
}

/// Entrada da calculadora de rodagem.
public struct DrivingInput: Equatable, Sendable {
    /// Km que o carro rodou de verdade (hodômetro ou GPS).
    public var kmDriven: Double
    /// Km em corrida (busca + viagem). nil = não sei.
    public var paidKm: Double?
    public var revenue: Double
    public var hours: Double?
    public var consumptionKmPerLiter: Double?
    public var fuelPrice: Double?
    /// Manutenção, pneus, óleo, depreciação, seguro… por km.
    public var otherCostPerKm: Double
    /// Custo total por km usado quando falta consumo ou preço do combustível (CPK).
    public var fallbackCostPerKm: Double

    public init(kmDriven: Double, paidKm: Double? = nil, revenue: Double, hours: Double? = nil,
                consumptionKmPerLiter: Double? = nil, fuelPrice: Double? = nil, otherCostPerKm: Double = 0, fallbackCostPerKm: Double = 0.5) {
        self.kmDriven = kmDriven
        self.paidKm = paidKm
        self.revenue = revenue
        self.hours = hours
        self.consumptionKmPerLiter = consumptionKmPerLiter
        self.fuelPrice = fuelPrice
        self.otherCostPerKm = otherCostPerKm
        self.fallbackCostPerKm = fallbackCostPerKm
    }
}

public struct DrivingResult: Equatable, Sendable {
    /// true = combustível calculado pelo consumo; false = custo estimado pelo CPK.
    public var detailed: Bool
    public var fuelLiters: Double?
    public var fuelCost: Double?
    public var otherCost: Double?
    public var totalCost: Double
    /// Custo por km rodado.
    public var costPerKm: Double
    public var profit: Double
    /// Ganho por km rodado (inclui o km morto).
    public var revenuePerKm: Double
    public var profitPerKm: Double
    public var revenuePerHour: Double?
    public var profitPerHour: Double?
    public var deadKm: Double?
    /// Parte dos km rodados sem corrida (0...1).
    public var deadShare: Double?
    /// Ganho por km em corrida (o número que o app do Uber faz parecer).
    public var revenuePerPaidKm: Double?
    /// Quanto cada km em corrida precisa pagar só para cobrir o custo de todos os km rodados.
    public var breakEvenPerPaidKm: Double?
    /// Lucro ÷ ganho (0...1; negativo = prejuízo).
    public var margin: Double?
}

/// Quanto o carro rodou de verdade, quanto custou e quanto sobrou.
public enum DrivingCalculator {
    public static func calculate(_ i: DrivingInput) -> DrivingResult? {
        guard i.kmDriven > 0, i.kmDriven.isFinite, i.revenue.isFinite, i.revenue >= 0 else { return nil }
        var fuelLiters: Double?, fuelCost: Double?, otherCost: Double?
        let total: Double
        let detailed: Bool
        if let c = i.consumptionKmPerLiter, c > 0, let p = i.fuelPrice, p > 0 {
            let liters = i.kmDriven / c
            fuelLiters = liters
            fuelCost = liters * p
            otherCost = i.kmDriven * max(0, i.otherCostPerKm)
            total = fuelCost! + otherCost!
            detailed = true
        } else {
            total = i.kmDriven * max(0, i.fallbackCostPerKm)
            detailed = false
        }
        let profit = i.revenue - total
        let paid = i.paidKm.flatMap { $0 > 0 ? min($0, i.kmDriven) : nil }
        let hours = i.hours.flatMap { $0 > 0 ? $0 : nil }
        return DrivingResult(
            detailed: detailed, fuelLiters: fuelLiters, fuelCost: fuelCost, otherCost: otherCost,
            totalCost: total, costPerKm: total / i.kmDriven, profit: profit,
            revenuePerKm: i.revenue / i.kmDriven, profitPerKm: profit / i.kmDriven,
            revenuePerHour: hours.map { i.revenue / $0 }, profitPerHour: hours.map { profit / $0 },
            deadKm: paid.map { i.kmDriven - $0 }, deadShare: paid.map { (i.kmDriven - $0) / i.kmDriven },
            revenuePerPaidKm: paid.map { i.revenue / $0 }, breakEvenPerPaidKm: paid.map { total / $0 },
            margin: i.revenue > 0 ? profit / i.revenue : nil
        )
    }

    /// Consumo real: km rodados entre dois abastecimentos ÷ litros que couberam no segundo.
    public static func consumption(km: Double, liters: Double) -> Double? {
        guard km > 0, liters > 0, km.isFinite, liters.isFinite else { return nil }
        return km / liters
    }
}
