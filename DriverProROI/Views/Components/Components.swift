import SwiftUI

/// Cartão padrão das telas.
struct Card<Content: View>: View {
    private let title: String?
    private let icon: String?
    private let content: Content

    init(_ title: String? = nil, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .foregroundStyle(Theme.accent)
                    }
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }
}

/// Botão grande para toque rápido no suporte do carro.
struct BigButtonStyle: ButtonStyle {
    var color: Color
    var foreground: Color = .black

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.heavy))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                color.opacity(configuration.isPressed ? 0.65 : 1),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
    }
}

struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(
                Theme.cardRaised.opacity(configuration.isPressed ? 0.6 : 1),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var signal: Signal = .neutral
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(signal.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Linha "rótulo …… valor".
struct InfoRow: View {
    let label: String
    let value: String
    var color: Color = .white
    var bold: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(bold ? .body.weight(.bold) : .body)
                .foregroundStyle(bold ? Color.white : Theme.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(bold ? .body.weight(.bold) : .body)
                .monospacedDigit()
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct SignalDot: View {
    let signal: Signal

    var body: some View {
        Circle()
            .fill(signal == .neutral ? Theme.muted : signal.color)
            .frame(width: 12, height: 12)
    }
}

/// Barra horizontal proporcional (classificação de tempo, composição de ganhos).
struct SegmentBar: View {
    let segments: [(value: Double, color: Color)]

    var body: some View {
        GeometryReader { geometry in
            let total = max(segments.reduce(0) { $0 + $1.value }, 0.0001)
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: max(0, geometry.size.width * segment.value / total - 2))
                }
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 4)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }
}

/// Campo numérico decimal com vírgula (R$, km, litros). Atualiza o valor a cada tecla.
struct DecimalField: View {
    let title: String
    @Binding var value: Double
    var suffix: String? = nil
    var digits: Int = 2
    var autoFocus: Bool = false
    var large: Bool = false

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if !title.isEmpty {
                Text(title)
                Spacer(minLength: 8)
            }
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(title.isEmpty ? .center : .trailing)
                .font(large ? .system(size: 44, weight: .bold, design: .rounded) : .body)
                .monospacedDigit()
                .focused($focused)
                .frame(minWidth: 70)
            if let suffix {
                Text(suffix)
                    .foregroundStyle(Theme.muted)
            }
        }
        .onAppear {
            text = DecimalField.format(value, digits: digits)
            if autoFocus { focused = true }
        }
        .onChange(of: text) { _, newText in
            let parsed = DecimalField.parse(newText)
            if parsed != value { value = parsed }
        }
        .onChange(of: value) { _, newValue in
            if DecimalField.parse(text) != newValue {
                text = DecimalField.format(newValue, digits: digits)
            }
        }
    }

    static func parse(_ text: String) -> Double {
        var cleaned = text.trimmingCharacters(in: .whitespaces)
        if cleaned.contains(",") {
            cleaned = cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        return max(0, Double(cleaned) ?? 0)
    }

    static func format(_ value: Double, digits: Int) -> String {
        guard value != 0 else { return "" }
        var formatted = String(format: "%.\(digits)f", value)
        if formatted.contains(".") {
            while formatted.hasSuffix("0") { formatted.removeLast() }
            if formatted.hasSuffix(".") { formatted.removeLast() }
        }
        return formatted.replacingOccurrences(of: ".", with: ",")
    }
}

/// Campo numérico inteiro (viagens, km de odômetro).
struct IntField: View {
    let title: String
    @Binding var value: Int

    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            TextField("0", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(minWidth: 60)
        }
        .onAppear {
            text = value == 0 ? "" : "\(value)"
        }
        .onChange(of: text) { _, newText in
            let parsed = Int(newText.filter { $0.isNumber }) ?? 0
            if parsed != value { value = parsed }
        }
        .onChange(of: value) { _, newValue in
            let current = Int(text.filter { $0.isNumber }) ?? 0
            if current != newValue {
                text = newValue == 0 ? "" : "\(newValue)"
            }
        }
    }
}

/// Botão "Olho Mágico": oculta todos os valores financeiros com 1 toque.
struct PrivacyToolbar: ViewModifier {
    @AppStorage("privacyMode") private var privacy = false

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    privacy.toggle()
                    ShiftManager.shared.refreshShared()
                } label: {
                    Image(systemName: privacy ? "eye.slash.fill" : "eye.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(privacy ? "Mostrar valores" : "Ocultar valores")
            }
        }
    }
}

extension View {
    func privacyToolbar() -> some View {
        modifier(PrivacyToolbar())
    }

    /// Fundo preto das telas em ScrollView.
    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}
