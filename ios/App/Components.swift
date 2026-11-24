import SwiftUI
import DriverCore

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.08)))
    }
}

struct Banner: View {
    var text: String
    var color: Color
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 6)
            Text(text).font(.footnote)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.35)))
    }
}

struct Stat: View {
    var title: String
    var value: String
    var color: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StepRow: View {
    var number: Int
    var title: String
    var detail: String
    var done: Bool
    var action: (String, () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(done ? Palette.positive.opacity(0.2) : Palette.brand.opacity(0.18)).frame(width: 28, height: 28)
                    if done {
                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(Palette.positive)
                    } else {
                        Text("\(number)").font(.subheadline.bold()).foregroundStyle(Palette.brand)
                    }
                }
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
            }
            Text(detail).font(.footnote).foregroundStyle(.secondary)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

extension Classification {
    var color: Color {
        switch self {
        case .green: return Palette.positive
        case .yellow: return Palette.warning
        case .red: return Palette.negative
        case .gray: return Palette.neutral
        }
    }
}

struct Pill: View {
    var text: String
    var color: Color
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.caption2.weight(.bold)).tracking(0.6)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.16), in: Capsule())
    }
}

struct OfferRow: View {
    var record: OfferRecord
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(record.cls.color).frame(width: 4, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(record.verdict ?? record.cls.shortLabel)
                        .font(.caption.weight(.heavy)).foregroundStyle(record.cls.color)
                    Text(Br.money(record.fare)).font(.headline.monospacedDigit())
                }
                Text(record.reasons?.first
                     ?? [record.category, Br.km(record.totalKm), Br.minutes(record.realisticMin ?? record.totalMin)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(record.revenuePerKm.map { "\(Br.decimal($0))/km" } ?? "—").font(.subheadline.monospacedDigit()).foregroundStyle(record.cls.color)
                HStack(spacing: 4) {
                    if record.surge != nil {
                        Image(systemName: "bolt.fill").font(.caption2)
                            .foregroundStyle(record.surgeReal == true ? Palette.positive : Palette.warning)
                    }
                    if record.alert != nil { Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(Palette.warning) }
                    if record.screenshot != nil { Image(systemName: "photo").font(.caption2) }
                    if let r = record.result { Text(r.label).font(.caption2.weight(.semibold)) }
                    Text(record.date, style: .time).font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// Campo numérico que aceita vírgula ou ponto.
struct NumberField: View {
    var title: String
    @Binding var value: Double?
    var suffix: String = ""
    @State private var text = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
                .onChange(of: text) { new in value = NumberNormalizer.parse(new) }
            if !suffix.isEmpty { Text(suffix).foregroundStyle(.secondary) }
        }
        .onAppear { text = value.map { Br.decimal($0, 2) } ?? "" }
    }
}

extension Binding where Value == Double {
    /// Adapta um Double obrigatório para o NumberField (mantém o valor anterior se apagar).
    var optional: Binding<Double?> {
        Binding<Double?>(get: { wrappedValue }, set: { if let v = $0 { wrappedValue = v } })
    }
}


// MARK: - Dinâmico

/**
 * Mostra se o dinâmico é ganho de verdade: a barra é o valor da corrida dividido em "sem dinâmico" e "dinâmico",
 * e o traço marca o mínimo que a corrida deveria pagar SEM dinâmico. Se a parte cinza não alcança o traço,
 * o dinâmico só está completando uma tarifa baixa (dinâmico de fachada).
 */
struct SurgeBox: View {
    var amount: Double
    var base: Double
    var basePerKm: Double?
    var basePerMinute: Double?
    var fair: Double?
    var real: Bool

    private var minimumBase: Double? { fair.map { $0 - amount } }
    private var color: Color { real ? Palette.positive : Palette.warning }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Dinâmico +\(Br.money(amount))", systemImage: "bolt.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.warning)
                Spacer()
                Text(real ? "REAL" : "DE FACHADA")
                    .font(.caption.weight(.heavy))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(color.opacity(0.2)))
                    .foregroundStyle(color)
            }
            bar.frame(height: 14)
            HStack(spacing: 12) {
                legend(Color.gray.opacity(0.6), "Sem dinâmico \(Br.money(base))")
                legend(Palette.warning, "Dinâmico \(Br.money(amount))")
            }
            Text([basePerKm.map { "Sem ele: \(Br.decimal($0))/km" }, basePerMinute.map { "\(Br.money($0))/min" }]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            if real {
                Text("O valor sem dinâmico já paga o seu piso. Os \(Br.money(amount)) são lucro a mais.")
                    .font(.footnote.weight(.medium)).foregroundStyle(Palette.positive)
            } else if let fair, let minimumBase {
                Text("Sem o dinâmico a corrida ficaria abaixo do seu mínimo (\(Br.money(minimumBase))). "
                     + "Com dinâmico de verdade ela pagaria \(Br.money(fair)) — faltam \(Br.money(max(0, fair - base - amount))).")
                    .font(.footnote.weight(.medium)).foregroundStyle(Palette.warning)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.warning.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.4), lineWidth: 1))
    }

    private var bar: some View {
        GeometryReader { geo in
            let total = max(base + amount, fair ?? 0, 0.01)
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.15))
                HStack(spacing: 0) {
                    Rectangle().fill(Color.gray.opacity(0.6)).frame(width: w * base / total)
                    Rectangle().fill(Palette.warning).frame(width: w * amount / total)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                if let minimumBase {
                    Rectangle().fill(Color.primary).frame(width: 2, height: geo.size.height + 6)
                        .offset(x: min(w - 2, w * minimumBase / total), y: 0)
                }
            }
        }
    }

    private func legend(_ c: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10)
            Text(text).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

extension OfferRecord {
    /// Cartão do dinâmico, quando o chamado mostrou um.
    @ViewBuilder var surgeBox: some View {
        if let surge, let surgeBase {
            SurgeBox(amount: surge, base: surgeBase, basePerKm: surgeBasePerKm, basePerMinute: surgeBasePerMinute,
                     fair: surgeFair, real: surgeReal ?? false)
        }
    }
}
