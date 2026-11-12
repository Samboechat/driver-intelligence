import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Conteúdo da Atividade ao Vivo (Dynamic Island / tela bloqueada).
/// Fica em Shared porque o app, a extensão de leitura e o widget usam o mesmo tipo.
struct RideActivityAttributes: Codable, Hashable {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable { case searching, offer, trip }

        var phase: Phase = .searching
        /// ACEITAR / AVALIAR / RECUSAR (ou o rótulo da classificação com a matriz desligada).
        var verdict: String = ""
        /// green / yellow / red / gray.
        var classification: String = "gray"
        var fare: Double?
        var perKm: Double?
        var perHour: Double?
        var category: String?
        var alert: String?
        /// Motivo em uma linha curta ("Km baixo: 1,50 · mínimo 2,00").
        var reason: String?
        var offersToday: Int = 0
        var updatedAt = Date()
    }

    var startedAt = Date()
}

#if canImport(ActivityKit)
@available(iOS 16.2, *)
extension RideActivityAttributes: ActivityAttributes {}
#endif

extension RideActivityAttributes.ContentState {
    static func searching(offersToday: Int) -> Self {
        .init(phase: .searching, verdict: "Buscando corridas…", classification: "gray", offersToday: offersToday)
    }
}
