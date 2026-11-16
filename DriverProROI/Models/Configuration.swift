import Foundation
import SwiftData

/// Perfil híbrido do veículo: alugado ou próprio.
@Model
final class VehicleProfile {
    var name: String = "Meu carro"
    var modeRaw: String = VehicleMode.rented.rawValue

    // Carro alugado
    var rentAmount: Double = 650
    var rentPeriodRaw: String = RentPeriod.weekly.rawValue
    /// Franquia de km por período do contrato (0 = km livre).
    var franchiseKm: Double = 1500
    var excessFeePerKm: Double = 0.50

    // Carro próprio (valores anuais)
    var ipvaAnnual: Double = 0
    var insuranceAnnual: Double = 0
    var licensingAnnual: Double = 0
    var fipeValue: Double = 0
    /// Depreciação anual estimada sobre a FIPE (%).
    var depreciationPct: Double = 10
    var financingMonthly: Double = 0

    // Consumo e preços de referência (usados até existirem abastecimentos reais)
    var kmPerLEthanol: Double = 7.5
    var kmPerLGasoline: Double = 10.5
    var priceEthanol: Double = 4.19
    var priceGasoline: Double = 6.19

    init() {}

    var mode: VehicleMode {
        get { VehicleMode(rawValue: modeRaw) ?? .rented }
        set { modeRaw = newValue.rawValue }
    }

    var rentPeriod: RentPeriod {
        get { RentPeriod(rawValue: rentPeriodRaw) ?? .weekly }
        set { rentPeriodRaw = newValue.rawValue }
    }

    var annualOwnedCost: Double {
        ipvaAnnual + insuranceAnnual + licensingAnnual + fipeValue * depreciationPct / 100 + financingMonthly * 12
    }

    /// Custo fixo por dia corrido.
    var dailyFixedCost: Double {
        switch mode {
        case .rented: return rentAmount / rentPeriod.days
        case .owned: return annualOwnedCost / 365
        }
    }
}

/// Metas, cofre virtual e alertas.
@Model
final class AppSettings {
    /// Piso de R$/km bruto do semáforo.
    var minPerKm: Double = 1.85
    /// Piso de R$/hora bruto do semáforo.
    var minPerHour: Double = 55
    /// Faixa amarela: até X% abaixo do piso.
    var yellowMarginPct: Double = 10
    /// Meta semanal de lucro líquido.
    var weeklyNetGoal: Double = 1500

    var vaultModeRaw: String = VaultMode.perKm.rawValue
    var vaultPerKm: Double = 0.10
    var vaultPct: Double = 5
    /// % do excedente diário enviado ao banco de folga.
    var dayOffBankPct: Double = 50

    /// Fator de calibração do GPS frente ao odômetro.
    var gpsCalibration: Double = 1.0

    var hourlyAlertEnabled: Bool = true
    var fatigueAlertEnabled: Bool = true
    var zoneAlertEnabled: Bool = true
    var scheduleRemindersEnabled: Bool = true

    /// Limites de ticket médio para classificar o perfil de corrida.
    var shortTicketLimit: Double = 12
    var longTicketLimit: Double = 22

    init() {}

    var vaultMode: VaultMode {
        get { VaultMode(rawValue: vaultModeRaw) ?? .perKm }
        set { vaultModeRaw = newValue.rawValue }
    }
}
