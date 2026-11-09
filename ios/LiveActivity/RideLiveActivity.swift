import ActivityKit
import SwiftUI
import WidgetKit

/// Widget da Atividade ao Vivo: Dynamic Island e tela bloqueada.
/// "Buscando corridas…" enquanto a leitura está ligada; ao chegar um chamado, mostra veredito, R$/km e R$/h.
@main
struct DriverLiveBundle: WidgetBundle {
    var body: some Widget {
        RideLiveActivity()
    }
}

struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.phase == .offer ? "R$/km" : "Leitura")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(s.phase == .offer ? LiveFormat.decimal(s.perKm) : "Ativa")
                            .font(.title3.bold().monospacedDigit())
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(s.phase == .offer ? "R$/h" : "Chamados")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(s.phase == .offer ? LiveFormat.decimal(s.perHour, 0) : "\(s.offersToday)")
                            .font(.title3.bold().monospacedDigit())
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(s.verdict)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(LiveFormat.color(s.classification))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 2) {
                        if s.phase == .offer {
                            Text([LiveFormat.money(s.fare), s.category].compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline.monospacedDigit())
                        }
                        if let alert = s.alert {
                            Text("⚠️ \(alert)").font(.caption.weight(.semibold)).foregroundStyle(.yellow).lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: s.phase == .offer ? LiveFormat.symbol(s.classification) : "dot.radiowaves.left.and.right")
                    .foregroundStyle(LiveFormat.color(s.classification))
            } compactTrailing: {
                Text(s.phase == .offer ? LiveFormat.decimal(s.perKm) : "\(s.offersToday)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(LiveFormat.color(s.classification))
            } minimal: {
                Image(systemName: s.phase == .offer ? LiveFormat.symbol(s.classification) : "dot.radiowaves.left.and.right")
                    .foregroundStyle(LiveFormat.color(s.classification))
            }
            .keylineTint(LiveFormat.color(s.classification))
        }
    }
}

private struct LockScreenView: View {
    var state: RideActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.phase == .offer ? LiveFormat.symbol(state.classification) : "dot.radiowaves.left.and.right")
                .font(.title)
                .foregroundStyle(LiveFormat.color(state.classification))
            VStack(alignment: .leading, spacing: 2) {
                Text(state.verdict).font(.headline.weight(.heavy)).foregroundStyle(LiveFormat.color(state.classification))
                if state.phase == .offer {
                    Text([LiveFormat.money(state.fare), state.category].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.white)
                } else {
                    Text("\(state.offersToday) chamado(s) analisado(s)").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
                if let alert = state.alert {
                    Text("⚠️ \(alert)").font(.caption.weight(.semibold)).foregroundStyle(.yellow)
                }
            }
            Spacer()
            if state.phase == .offer {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(LiveFormat.decimal(state.perKm))/km").font(.headline.monospacedDigit()).foregroundStyle(.white)
                    Text("\(LiveFormat.decimal(state.perHour, 0))/h").font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(16)
    }
}

/// Formatação mínima (o widget não carrega o núcleo, para ficar leve).
private enum LiveFormat {
    static func decimal(_ v: Double?, _ digits: Int = 2) -> String {
        guard let v, v.isFinite else { return "—" }
        return String(format: "%.\(digits)f", v).replacingOccurrences(of: ".", with: ",")
    }

    static func money(_ v: Double?) -> String? {
        guard let v, v.isFinite else { return nil }
        return "R$ " + decimal(v)
    }

    static func color(_ classification: String) -> Color {
        switch classification {
        case "green": return Color(red: 0.18, green: 0.82, blue: 0.50)
        case "yellow": return Color(red: 0.95, green: 0.76, blue: 0.31)
        case "red": return Color(red: 1.0, green: 0.36, blue: 0.36)
        default: return Color(red: 0.56, green: 0.64, blue: 1.0)
        }
    }

    static func symbol(_ classification: String) -> String {
        switch classification {
        case "green": return "checkmark.circle.fill"
        case "yellow": return "exclamationmark.circle.fill"
        case "red": return "xmark.circle.fill"
        default: return "questionmark.circle.fill"
        }
    }
}
