import Foundation

/// Formatadores pt-BR usados pelo app e pelos widgets.
enum Fmt {
    private static let brlFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static var dateFormatters: [String: DateFormatter] = [:]
    private static let lock = NSLock()

    static let hiddenMoney = "R$ ••••"

    static func brl(_ value: Double) -> String {
        brlFormatter.string(from: NSNumber(value: value)) ?? "R$ 0,00"
    }

    static func money(_ value: Double, hidden: Bool) -> String {
        hidden ? hiddenMoney : brl(value)
    }

    static func rate(_ value: Double, unit: String, hidden: Bool) -> String {
        hidden ? "R$ ••/\(unit)" : "\(brl(value))/\(unit)"
    }

    static func number(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
    }

    static func km(_ value: Double) -> String {
        number(value, digits: 1) + " km"
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// 1:23:45
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// 5h32
    static func hoursMinutes(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%dh%02d", total / 3600, (total % 3600) / 60)
    }

    static func hours(_ hours: Double) -> String {
        hoursMinutes(hours * 3600)
    }

    /// 03:30
    static func minuteOfDay(_ minutes: Int) -> String {
        let normalized = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }

    static func date(_ date: Date, _ format: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        let formatter: DateFormatter
        if let cached = dateFormatters[format] {
            formatter = cached
        } else {
            formatter = DateFormatter()
            formatter.locale = Locale(identifier: "pt_BR")
            formatter.dateFormat = format
            dateFormatters[format] = formatter
        }
        return formatter.string(from: date)
    }
}
