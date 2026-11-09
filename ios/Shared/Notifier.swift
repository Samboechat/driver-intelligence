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

    /// Sons por veredito (arquivos dentro do app). Sem o arquivo, o iOS toca o som padrão.
    static func sound(for c: Classification) -> UNNotificationSound {
        switch c {
        case .green: return UNNotificationSound(named: UNNotificationSoundName("di-aceitar.wav"))
        case .yellow: return UNNotificationSound(named: UNNotificationSoundName("di-avaliar.wav"))
        case .red: return UNNotificationSound(named: UNNotificationSoundName("di-recusar.wav"))
        case .gray: return .default
        }
    }

    /// `record`: o chamado como vai para o histórico (viaja junto, para o app conseguir salvá-lo).
    static func post(_ a: OfferAnalysis, settings: DriverSettings, identifier: String, screenshot: URL? = nil, record: OfferRecord? = nil) {
        let c = NotificationFormatter.format(a, goals: settings.goals, hourFloor: settings.hourFloor)
        let content = UNMutableNotificationContent()
        content.title = c.title
        content.subtitle = c.subtitle
        content.body = c.body
        content.threadIdentifier = offerThread
        content.categoryIdentifier = offerCategory
        var info: [String: Any] = ["fingerprint": a.fingerprint ?? ""]
        if let record, let data = try? JSONEncoder().encode(record) { info["rec"] = data }
        content.userInfo = info
        if settings.notifySound {
            content.sound = settings.verdictSounds ? sound(for: a.decision.classification) : .default
        }
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

    /// Notificações de exemplo (uma de cada veredito), para conferir o texto e os sons.
    static func sendTest(settings: DriverSettings) {
        let samples: [OfferData] = [
            OfferData(fare: 27.50, pickupDistanceKm: 1.4, tripDistanceKm: 9.6, pickupTimeMin: 4, tripTimeMin: 17, category: "Comfort",
                      destination: "Parque Campolim, Sorocaba", passengerRating: 4.92),
            OfferData(fare: 9.80, pickupDistanceKm: 4.2, tripDistanceKm: 3.1, pickupTimeMin: 11, tripTimeMin: 9, category: "UberX",
                      destination: "Éden, Sorocaba", passengerRating: 4.71),
        ]
        var ctx = settings.context
        ctx.useRealisticTime = false
        for (i, offer) in samples.enumerated() {
            let a = OfferAnalyzer().analyze(offer: offer, context: ctx)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 3.5) {
                post(a, settings: settings, identifier: "teste-\(i)-\(Date().timeIntervalSince1970)")
            }
        }
    }
}
