import ActivityKit
import SwiftUI
import WidgetKit

/// Widget da Atividade ao Vivo: Dynamic Island e tela bloqueada.
/// Com um chamado na tela, a ilha mostra R$/km e R$/h na cor do veredito; em corrida, o cronômetro; sem chamado, "Buscando corridas…".
/// No CarPlay (iOS 26) aparece o painel `CarPlayView`, com números grandes.
@main
struct DriverLiveBundle: WidgetBundle {
    var body: some Widget {
        RideLiveActivity()
    }
}

struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            ActivityContentView(state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.88))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            let stale = context.isStale
            let offer = s.phase == .offer && !stale
            let trip = s.phase == .trip && !stale
            let tint = stale ? LiveFormat.color("gray") : LiveFormat.color(s.classification)
            return DynamicIsland {
                // Expandida (a cada chamado, ou ao segurar a ilha).
                DynamicIslandExpandedRegion(.leading) {
                    if offer || trip {
                        BigRate(value: LiveFormat.decimal(s.perKm), unit: "R$/km", color: tint, alignment: .leading)
                            .padding(.leading, 6)
                    } else {
                        Image(systemName: stale ? "moon.zzz.fill" : "dot.radiowaves.left.and.right")
                            .font(.title2).foregroundStyle(tint).padding(.leading, 8)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if offer || trip {
                        BigRate(value: LiveFormat.decimal(s.perHour, 0), unit: "R$/h", color: tint, alignment: .trailing)
                            .padding(.trailing, 6)
                    } else {
                        BigRate(value: "\(s.offersToday)", unit: "chamados", color: .white, alignment: .trailing)
                            .padding(.trailing, 6)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(stale ? "Sem atualização" : (offer || trip ? s.verdict : "Buscando…"))
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 3) {
                        if offer || trip {
                            HStack(spacing: 6) {
                                Text([LiveFormat.money(s.fare), s.category].compactMap { $0 }.joined(separator: " · "))
                                if trip, let start = s.tripStartedAt {
                                    Text("·")
                                    TripTimer(start: start).frame(maxWidth: 70)
                                }
                            }
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
                            if let reason = s.reason {
                                Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            if offer, let alert = s.alert {
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
                // Compacta: R$/km de um lado, R$/h (ou o cronômetro da corrida) do outro.
                if offer {
                    SmallRate(value: LiveFormat.decimal(s.perKm), unit: "/km", color: tint)
                } else if trip {
                    Image(systemName: "car.fill").foregroundStyle(tint)
                } else {
                    Image(systemName: stale ? "moon.zzz.fill" : "dot.radiowaves.left.and.right").foregroundStyle(tint)
                }
            } compactTrailing: {
                if offer {
                    SmallRate(value: LiveFormat.decimal(s.perHour, 0), unit: "/h", color: tint)
                } else if trip, let start = s.tripStartedAt {
                    TripTimer(start: start)
                        .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(tint)
                        .frame(maxWidth: 52)
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
                } else if trip {
                    Image(systemName: "car.fill").foregroundStyle(tint)
                } else {
                    Image(systemName: stale ? "moon.zzz.fill" : "dot.radiowaves.left.and.right").foregroundStyle(tint)
                }
            }
            .keylineTint(tint)
        }
        // CarPlay (e o Apple Watch) usam o tamanho "small". Sem ele, o CarPlay mostra só a ilha compacta, miúda.
        .supplementalActivityFamilies([.small])
    }
}

/// Escolhe o layout pelo lugar onde a atividade aparece.
private struct ActivityContentView: View {
    @Environment(\.activityFamily) private var family
    var state: RideActivityAttributes.ContentState
    var stale: Bool

    var body: some View {
        switch family {
        case .small:
            CarPlayView(state: state, stale: stale)
        default:
            LockScreenView(state: state, stale: stale)
        }
    }
}

/// Cronômetro da corrida (conta sozinho, sem precisar de atualização).
private struct TripTimer: View {
    var start: Date
    var body: some View {
        Text(timerInterval: start...start.addingTimeInterval(8 * 3600), countsDown: false)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

/**
 * Painel do CarPlay: feito para bater o olho dirigindo.
 * Veredito numa faixa colorida, R$/km e R$/h grandes, o resto em uma linha.
 */
private struct CarPlayView: View {
    var state: RideActivityAttributes.ContentState
    var stale: Bool

    var body: some View {
        let offer = state.phase == .offer && !stale
        let trip = state.phase == .trip && !stale
        let tint = stale ? LiveFormat.color("gray") : LiveFormat.color(state.classification)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(stale ? "SEM SINAL" : (offer || trip ? state.verdict.uppercased() : "BUSCANDO"))
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tint))
                Spacer(minLength: 2)
                if trip, let start = state.tripStartedAt {
                    TripTimer(start: start)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: 64, alignment: .trailing)
                } else if let fare = LiveFormat.money(state.fare), offer {
                    Text(fare)
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            if offer || trip {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    CarRate(value: LiveFormat.decimal(state.perKm), unit: "R$/km", color: tint)
                    CarRate(value: LiveFormat.decimal(state.perHour, 0), unit: "R$/h", color: tint)
                }
                Text(footer(trip: trip))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(state.alert != nil && offer ? .yellow : .white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(stale ? "Abra o app no iPhone" : "\(state.offersToday)")
                    .font(.system(size: stale ? 15 : 34, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(stale ? "para voltar a atualizar" : "chamados analisados")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func footer(trip: Bool) -> String {
        if !trip, let alert = state.alert { return "⚠️ " + alert }
        if trip { return [LiveFormat.money(state.fare), state.category, state.reason].compactMap { $0 }.joined(separator: " · ") }
        return [state.category, state.reason].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Número grande do CarPlay.
private struct CarRate: View {
    var value: String
    var unit: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(value)
                .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(unit)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
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
        let offer = (state.phase == .offer || state.phase == .trip) && !stale
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
                    if state.phase == .trip, let start = state.tripStartedAt {
                        TripTimer(start: start).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.leading)
                    }
                    if let reason = state.reason {
                        Text(reason).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                } else {
                    Text(stale ? "Abra o app para voltar a atualizar." : "\(state.offersToday) chamado(s) analisado(s)")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
                if state.phase == .offer, !stale, let alert = state.alert {
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
