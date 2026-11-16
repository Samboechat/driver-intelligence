import SwiftData
import SwiftUI

/// Lê o banco via @Query e entrega o motor financeiro pronto para as telas.
struct EngineReader<Content: View>: View {
    @Query(sort: \DailySummary.day) private var summaries: [DailySummary]
    @Query private var expenses: [Expense]
    @Query private var fuelEntries: [FuelEntry]
    @Query private var dayOffs: [DayOff]
    @Query private var movements: [VaultMovement]
    @Query private var blocks: [ScheduleBlock]
    @Query private var vehicles: [VehicleProfile]
    @Query private var settingsList: [AppSettings]

    private let content: (FinanceEngine) -> Content

    init(@ViewBuilder content: @escaping (FinanceEngine) -> Content) {
        self.content = content
    }

    var body: some View {
        if let vehicle = vehicles.first, let settings = settingsList.first {
            content(FinanceEngine(
                summaries: summaries,
                expenses: expenses,
                fuelEntries: fuelEntries,
                vehicle: vehicle,
                settings: settings,
                dayOffs: dayOffs,
                movements: movements,
                workWeekdays: Store.workWeekdays(blocks)
            ))
        } else {
            ProgressView("Preparando dados…")
                .task { Store.bootstrap() }
        }
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        EngineReader { engine in
            TabView {
                NavigationStack {
                    ShiftDashboardView(engine: engine)
                }
                .tabItem { Label("Turno", systemImage: "steeringwheel") }

                NavigationStack {
                    HistoryView(engine: engine)
                }
                .tabItem { Label("Resumos", systemImage: "list.bullet.rectangle.fill") }

                NavigationStack {
                    AnalyticsView(engine: engine)
                }
                .tabItem { Label("Análises", systemImage: "chart.bar.fill") }

                NavigationStack {
                    ScheduleView(engine: engine)
                }
                .tabItem { Label("Cronograma", systemImage: "calendar") }

                NavigationStack {
                    MoreView(engine: engine)
                }
                .tabItem { Label("Mais", systemImage: "square.grid.2x2.fill") }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                ShiftManager.shared.appBecameActive()
            case .background:
                ExportService.autoBackup()
            default:
                break
            }
        }
    }
}
