import Foundation
import SwiftData

// Estruturas Codable do backup local em JSON (espelham os modelos SwiftData).

struct ShiftDTO: Codable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var statusRaw: String
    var activeSeconds: Double
    var pausedSeconds: Double
    var drivingSeconds: Double
    var gpsKm: Double
    var startLat: Double?
    var startLon: Double?
    var endLat: Double?
    var endLon: Double?
    var route: [RoutePoint]
    var pauses: [PauseRecord]
    var entries: [LiveEntry]
    var mergedIntoSummary: Bool

    init(_ model: Shift) {
        id = model.id
        startedAt = model.startedAt
        endedAt = model.endedAt
        statusRaw = model.statusRaw
        activeSeconds = model.activeSeconds
        pausedSeconds = model.pausedSeconds
        drivingSeconds = model.drivingSeconds
        gpsKm = model.gpsKm
        startLat = model.startLat
        startLon = model.startLon
        endLat = model.endLat
        endLon = model.endLon
        route = model.route
        pauses = model.pauses
        entries = model.entries
        mergedIntoSummary = model.mergedIntoSummary
    }

    func makeModel() -> Shift {
        let model = Shift(startedAt: startedAt)
        model.id = id
        model.endedAt = endedAt
        // Turnos abertos no momento do backup são restaurados como encerrados.
        model.statusRaw = ShiftStatus.finished.rawValue
        model.lastResumeAt = nil
        model.pauseStartedAt = nil
        model.activeSeconds = activeSeconds
        model.pausedSeconds = pausedSeconds
        model.drivingSeconds = drivingSeconds
        model.gpsKm = gpsKm
        model.startLat = startLat
        model.startLon = startLon
        model.endLat = endLat
        model.endLon = endLon
        model.route = route
        model.pauses = pauses
        model.entries = entries
        model.mergedIntoSummary = mergedIntoSummary
        return model
    }
}

struct SummaryDTO: Codable {
    var id: UUID
    var day: Date
    var figures: [String: CategoryFigures]
    var tips: Double
    var surge: Double
    var activeHours: Double
    var pausedHours: Double
    var drivingHours: Double
    var gpsKm: Double
    var productiveKm: Double
    var odometerStart: Double
    var odometerEnd: Double
    var fuelCostPerKm: Double
    var manualFuelCost: Double?
    var fixedCost: Double
    var reserveCost: Double
    var isManual: Bool
    var startLat: Double?
    var startLon: Double?
    var endLat: Double?
    var endLon: Double?
    var notes: String

    init(_ model: DailySummary) {
        id = model.id
        day = model.day
        var raw: [String: CategoryFigures] = [:]
        for (category, value) in model.figures {
            raw[category.rawValue] = value
        }
        figures = raw
        tips = model.tips
        surge = model.surge
        activeHours = model.activeHours
        pausedHours = model.pausedHours
        drivingHours = model.drivingHours
        gpsKm = model.gpsKm
        productiveKm = model.productiveKm
        odometerStart = model.odometerStart
        odometerEnd = model.odometerEnd
        fuelCostPerKm = model.fuelCostPerKm
        manualFuelCost = model.manualFuelCost
        fixedCost = model.fixedCost
        reserveCost = model.reserveCost
        isManual = model.isManual
        startLat = model.startLat
        startLon = model.startLon
        endLat = model.endLat
        endLon = model.endLon
        notes = model.notes
    }

    func makeModel() -> DailySummary {
        let model = DailySummary(day: day)
        model.id = id
        var parsed: [RideCategory: CategoryFigures] = [:]
        for (key, value) in figures {
            if let category = RideCategory(rawValue: key) {
                parsed[category] = value
            }
        }
        model.figures = parsed
        model.tips = tips
        model.surge = surge
        model.activeHours = activeHours
        model.pausedHours = pausedHours
        model.drivingHours = drivingHours
        model.gpsKm = gpsKm
        model.productiveKm = productiveKm
        model.odometerStart = odometerStart
        model.odometerEnd = odometerEnd
        model.fuelCostPerKm = fuelCostPerKm
        model.manualFuelCost = manualFuelCost
        model.fixedCost = fixedCost
        model.reserveCost = reserveCost
        model.isManual = isManual
        model.startLat = startLat
        model.startLon = startLon
        model.endLat = endLat
        model.endLon = endLon
        model.notes = notes
        return model
    }
}

