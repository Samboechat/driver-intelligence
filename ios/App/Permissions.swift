import SwiftUI
import UserNotifications
import Photos

/// Estado e pedido de todas as permissões do app.
@MainActor
final class Permissions: ObservableObject {
    static let shared = Permissions()

    @Published var notifications: UNAuthorizationStatus = .notDetermined
    @Published var alertsEnabled = false
    @Published var photos: PHAuthorizationStatus = .notDetermined
    @Published var lastError: String?

    var notificationsOK: Bool { notifications == .authorized || notifications == .ephemeral || (notifications == .provisional && alertsEnabled) }
    var notificationsQuiet: Bool { notifications == .provisional }
    var photosOK: Bool { PhotoAlbum.canAdd }

    func refresh() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        notifications = s.authorizationStatus
        alertsEnabled = s.alertSetting == .enabled
        photos = PhotoAlbum.canUseAlbum ? PhotoAlbum.readWrite : (PhotoAlbum.addOnly == .authorized ? .authorized : PhotoAlbum.readWrite)
    }

    /// Pede tudo o que ainda não foi decidido (chamado ao abrir o app).
    func requestAll() async {
        await requestNotifications()
        // Fotos só é pedido com os prints ligados nos Ajustes.
        if SharedStore.settings.saveScreenshots { await requestPhotos() }
        // Localização: km rodados e Dynamic Island em tempo real.
        if SharedStore.settings.gpsTracking { LocationService.shared.requestPermission() }
        await refresh()
    }

    func requestNotifications() async {
        let center = UNUserNotificationCenter.current()
        Notifier.registerCategories()
        let current = await center.notificationSettings().authorizationStatus
        guard current == .notDetermined || current == .provisional else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            lastError = error.localizedDescription
        }
        // Reserva: se o aviso do iOS não apareceu, a autorização provisória faz a opção
        // "Notificações" surgir nos Ajustes, onde dá para ativar os alertas.
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge, .provisional])
        }
        await refresh()
    }

    func requestPhotos() async {
        guard PhotoAlbum.notDetermined else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            PhotoAlbum.requestAccess { _ in c.resume() }
        }
        await refresh()
    }

    func openSettings() {
        let url: URL?
        if #available(iOS 16.0, *) {
            url = URL(string: UIApplication.openNotificationSettingsURLString)
        } else {
            url = URL(string: UIApplication.openSettingsURLString)
        }
        if let url { UIApplication.shared.open(url) }
    }

    func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
