import Foundation
import SwiftData

/// Números de uma categoria (UberX, Comfort, 99Pop, Outros) em um dia.
struct CategoryFigures: Codable, Hashable {
    var gross: Double = 0
    var trips: Int = 0
    /// Opcional: horas dedicadas à categoria (0 = não informado).
    var hours: Double = 0
    /// Opcional: km em corrida na categoria (0 = não informado).
    var km: Double = 0
}

/// Fechamento / Resumo Geral Diário.
@Model
final class DailySummary {
    var id: UUID = UUID()
    var day: Date = Date()
    var categoryBlob: Data?
    /// Soma dos ganhos brutos das categorias (desnormalizado para consultas rápidas).
    var categoriesGross: Double = 0
    var totalTrips: Int = 0
    var tips: Double = 0
    /// Tarifa dinâmica + promoções/desafios.
    var surge: Double = 0
    var activeHours: Double = 0
    var pausedHours: Double = 0
    var drivingHours: Double = 0
    var gpsKm: Double = 0
    /// Km em corrida (com passageiro) informados pelo motorista.
    var productiveKm: Double = 0
    var odometerStart: Double = 0
    var odometerEnd: Double = 0
    /// Custo de combustível por km congelado no fechamento.
    var fuelCostPerKm: Double = 0
    /// Valor real gasto com combustível no dia, se o motorista preferir informar.
    var manualFuelCost: Double?
    /// Custo fixo do dia (locação ou rateio do carro próprio) congelado no fechamento.
    var fixedCost: Double = 0
    /// Reserva de manutenção enviada ao cofre virtual.
    var reserveCost: Double = 0
    var isManual: Bool = false
    var startLat: Double?
    var startLon: Double?
    var endLat: Double?
    var endLon: Double?
    var notes: String = ""

    init(day: Date) {
        self.id = UUID()
        self.day = Calendar.br.startOfDay(for: day)
    }

    var figures: [RideCategory: CategoryFigures] {
        get {
            let raw = Blob.decode([String: CategoryFigures].self, from: categoryBlob) ?? [:]
            var result: [RideCategory: CategoryFigures] = [:]
            for category in RideCategory.allCases {
                result[category] = raw[category.rawValue] ?? CategoryFigures()
            }
            return result
        }
        set {
            var raw: [String: CategoryFigures] = [:]
            for (category, value) in newValue {
                raw[category.rawValue] = value
            }
            categoryBlob = Blob.encode(raw)
            categoriesGross = newValue.values.reduce(0) { $0 + $1.gross }
            totalTrips = newValue.values.reduce(0) { $0 + $1.trips }
        }
    }

    var totalGross: Double { categoriesGross + tips + surge }

    var odometerKm: Double {
        odometerStart > 0 && odometerEnd > odometerStart ? odometerEnd - odometerStart : 0
    }

    /// Km usados no cálculo de custos: odômetro (quando auditado) ou GPS.
    var costKm: Double { odometerKm > 0 ? odometerKm : gpsKm }
}
