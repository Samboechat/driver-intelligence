import Foundation
import SwiftUI

extension Calendar {
    /// Calendário brasileiro: semana começa na segunda-feira.
    static let br: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "pt_BR")
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone.autoupdatingCurrent
        return calendar
    }()

    static let weekdayNames = ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"]
    /// Ordem de exibição: segunda → domingo (valores de `Calendar.component(.weekday)`).
    static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    static func weekdayName(_ weekday: Int) -> String {
        weekdayNames[max(0, min(6, weekday - 1))]
    }
}

struct DayRef: Identifiable, Hashable {
    let day: Date
    var id: Date { day }
}

enum ShiftStatus: String, Codable {
    case running, paused, finished
}

enum RideCategory: String, CaseIterable, Identifiable, Codable {
    case uberX, comfort, pop99, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uberX: return "UberX"
        case .comfort: return "Uber Comfort"
        case .pop99: return "99Pop"
        case .other: return "Outros/Particular"
        }
    }

    var short: String {
        switch self {
        case .uberX: return "UberX"
        case .comfort: return "Comfort"
        case .pop99: return "99Pop"
        case .other: return "Outros"
        }
    }

    var color: Color {
        switch self {
        case .uberX: return Color(white: 0.85)
        case .comfort: return Theme.info
        case .pop99: return Theme.warning
        case .other: return Theme.accent
        }
    }
}

enum FuelType: String, CaseIterable, Identifiable, Codable {
    case ethanol, gasoline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ethanol: return "Etanol"
        case .gasoline: return "Gasolina"
        }
    }
}

enum VehicleMode: String, CaseIterable, Identifiable {
    case rented, owned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rented: return "Carro alugado"
        case .owned: return "Carro próprio"
        }
    }
}

enum RentPeriod: String, CaseIterable, Identifiable {
    case weekly, monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: return "Semanal"
        case .monthly: return "Mensal"
        }
    }

    var days: Double {
        switch self {
        case .weekly: return 7
        case .monthly: return 30
        }
    }
}

enum VaultMode: String, CaseIterable, Identifiable {
    case perKm, percent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .perKm: return "R$ por km"
        case .percent: return "% do bruto"
        }
    }
}

enum VaultKind: String {
    case maintenance, dayOff
}

enum ExpenseCategory: String, CaseIterable, Identifiable {
    case food, water, carWash, parking, toll, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: return "Alimentação"
        case .water: return "Água/Balas"
        case .carWash: return "Lava-rápido"
        case .parking: return "Estacionamento"
        case .toll: return "Pedágio"
        case .other: return "Outros"
        }
    }

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .water: return "drop.fill"
        case .carWash: return "sparkles"
        case .parking: return "parkingsign.circle.fill"
        case .toll: return "road.lanes"
        case .other: return "ellipsis.circle.fill"
        }
    }

    /// Valores de 1 toque sugeridos por categoria.
    var quickAmounts: [Double] {
        switch self {
        case .food: return [15, 20, 25, 30, 40, 50]
        case .water: return [5, 10, 15, 20, 30, 40]
        case .carWash: return [20, 30, 40, 50, 60, 80]
        case .parking: return [5, 8, 10, 15, 20, 30]
        case .toll: return [4, 6, 8, 10, 12, 15]
        case .other: return [5, 10, 20, 30, 50, 100]
        }
    }
}

enum BlockKind: String, CaseIterable, Identifiable {
    case work, rest, optional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work: return "Trabalho"
        case .rest: return "Pausa estratégica"
        case .optional: return "Janela extra"
        }
    }

    var color: Color {
        switch self {
        case .work: return Theme.accent
        case .rest: return Theme.muted
        case .optional: return Theme.warning
        }
    }
}

/// Semáforo de meta.
enum Signal {
    case green, yellow, red, neutral

    var color: Color {
        switch self {
        case .green: return Theme.accent
        case .yellow: return Theme.warning
        case .red: return Theme.danger
        case .neutral: return Color.white
        }
    }

    var label: String {
        switch self {
        case .green: return "Acima da meta"
        case .yellow: return "Na margem"
        case .red: return "Abaixo do piso"
        case .neutral: return "Sem dados"
        }
    }
}

/// Serialização simples de estruturas auxiliares guardadas como Data no SwiftData.
enum Blob {
    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