struct ExpenseDTO: Codable {
    var date: Date
    var categoryRaw: String
    var amount: Double
    var note: String

    init(_ model: Expense) {
        date = model.date
        categoryRaw = model.categoryRaw
        amount = model.amount
        note = model.note
    }

    func makeModel() -> Expense {
        Expense(date: date, category: ExpenseCategory(rawValue: categoryRaw) ?? .other, amount: amount, note: note)
    }
}

struct FuelDTO: Codable {
    var date: Date
    var fuelRaw: String
    var liters: Double
    var totalPaid: Double
    var odometer: Double
    var fullTank: Bool

    init(_ model: FuelEntry) {
        date = model.date
        fuelRaw = model.fuelRaw
        liters = model.liters
        totalPaid = model.totalPaid
        odometer = model.odometer
        fullTank = model.fullTank
    }

    func makeModel() -> FuelEntry {
        FuelEntry(date: date, fuel: FuelType(rawValue: fuelRaw) ?? .ethanol, liters: liters,
                  totalPaid: totalPaid, odometer: odometer, fullTank: fullTank)
    }
}

struct MovementDTO: Codable {
    var date: Date
    var kindRaw: String
    var amount: Double
    var note: String

    init(_ model: VaultMovement) {
        date = model.date
        kindRaw = model.kindRaw
        amount = model.amount
        note = model.note
    }

    func makeModel() -> VaultMovement {
        VaultMovement(date: date, kind: VaultKind(rawValue: kindRaw) ?? .maintenance, amount: amount, note: note)
    }
}

struct DayOffDTO: Codable {
    var day: Date
    var coveredCost: Double

    init(_ model: DayOff) {
        day = model.day
        coveredCost = model.coveredCost
    }

    func makeModel() -> DayOff {
        DayOff(day: day, coveredCost: coveredCost)
    }
}

struct ZoneDTO: Codable {
    var name: String
    var lat: Double
    var lon: Double
    var radius: Double
    var isEnabled: Bool

    init(_ model: LowLiquidityZone) {
        name = model.name
        lat = model.lat
        lon = model.lon
        radius = model.radius
        isEnabled = model.isEnabled
    }

    func makeModel() -> LowLiquidityZone {
        let model = LowLiquidityZone(name: name, lat: lat, lon: lon, radius: radius)
        model.isEnabled = isEnabled
        return model
    }
}

struct BlockDTO: Codable {
    var weekday: Int
    var startMinute: Int
    var endMinute: Int
    var title: String
    var focus: String
    var kindRaw: String
    var isEnabled: Bool

    init(_ model: ScheduleBlock) {
        weekday = model.weekday
        startMinute = model.startMinute
        endMinute = model.endMinute
        title = model.title
        focus = model.focus
        kindRaw = model.kindRaw
        isEnabled = model.isEnabled
    }

    func makeModel() -> ScheduleBlock {
        ScheduleBlock(weekday: weekday, startMinute: startMinute, endMinute: endMinute, title: title,
                      focus: focus, kind: BlockKind(rawValue: kindRaw) ?? .work, isEnabled: isEnabled)
    }
}

struct VehicleDTO: Codable {
    var name: String
    var modeRaw: String
    var rentAmount: Double
    var rentPeriodRaw: String
    var franchiseKm: Double
    var excessFeePerKm: Double
    var ipvaAnnual: Double
    var insuranceAnnual: Double
    var licensingAnnual: Double
    var fipeValue: Double
    var depreciationPct: Double
    var financingMonthly: Double
    var kmPerLEthanol: Double
    var kmPerLGasoline: Double
    var priceEthanol: Double
    var priceGasoline: Double

