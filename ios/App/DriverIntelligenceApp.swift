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
        // Deixa os ajustes atuais à mão para a leitura de tela (ver Bridge).
        Bridge.publishSettings(SharedStore.settings)
        // Sincronização com a leitura, turno automático, GPS e Dynamic Island (segue rodando em segundo plano).
        AppSync.shared.start()
        return true
    }

    /// Mostra as notificações também com o app aberto.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Botões "Aceitei" / "Finalizei" das notificações: repassa para a extensão.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let fp = info["fingerprint"] as? String
        // A notificação carrega o chamado: guarda no histórico antes que ela suma da Central.
        if let data = info["rec"] as? Data, let record = try? JSONDecoder().decode(OfferRecord.self, from: data) {
            Bridge.merge(offers: [record])
        }
        switch response.actionIdentifier {
        case Notifier.acceptAction:
            Bridge.send(AppCommand(action: .accept, fingerprint: (fp?.isEmpty ?? true) ? nil : fp))
            if let fp, !fp.isEmpty { SharedStore.setOutcome(fingerprint: fp, .accepted) }
        case Notifier.finishAction:
            Bridge.send(AppCommand(action: .finish))
        case Notifier.resetAction:
            Bridge.send(AppCommand(action: .reset))
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
            AppSync.shared.pull()
            flushPhotos()
        }
        .onChange(of: phase) { p in
            guard p == .active else { return }
            Task { await perms.refresh() }
            Bridge.publishSettings(SharedStore.settings)
            AppSync.shared.pull()
            flushPhotos()
            showPrints = SharedStore.settings.saveScreenshots
        }
        .onReceive(photoTimer) { _ in flushPhotos() }
    }

    private func flushPhotos() {
        guard SharedStore.settings.saveScreenshots || !PhotoAlbum.notDetermined else { return }
        DispatchQueue.global(qos: .utility).async { _ = PhotoAlbum.flushPending() }
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
