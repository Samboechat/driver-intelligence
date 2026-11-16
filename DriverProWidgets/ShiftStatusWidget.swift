import AppIntents
import SwiftUI
import WidgetKit

struct ShiftEntry: TimelineEntry {
    let date: Date
    let state: SharedShiftState
}

struct ShiftTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShiftEntry {
        ShiftEntry(date: Date(), state: SharedShiftState())
    }

    func getSnapshot(in context: Context, completion: @escaping (ShiftEntry) -> Void) {
        completion(ShiftEntry(date: Date(), state: SharedShiftState.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShiftEntry>) -> Void) {
        let entry = ShiftEntry(date: Date(), state: SharedShiftState.load())
        let refresh = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

/// Widget pequeno/médio: status do turno, lucro líquido do dia e botão de iniciar/pausar.
struct ShiftStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShiftStatusWidget", provider: ShiftTimelineProvider()) { entry in
            ShiftWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("Turno DriverPro")
        .description("Inicie ou pause o turno e veja o lucro líquido do dia.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ShiftWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShiftEntry

    private var state: SharedShiftState { entry.state }

    private var statusText: String {
        switch state.status {
        case .idle: return "Turno parado"
        case .running: return "Rodando"
        case .paused: return "Pausado"
        }
    }

    private var statusColor: Color {
        switch state.status {
        case .idle: return Theme.muted
        case .running: return Theme.accent
        case .paused: return Theme.warning
        }
    }

    private var buttonTitle: String {
        switch state.status {
        case .idle: return "Iniciar"
        case .running: return "Pausar"
        case .paused: return "Retomar"
        }
    }

    private var buttonIcon: String {
        state.status == .running ? "pause.fill" : "play.fill"
    }

    var body: some View {
        if family == .systemMedium {
            medium
        } else {
            small
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
            Spacer(minLength: 0)
        }
    }

    private var timer: some View {
        Group {
            if state.status == .running {
                Text(state.timerReference, style: .timer)
            } else {
                Text(Fmt.clock(state.activeSeconds))
            }
        }
        .font(.title2.weight(.bold))
        .monospacedDigit()
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var profit: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Lucro líquido hoje")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
            Text(Fmt.money(state.netToday, hidden: state.privacy))
                .font(.headline.weight(.bold))
                .foregroundStyle(state.netToday >= 0 ? Theme.accent : Theme.danger)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var toggleButton: some View {
        Button(intent: ToggleShiftIntent()) {
            Label(buttonTitle, systemImage: buttonIcon)
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(state.status == .running ? Theme.warning : Theme.accent)
        .foregroundStyle(.black)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            timer
            profit
            Spacer(minLength: 0)
            toggleButton
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                header
                timer
                Text(Fmt.km(state.km))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                toggleButton
            }
            VStack(alignment: .leading, spacing: 8) {
                profit
                VStack(alignment: .leading, spacing: 0) {
                    Text("Faturado hoje")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                    Text(Fmt.money(state.grossToday, hidden: state.privacy))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Meta do dia")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                    Text(Fmt.money(state.goalToday, hidden: state.privacy))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
