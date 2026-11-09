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

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Notifier.registerCategories()
        return true
    }

    /// Mostra as notificações também com o app aberto.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Botões "Aceitei" / "Finalizei" das notificações: repassa para a extensão.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let fp = response.notification.request.content.userInfo["fingerprint"] as? String
        switch response.actionIdentifier {
        case Notifier.acceptAction:
            SharedStore.command = AppCommand(action: .accept, fingerprint: (fp?.isEmpty ?? true) ? nil : fp)
            if let fp, !fp.isEmpty { SharedStore.setOutcome(fingerprint: fp, .accepted) }
        case Notifier.finishAction:
            SharedStore.command = AppCommand(action: .finish)
        case Notifier.resetAction:
            SharedStore.command = AppCommand(action: .reset)
        default:
            break
        }
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var phase
    @StateObject private var perms = Permissions.shared
    @AppStorage("onboarded") private var onboarded = false
    @State private var tab = 0
    @State private var showPrints = SharedStore.settings.saveScreenshots
    private let photoTimer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()
    private let liveTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    @State private var lastLiveState: RideActivityAttributes.ContentState?

    var body: some View {
        TabView(selection: $tab) {
            HomeView().tag(0).tabItem { Label("Início", systemImage: "bolt.fill") }
            DashboardView().tag(1).tabItem { Label("Painel", systemImage: "chart.pie.fill") }
            HistoryView().tag(2).tabItem { Label("Histórico", systemImage: "clock.arrow.circlepath") }
            // A aba de prints só existe com os prints ligados nos Ajustes.
            if showPrints {
                CapturesView().tag(3).tabItem { Label("Prints", systemImage: "photo.on.rectangle.angled") }
            }
            SettingsView().tag(4).tabItem { Label("Ajustes", systemImage: "slider.horizontal.3") }
        }
        .onChange(of: tab) { _ in showPrints = SharedStore.settings.saveScreenshots }
        .environmentObject(perms)
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
            OnboardingView { onboarded = true }
                .environmentObject(perms)
                .preferredColorScheme(.dark)
        }
        .task {
            // Ao entrar no app: pede tudo o que ainda não foi decidido.
            await perms.requestAll()
            flushPhotos()
            syncLiveActivity()
        }
        .onChange(of: phase) { p in
            guard p == .active else { return }
            Task { await perms.refresh() }
            flushPhotos()
            showPrints = SharedStore.settings.saveScreenshots
            syncLiveActivity()
        }
        .onReceive(photoTimer) { _ in flushPhotos() }
        .onReceive(liveTimer) { _ in if phase == .active { syncLiveActivity() } }
    }

    private func flushPhotos() {
        guard SharedStore.settings.saveScreenshots || !PhotoAlbum.notDetermined else { return }
        DispatchQueue.global(qos: .utility).async { _ = PhotoAlbum.flushPending() }
    }

    /// Com a leitura ligada, abre (ou atualiza) a Dynamic Island; com ela desligada, encerra.
    private func syncLiveActivity() {
        guard #available(iOS 16.2, *) else { return }
        let settings = SharedStore.settings
        let status = SharedStore.status
        let live = status.running && (status.lastFrameAt.map { Date().timeIntervalSince($0) < 30 } ?? true)
        guard settings.liveActivity && live else {
            if LiveActivityController.isRunning { LiveActivityController.end() }
            lastLiveState = nil
            return
        }
        // Só mexe na atividade quando o estado muda (a extensão grava o último chamado no armazenamento compartilhado).
        let state = SharedStore.liveState ?? .searching(offersToday: status.offersNotified)
        guard !LiveActivityController.isRunning || state != lastLiveState else { return }
        lastLiveState = state
        LiveActivityController.start(state)
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
