import Foundation

struct FuelInterval: Identifiable {
    let id = UUID()
    let date: Date
    let fuel: FuelType
    let km: Double
    let liters: Double
    var kmPerL: Double { liters > 0 ? km / liters : 0 }
}

/// Calculadora Flex: consumo real (método tanque cheio), custo por km e combustível que compensa.
struct FuelAnalysis {
    private(set) var kmPerL: [FuelType: Double] = [:]
    private(set) var measured: [FuelType: Bool] = [:]
    private(set) var price: [FuelType: Double] = [:]
    private(set) var lastFuel: FuelType?
    private(set) var intervals: [FuelInterval] = []

    init(entries: [FuelEntry], vehicle: VehicleProfile) {
        let sorted = entries.filter { $0.odometer > 0 && $0.liters > 0 }.sorted { $0.odometer < $1.odometer }
        var litersSum: [FuelType: Double] = [:]
        var kmSum: [FuelType: Double] = [:]
        var lastFull: FuelEntry?
        var pendingLiters = 0.0

        for entry in sorted {
            guard let previous = lastFull else {
                if entry.fullTank { lastFull = entry }
                continue
            }
            pendingLiters += entry.liters
            guard entry.fullTank else { continue }
            let km = entry.odometer - previous.odometer
            if km > 0 {
                let ratio = km / pendingLiters
                // Descarta leituras absurdas (erro de digitação de odômetro/litros).
                if ratio > 2 && ratio < 30 {
                    litersSum[previous.fuel, default: 0] += pendingLiters
                    kmSum[previous.fuel, default: 0] += km
                    intervals.append(FuelInterval(date: entry.date, fuel: previous.fuel, km: km, liters: pendingLiters))
                }
            }
            lastFull = entry
            pendingLiters = 0
        }

        for fuel in FuelType.allCases {
            let fallbackEfficiency = fuel == .ethanol ? vehicle.kmPerLEthanol : vehicle.kmPerLGasoline
            if let liters = litersSum[fuel], liters > 0, let km = kmSum[fuel] {
                kmPerL[fuel] = km / liters
                measured[fuel] = true
            } else {
                kmPerL[fuel] = fallbackEfficiency
                measured[fuel] = false
            }
            let latest = entries
                .filter { $0.fuel == fuel && $0.liters > 0 }
                .max { $0.date < $1.date }
            let fallbackPrice = fuel == .ethanol ? vehicle.priceEthanol : vehicle.priceGasoline
            price[fuel] = latest?.pricePerLiter ?? fallbackPrice
        }
        lastFuel = entries.max { $0.date < $1.date }?.fuel
    }

    func efficiency(_ fuel: FuelType) -> Double { kmPerL[fuel] ?? 0 }

    func pricePerLiter(_ fuel: FuelType) -> Double { price[fuel] ?? 0 }

    func isMeasured(_ fuel: FuelType) -> Bool { measured[fuel] ?? false }

    func costPerKm(_ fuel: FuelType) -> Double {
        let value = efficiency(fuel)
        return value > 0 ? pricePerLiter(fuel) / value : 0
    }

    /// Combustível mais barato por km com a eficiência real do carro.
    var recommended: FuelType {
        costPerKm(.ethanol) <= costPerKm(.gasoline) ? .ethanol : .gasoline
    }

    /// Custo por km do combustível que está no tanque (último abastecido) ou do recomendado.
    var currentCostPerKm: Double {
        costPerKm(lastFuel ?? recommended)
    }

    /// Relação real de rendimento etanol/gasolina deste carro (ex.: 0,73).
    var efficiencyRatio: Double {
        let gasoline = efficiency(.gasoline)
        return gasoline > 0 ? efficiency(.ethanol) / gasoline : 0
    }

    /// Relação de preço etanol/gasoline nas bombas.
    var priceRatio: Double {
        let gasoline = pricePerLiter(.gasoline)
        return gasoline > 0 ? pricePerLiter(.ethanol) / gasoline : 0
    }

    /// Preço máximo do etanol para ainda compensar frente à gasolina atual.
    var ethanolBreakEvenPrice: Double {
        pricePerLiter(.gasoline) * efficiencyRatio
    }

    /// Economia por 100 km ao usar o combustível recomendado.
    var savingsPer100Km: Double {
        abs(costPerKm(.ethanol) - costPerKm(.gasoline)) * 100
    }
}
