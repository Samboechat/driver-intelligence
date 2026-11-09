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
            RoundedRectangle(cornerRadius: 2).fill(record.cls.color).frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(Br.money(record.fare)).font(.headline.monospacedDigit())
                Text([record.category, Br.km(record.totalKm), Br.minutes(record.realisticMin ?? record.totalMin)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.revenuePerKm.map { "\(Br.decimal($0))/km" } ?? "—").font(.subheadline.monospacedDigit()).foregroundStyle(record.cls.color)
                Text(record.date, style: .time).font(.caption).foregroundStyle(.secondary)
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
