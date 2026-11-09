import Foundation
import UserNotifications
import DriverCore

/// Envia as notificações de análise (usado pela extensão e pelo teste no app).
enum Notifier {
    static let offerThread = "offers"
    static let offerCategory = "OFFER"
    static let tripCategory = "TRIP"
    static let acceptAction = "ACCEPT"
    static let finishAction = "FINISH"
    static let resetAction = "RESET"

    /// Botões nas notificações ("Aceitei", "Finalizei"), registrados pelo app.
    static func registerCategories() {
        let accept = UNNotificationAction(identifier: acceptAction, title: "✅ Aceitei esta corrida", options: [])
        let finish = UNNotificationAction(identifier: finishAction, title: "🏁 Finalizei a corrida", options: [])
        let reset = UNNotificationAction(identifier: resetAction, title: "Parar de acompanhar", options: [.destructive])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: offerCategory, actions: [accept], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: tripCategory, actions: [finish, reset], intentIdentifiers: [], options: []),
        ])
    }

    static func post(_ a: OfferAnalysis, settings: DriverSettings, identifier: String, screenshot: URL? = nil) {
        let c = NotificationFormatter.format(a, goals: settings.goals)
        let content = UNMutableNotificationContent()
        content.title = c.title
        content.body = c.body
        content.threadIdentifier = offerThread
        content.categoryIdentifier = offerCategory
        content.userInfo = ["fingerprint": a.fingerprint ?? ""]
        content.sound = settings.notifySound ? .default : nil
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .active
            content.relevanceScore = a.decision.classification == .green ? 1 : 0.5
        }
        if let screenshot, let att = attachment(screenshot) { content.attachments = [att] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    /// O sistema move o anexo para o próprio armazenamento: anexamos uma cópia.
    private static func attachment(_ url: URL) -> UNNotificationAttachment? {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        guard (try? FileManager.default.copyItem(at: url, to: tmp)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "print", url: tmp, options: [UNNotificationAttachmentOptionsThumbnailHiddenKey: false])
    }

    static func postInfo(_ title: String, _ body: String, id: String, category: String? = nil, sound: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "status"
        if let category { content.categoryIdentifier = category }
        if sound { content.sound = .default }
        if #available(iOS 15.0, *) { content.interruptionLevel = .passive }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    /// Resumo da corrida concluída, com o tempo real comparado ao que o app prometeu.
    static func postTripSummary(_ t: TripRecord, factors: TimeFactors, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "\(t.cls.dot) Corrida concluída · \(Br.money(t.fare))"
        var lines: [String] = []
        var first = "Tempo real \(Br.minutes(t.totalMin))"
        if let offered = t.offeredMin { first += " (app dizia \(Br.minutes(offered)))" }
        lines.append(first)
        lines.append("\(Br.perHour(t.revenuePerHour)) real · lucro \(Br.money(t.profit))")
        if factors.learned {
            lines.append("Tempo aprendido: busca ×\(Br.decimal(factors.pickup)) · viagem ×\(Br.decimal(factors.trip))")
        }
        content.body = lines.joined(separator: "\n")
        content.threadIdentifier = "trips"
        if sound { content.sound = .default }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "trip-\(t.id)", content: content, trigger: nil))
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
