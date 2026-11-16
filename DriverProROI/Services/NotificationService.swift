import Foundation
import UserNotifications

struct BlockReminder {
    let id: String
    let weekday: Int
    let startMinute: Int
    let title: String
    let timeLabel: String
}

/// Notificações locais: fadiga, queda de rendimento, zonas, break-even e lembretes do cronograma.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let fatigueHours = [8, 10, 12]

    func configure() {
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Envia agora (ou após `seconds`). `discreet` = sem som, entrega passiva.
    func notify(id: String, title: String, body: String, discreet: Bool = false, after seconds: TimeInterval = 0) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if discreet {
            content.interruptionLevel = .passive
        } else {
            content.sound = .default
        }
        var trigger: UNNotificationTrigger?
        if seconds >= 1 {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: Fadiga

    /// Agenda os alertas de 8h, 10h e 12h a partir do tempo já trabalhado hoje.
    func scheduleFatigue(alreadyWorked seconds: Double) {
        cancelFatigue()
        for hours in fatigueHours {
            let remaining = Double(hours) * 3600 - seconds
            guard remaining >= 1 else { continue }
            let body: String
            switch hours {
            case 8: body = "Você completou 8h de direção hoje. Faça uma pausa de pelo menos 15 minutos."
            case 10: body = "10h de direção acumuladas. O risco de acidente sobe muito a partir daqui — descanse."
            default: body = "12h de direção hoje. Pausa obrigatória: encerre o turno e descanse."
            }
            notify(id: "fatigue.\(hours)", title: "Alerta de fadiga — \(hours)h ao volante", body: body, after: remaining)
        }
    }

    func cancelFatigue() {
        center.removePendingNotificationRequests(withIdentifiers: fatigueHours.map { "fatigue.\($0)" })
    }

    // MARK: Cronograma

    /// Lembretes semanais 30 minutos antes de cada bloco de trabalho.
    func rescheduleBlockReminders(_ blocks: [BlockReminder], enabled: Bool) {
        let center = self.center
        center.getPendingNotificationRequests { requests in
            let old = requests.map { $0.identifier }.filter { $0.hasPrefix("block.") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            guard enabled else { return }
            for block in blocks {
                var minute = block.startMinute - 30
                var weekday = block.weekday
                if minute < 0 {
                    minute += 1440
                    weekday = weekday == 1 ? 7 : weekday - 1
                }
                var components = DateComponents()
                components.weekday = weekday
                components.hour = minute / 60
                components.minute = minute % 60

                let content = UNMutableNotificationContent()
                content.title = "Bloco começa em 30 min"
                content.body = "\(block.title) — \(block.timeLabel)"
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                center.add(UNNotificationRequest(identifier: "block.\(block.id)", content: content, trigger: trigger))
            }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