    init(_ model: VehicleProfile) {
        name = model.name
        modeRaw = model.modeRaw
        rentAmount = model.rentAmount
        rentPeriodRaw = model.rentPeriodRaw
        franchiseKm = model.franchiseKm
        excessFeePerKm = model.excessFeePerKm
        ipvaAnnual = model.ipvaAnnual
        insuranceAnnual = model.insuranceAnnual
        licensingAnnual = model.licensingAnnual
        fipeValue = model.fipeValue
        depreciationPct = model.depreciationPct
        financingMonthly = model.financingMonthly
        kmPerLEthanol = model.kmPerLEthanol
        kmPerLGasoline = model.kmPerLGasoline
        priceEthanol = model.priceEthanol
        priceGasoline = model.priceGasoline
    }

    func apply(to model: VehicleProfile) {
        model.name = name
        model.modeRaw = modeRaw
        model.rentAmount = rentAmount
        model.rentPeriodRaw = rentPeriodRaw
        model.franchiseKm = franchiseKm
        model.excessFeePerKm = excessFeePerKm
        model.ipvaAnnual = ipvaAnnual
        model.insuranceAnnual = insuranceAnnual
        model.licensingAnnual = licensingAnnual
        model.fipeValue = fipeValue
        model.depreciationPct = depreciationPct
        model.financingMonthly = financingMonthly
        model.kmPerLEthanol = kmPerLEthanol
        model.kmPerLGasoline = kmPerLGasoline
        model.priceEthanol = priceEthanol
        model.priceGasoline = priceGasoline
    }
}

struct SettingsDTO: Codable {
    var minPerKm: Double
    var minPerHour: Double
    var yellowMarginPct: Double
    var weeklyNetGoal: Double
    var vaultModeRaw: String
    var vaultPerKm: Double
    var vaultPct: Double
    var dayOffBankPct: Double
    var gpsCalibration: Double
    var hourlyAlertEnabled: Bool
    var fatigueAlertEnabled: Bool
    var zoneAlertEnabled: Bool
    var scheduleRemindersEnabled: Bool
    var shortTicketLimit: Double
    var longTicketLimit: Double

    init(_ model: AppSettings) {
        minPerKm = model.minPerKm
        minPerHour = model.minPerHour
        yellowMarginPct = model.yellowMarginPct
        weeklyNetGoal = model.weeklyNetGoal
        vaultModeRaw = model.vaultModeRaw
        vaultPerKm = model.vaultPerKm
        vaultPct = model.vaultPct
        dayOffBankPct = model.dayOffBankPct
        gpsCalibration = model.gpsCalibration
        hourlyAlertEnabled = model.hourlyAlertEnabled
        fatigueAlertEnabled = model.fatigueAlertEnabled
        zoneAlertEnabled = model.zoneAlertEnabled
        scheduleRemindersEnabled = model.scheduleRemindersEnabled
        shortTicketLimit = model.shortTicketLimit
        longTicketLimit = model.longTicketLimit
    }

    func apply(to model: AppSettings) {
        model.minPerKm = minPerKm
        model.minPerHour = minPerHour
        model.yellowMarginPct = yellowMarginPct
        model.weeklyNetGoal = weeklyNetGoal
        model.vaultModeRaw = vaultModeRaw
        model.vaultPerKm = vaultPerKm
        model.vaultPct = vaultPct
        model.dayOffBankPct = dayOffBankPct
        model.gpsCalibration = gpsCalibration
        model.hourlyAlertEnabled = hourlyAlertEnabled
        model.fatigueAlertEnabled = fatigueAlertEnabled
        model.zoneAlertEnabled = zoneAlertEnabled
        model.scheduleRemindersEnabled = scheduleRemindersEnabled
        model.shortTicketLimit = shortTicketLimit
        model.longTicketLimit = longTicketLimit
    }
}

struct BackupFile: Codable {
    var version: Int = 1
    var exportedAt: Date = Date()
    var shifts: [ShiftDTO]
    var summaries: [SummaryDTO]
    var expenses: [ExpenseDTO]
    var fuel: [FuelDTO]
    var movements: [MovementDTO]
    var dayOffs: [DayOffDTO]
    var zones: [ZoneDTO]
    var blocks: [BlockDTO]
    var vehicle: VehicleDTO
    var settings: SettingsDTO
}
