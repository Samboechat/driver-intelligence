import SwiftUI
import UserNotifications

@main
struct DriverIntelligenceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Palette.brand)
        }
    }
}

/// Mostra as notificações também com o app aberto (para o teste).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            HomeView().tabItem { Label("Início", systemImage: "bolt.fill") }
            SimulatorView().tabItem { Label("Simular", systemImage: "function") }
            HistoryView().tabItem { Label("Histórico", systemImage: "clock.arrow.circlepath") }
            SettingsView().tabItem { Label("Ajustes", systemImage: "slider.horizontal.3") }
        }
    }
}

enum Palette {
    static let brand = Color(red: 0.56, green: 0.64, blue: 1.0)
    static let positive = Color(red: 0.18, green: 0.82, blue: 0.50)
    static let warning = Color(red: 0.95, green: 0.76, blue: 0.31)
    static let negative = Color(red: 1.0, green: 0.36, blue: 0.36)
    static let neutral = Color(red: 0.54, green: 0.58, blue: 0.65)
    static let surface = Color(red: 0.07, green: 0.09, blue: 0.11)
    static let background = Color(red: 0.04, green: 0.05, blue: 0.06)
}
