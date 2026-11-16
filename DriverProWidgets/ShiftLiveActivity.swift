import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Live Activity do turno: tela bloqueada + Dynamic Island.
struct ShiftLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShiftActivityAttributes.self) { context in
            ShiftLockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.88))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.isPaused ? "Pausado" : "Rodando")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(context.state.isPaused ? Theme.warning : Theme.accent)
                        ShiftTimerText(state: context.state)
                            .font(.title3.weight(.bold))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Rodado")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                        Text(Fmt.km(context.state.km))
                            .font(.title3.weight(.bold))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        ShiftGoalBar(state: context.state)
                        Button(intent: ToggleShiftIntent()) {
                            Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                                .font(.headline)
                                .frame(width: 44, height: 30)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(context.state.isPaused ? Theme.accent : Theme.warning)
                        .foregroundStyle(.black)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.circle.fill" : "steeringwheel")
                    .foregroundStyle(context.state.isPaused ? Theme.warning : Theme.accent)
            } compactTrailing: {
                ShiftTimerText(state: context.state)
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: 58)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "steeringwheel")
                    .foregroundStyle(context.state.isPaused ? Theme.warning : Theme.accent)
            }
        }
    }
}

struct ShiftTimerText: View {
    let state: ShiftActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isPaused {
                Text(Fmt.clock(state.activeSeconds))
            } else {
                Text(state.timerReference, style: .timer)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .foregroundStyle(.white)
    }
}

struct ShiftGoalBar: View {
    let state: ShiftActivityAttributes.ContentState

    private var progress: Double {
        guard state.goal > 0 else { return 0 }
        return min(1, max(0, state.net / state.goal))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Lucro x meta do dia")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 4)
                Text(state.privacy ? Fmt.hiddenMoney : "\(Fmt.brl(state.net)) de \(Fmt.brl(state.goal))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            ProgressView(value: progress)
                .tint(progress >= 1 ? Theme.accent : Theme.info)
        }
    }
}

struct ShiftLockScreenView: View {
    let state: ShiftActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(state.isPaused ? "Turno pausado" : "Turno rodando",
                          systemImage: state.isPaused ? "pause.circle.fill" : "steeringwheel")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(state.isPaused ? Theme.warning : Theme.accent)
                    ShiftTimerText(state: state)
                        .font(.title.weight(.bold))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Rodado")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    Text(Fmt.km(state.km))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }
                Button(intent: ToggleShiftIntent()) {
                    Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                        .font(.title3)
                        .frame(width: 44, height: 40)
                }
                .buttonStyle(.borderedProminent)
                .tint(state.isPaused ? Theme.accent : Theme.warning)
                .foregroundStyle(.black)
            }
            ShiftGoalBar(state: state)
        }
        .padding(16)
    }
}
