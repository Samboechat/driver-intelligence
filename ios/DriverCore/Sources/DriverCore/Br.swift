import Foundation

/// Formatação pt-BR (vírgula decimal, ponto de milhar) — independente do idioma do aparelho.
public enum Br {
    public static let dash = "—"

    public static func decimal(_ v: Double?, _ digits: Int = 2) -> String {
        guard let v, v.isFinite else { return dash }
        let neg = v < 0 && abs(v) >= 0.5 * pow(10, Double(-digits))
        let s = String(format: "%.\(digits)f", abs(v))
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        var intPart = String(parts[0])
        var grouped = ""
        while intPart.count > 3 {
            grouped = "." + intPart.suffix(3) + grouped
            intPart = String(intPart.dropLast(3))
        }
        grouped = intPart + grouped
        let out = parts.count > 1 ? grouped + "," + parts[1] : grouped
        return neg ? "−" + out : out
    }

    public static func money(_ v: Double?) -> String {
        guard let v, v.isFinite else { return dash }
        let d = decimal(abs(v))
        return v < -0.004 ? "−R$ \(d)" : "R$ \(d)"
    }

    public static func perKm(_ v: Double?) -> String { v == nil ? dash : "\(money(v))/km" }
    public static func perHour(_ v: Double?) -> String { v == nil ? dash : "\(money(v))/h" }

    public static func km(_ v: Double?, _ digits: Int = 1) -> String {
        guard let v, v.isFinite else { return dash }
        return "\(decimal(v, digits)) km"
    }

    public static func minutes(_ v: Double?) -> String {
        guard let v, v.isFinite else { return dash }
        let total = Int(v.rounded())
        if total < 60 { return "\(total) min" }
        let h = total / 60, m = total % 60
        return m == 0 ? "\(h) h" : String(format: "%d h %02d min", h, m)
    }

    /// Endereço lido em várias linhas → uma linha só.
    public static func oneLine(_ s: String?) -> String? {
        guard let s else { return nil }
        let parts = s.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    public static func percent(_ f: Double?) -> String {
        guard let f, f.isFinite else { return dash }
        return "\(Int((f * 100).rounded()))%"
    }
}
