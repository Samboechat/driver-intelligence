import Foundation
import UserNotifications
import DriverCore

/// Envia as notificações de análise (usado pela extensão e pelo teste no app).
enum Notifier {
    static let offerThread = "offers"

    static func post(_ a: OfferAnalysis, settings: DriverSettings, identifier: String) {
        let c = NotificationFormatter.format(a, goals: settings.goals)
        let content = UNMutableNotificationContent()
        content.title = c.title
        content.body = c.body
        content.threadIdentifier = offerThread
        content.sound = settings.notifySound ? .default : nil
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .active
            content.relevanceScore = a.decision.classification == .green ? 1 : 0.5
        }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func postInfo(_ title: String, _ body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "status"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    /// Notificação de exemplo, para conferir se elas aparecem (e passam pelo Foco).
    static func sendTest(settings: DriverSettings) {
        let a = OfferAnalyzer().analyze(
            offer: OfferData(fare: 19.20, pickupDistanceKm: 1.2, tripDistanceKm: 7.7, pickupTimeMin: 4, tripTimeMin: 20, category: "UberX"),
            context: settings.context
        )
        post(a, settings: settings, identifier: "teste-\(Date().timeIntervalSince1970)")
    }
}
