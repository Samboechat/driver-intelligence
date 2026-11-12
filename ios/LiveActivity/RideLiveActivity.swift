import ActivityKit
import SwiftUI
import WidgetKit

/// Widget da Atividade ao Vivo: Dynamic Island e tela bloqueada.
/// Com um chamado na tela, a ilha mostra R$/km e R$/h na cor do veredito; sem chamado, "Buscando corridas…".
@main
struct DriverLiveBundle: WidgetBundle {
    var body: some Widget {
        RideLiveActivity()
    }
}

struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            LockScreenView(state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            let stale = context.isStale
            let offer = s.phase == .offer && !stale
            let tint = stale ? LiveFormat.color("gray") : LiveFormat.color(s.classification)
            return DynamicIsland {
                // Expandida (a cada chamado, ou ao segurar a ilha).
                DynamicIslandExpandedRegion(.leading) {
                    if offer {
                        BigRate(value: LiveFormat.decimal(s.perKm), unit: "R$/km", color: tint, alignment: .leading)
                            .padding(.leading, 6)
                    } else {
                        Image(systemName: stale ? "moon.zzz.fill" : "dot.radiowaves.left.and.right")
                            .font(.title2).foregroundStyle(tint).padding(.leading, 8)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if offer {
                        BigRate(value: LiveFormat.decimal(s.perHour, 0), unit: "R$/h", color: tint, alignment: .trailing)
                            .padding(.trailing, 6)
                    } else {
                        BigRate(value: "\(s.offersToday)", unit: "chamados", color: .white, alignment: .trailing)
                            .padding(.trailing, 6)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(stale ? "Sem atualização" : (offer ? s.verdict : "Buscando…"))
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 3) {
                        if offer {
                            Text([LiveFormat.money(s.fare), s.category].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                            if let reason = s.reason {
                                Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            if let alert = s.alert {
                                Text("⚠️ \(alert)").font(.caption.weight(.semibold)).foregroundStyle(.yellow).lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        } else {
                            Text(stale ? "Abra o Driver Intelligence para voltar a atualizar." : "Lendo a tela. O próximo chamado aparece aqui.")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
                        }
                    }
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                // Compacta: R$/km de um lado, R$/h do outro.
                if offer {
                    SmallRate(value: LiveFormat.decimal(s.perKm), unit: "/km", color: tint)
                } else {
                    Image(systemName: stale ? "moon.zzz.fill" : "dot.radiowaves.left.and.right").foregroundStyle(tint)
                }
            } compactTrailing: {
                if offer {
                    SmallRate(value: LiveFormat.decimal(s.perHour, 0), unit: "/h", color: tint)
                } else {
                    Text(stale ? "—" : "\(s.offersToday)")
                        .font(.caption.bold().monospacedDigit()).foregroundStyle(tint)
                }
            } minimal: {
                // Mínima (quando o iOS divide a ilha com a gravação de tela ou outro app): os dois números empilhados.
                if offer {
                    VStack(spacing: -2) {
                        Text(LiveFormat.decimal(s.perKm))
                            .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                        Text("\(LiveFormat.decimal(s.perHour, 0))h")
                            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    }
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.6)
                } else {
                    Image(systemName: stale ? "moon.zzz.fill" : "dot.radiowaves.left.and.right").foregroundStyle(tint)
                }
            }
            .keylineTint(tint)
        }
    }
}

/// Número grande com a unidade embaixo (ilha expandida e tela bloqueada).
private struct BigRate: View {
    var value: String
    var unit: String
    var color: Color
    var alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(value)
                .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

/// Número pequeno com a unidade ao lado (ilha compacta).
private struct SmallRate: View {
    var value: String
    var unit: String
    var color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(value).font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
            Text(unit).font(.system(size: 9, weight: .bold, design: .rounded))
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

private struct LockScreenView: View {
    var state: RideActivityAttributes.ContentState
    var stale: Bool

    var body: some View {
        let offer = state.phase == .offer && !stale
        let tint = stale ? LiveFormat.color("gray") : LiveFormat.color(state.classification)
        HStack(spacing: 14) {
            if offer {
                BigRate(value: LiveFormat.decimal(state.perKm), unit: "R$/km", color: tint, alignment: .leading)
            } else {
                Image(systemName: stale ? "moon.zzz.fill" : "dot.radiowaves.left.and.right").font(.title).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(stale ? "Sem atualização" : (offer ? state.verdict : "Buscando corridas…"))
                    .font(.headline.weight(.heavy)).foregroundStyle(tint)
                if offer {
                    Text([LiveFormat.money(state.fare), state.category].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.white)
                    if let reason = state.reason {
                        Text(reason).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                } else {
                    Text(stale ? "Abra o app para voltar a atualizar." : "\(state.offersToday) chamado(s) analisado(s)")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
                if offer, let alert = state.alert {
                    Text("⚠️ \(alert)").font(.caption.weight(.semibold)).foregroundStyle(.yellow).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if offer {
                BigRate(value: LiveFormat.decimal(state.perHour, 0), unit: "R$/h", color: tint, alignment: .trailing)
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
}
