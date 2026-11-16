import CoreLocation
import Foundation
import SwiftData

/// Despesa de rua lançada durante o turno.
@Model
final class Expense {
    var id: UUID = UUID()
    var date: Date = Date()
    var categoryRaw: String = ExpenseCategory.other.rawValue
    var amount: Double = 0
    var note: String = ""

    init(date: Date = Date(), category: ExpenseCategory, amount: Double, note: String = "") {
        self.id = UUID()
        self.date = date
        self.categoryRaw = category.rawValue
        self.amount = amount
        self.note = note
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

/// Abastecimento.
@Model
final class FuelEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var fuelRaw: String = FuelType.ethanol.rawValue
    var liters: Double = 0
    var totalPaid: Double = 0
    var odometer: Double = 0
    var fullTank: Bool = true

    init(date: Date = Date(), fuel: FuelType, liters: Double, totalPaid: Double, odometer: Double, fullTank: Bool) {
        self.id = UUID()
        self.date = date
        self.fuelRaw = fuel.rawValue
        self.liters = liters
        self.totalPaid = totalPaid
        self.odometer = odometer
        self.fullTank = fullTank
    }

    var fuel: FuelType {
        get { FuelType(rawValue: fuelRaw) ?? .ethanol }
        set { fuelRaw = newValue.rawValue }
    }

    var pricePerLiter: Double { liters > 0 ? totalPaid / liters : 0 }
}

/// Retirada do cofre de manutenção ou do banco de folga.
@Model
final class VaultMovement {
    var id: UUID = UUID()
    var date: Date = Date()
    var kindRaw: String = VaultKind.maintenance.rawValue
    /// Valor retirado (positivo).
    var amount: Double = 0
    var note: String = ""

    init(date: Date = Date(), kind: VaultKind, amount: Double, note: String) {
        self.id = UUID()
        self.date = date
        self.kindRaw = kind.rawValue
        self.amount = amount
        self.note = note
    }

    var kind: VaultKind { VaultKind(rawValue: kindRaw) ?? .maintenance }
}

/// Dia de folga remunerada coberto pelo banco de folga.
@Model
final class DayOff {
    var id: UUID = UUID()
    var day: Date = Date()
    var coveredCost: Double = 0

    init(day: Date, coveredCost: Double) {
        self.id = UUID()
        self.day = Calendar.br.startOfDay(for: day)
        self.coveredCost = coveredCost
    }
}

/// Região marcada pelo motorista como de baixa liquidez (retorno vazio).
@Model
final class LowLiquidityZone {
    var id: UUID = UUID()
    var name: String = ""
    var lat: Double = 0
    var lon: Double = 0
    var radius: Double = 800
    var isEnabled: Bool = true

    init(name: String, lat: Double, lon: Double, radius: Double) {
        self.id = UUID()
        self.name = name
        self.lat = lat
        self.lon = lon
        self.radius = radius
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// Bloco do cronograma semanal.
@Model
final class ScheduleBlock {
    var id: UUID = UUID()
    /// 1 = domingo … 7 = sábado (padrão do Calendar).
    var weekday: Int = 2
    var startMinute: Int = 0
    /// Se for menor ou igual ao início, o bloco atravessa a meia-noite.
    var endMinute: Int = 0
    var title: String = ""
    var focus: String = ""
    var kindRaw: String = BlockKind.work.rawValue
    var isEnabled: Bool = true

    init(weekday: Int, startMinute: Int, endMinute: Int, title: String, focus: String, kind: BlockKind, isEnabled: Bool = true) {
        self.id = UUID()
        self.weekday = weekday
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.title = title
        self.focus = focus
        self.kindRaw = kind.rawValue
        self.isEnabled = isEnabled
    }

    var kind: BlockKind {
        get { BlockKind(rawValue: kindRaw) ?? .work }
        set { kindRaw = newValue.rawValue }
    }

    var durationMinutes: Int {
        endMinute > startMinute ? endMinute - startMinute : endMinute + 1440 - startMinute
    }

    var durationHours: Double { Double(durationMinutes) / 60 }

    var timeLabel: String {
        "\(Fmt.minuteOfDay(startMinute)) às \(Fmt.minuteOfDay(endMinute))"
    }

    /// Conta para horas planejadas (trabalho ou janela extra ativada).
    var countsAsWork: Bool { isEnabled && kind != .rest }

    /// Intervalo concreto do bloco em um dia (início do dia) específico.
    func interval(onDay day: Date) -> DateInterval {
        let start = day.addingTimeInterval(Double(startMinute) * 60)
        return DateInterval(start: start, duration: Double(durationMinutes) * 60)
    }
}
