import Foundation

/// Aviso instantâneo entre a extensão de leitura e o app (não leva dados; só diz "tem novidade no canal").
/// Funciona entre processos sem App Group.
enum DarwinSignal {
    private static let name = "com.samboechat.driverintelligence.bridge" as CFString
    static let received = Notification.Name("DarwinSignal.received")
    private static var observing = false

    static func post() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name), nil, nil, true)
    }

    /// Repassa o aviso para o NotificationCenter do próprio processo.
    static func observe() {
        guard !observing else { return }
        observing = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil,
            { _, _, _, _, _ in NotificationCenter.default.post(name: DarwinSignal.received, object: nil) },
            name, nil, .deliverImmediately
        )
    }
}
