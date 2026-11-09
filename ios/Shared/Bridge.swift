import Foundation
import UserNotifications
import DriverCore

/// Tela que parecia um chamado (tinha botão Aceitar ou rótulos do cartão) e não pôde ser lida.
struct ReadMiss: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var at = Date()
    var text: String
}

/// Sinal de vida da extensão (pequeno, publicado a cada poucos segundos).
struct BridgePulse: Codable {
    var at = Date()
    var status = BroadcastStatus()
    var live: RideActivityAttributes.ContentState?
}

/// O que a extensão de leitura publica para o app.
struct BridgeState: Codable {
    var at = Date()
    var status = BroadcastStatus()
    var offers: [OfferRecord] = []
    var trips: [TripRecord] = []
    var samples: [TimingSample] = []
    var live: RideActivityAttributes.ContentState?
    var misses: [ReadMiss] = []
}

/**
 * Canal entre o app e a extensão de leitura que NÃO depende de App Group.
 *
 * Instaladores como o ESign assinam o app sem o grupo compartilhado: aí o app e a extensão passam a ter
 * armazenamentos separados, e o app não fica sabendo que a leitura está ligada nem recebe os chamados.
 * A central de notificações, porém, é a mesma para os dois (é por isso que as notificações da extensão
 * chegam com a permissão dada ao app). Este canal guarda os dados em pedidos de notificação agendados
 * para daqui a anos — eles nunca aparecem, mas podem ser lidos e substituídos pelos dois lados.
 *
 *  settings  app → extensão   ajustes do motorista
 *  command   app → extensão   "aceitei", "finalizei", …
 *  state     extensão → app   chamados, corridas, tempos medidos (publicado quando algo muda)
 *  pulse     extensão → app   sinal de vida e status (a cada poucos segundos)
 *
 * Com o App Group funcionando, os dois caminhos convivem (os dados são juntados pelo identificador).
 */
enum Bridge {
    enum Key: String { case settings, command, state, pulse }

    static let prefix = "di.bridge."
    private static let farFuture: TimeInterval = 5 * 365 * 86400
    private static var center: UNUserNotificationCenter { .current() }

    // MARK: Gravar e ler

    static func put<T: Encodable>(_ key: Key, _ value: T) {
        guard let json = try? JSONEncoder().encode(value) else { return }
        let packed = (try? (json as NSData).compressed(using: .zlib)) as Data?
        let content = UNMutableNotificationContent()
        // Nunca é exibido (dispara daqui a anos e é substituído a cada gravação), mas o iOS pede um texto.
        content.title = "Driver Intelligence"
        content.body = "Sincronização interna."
        content.userInfo = [
            "d": packed ?? json,
            "z": packed != nil,
            "at": Date().timeIntervalSince1970,
        ]
        if #available(iOS 15.0, *) { content.interruptionLevel = .passive }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: farFuture, repeats: false)
        center.add(UNNotificationRequest(identifier: prefix + key.rawValue, content: content, trigger: trigger))
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ info: [AnyHashable: Any]) -> T? {
        guard var data = info["d"] as? Data else { return nil }
        if (info["z"] as? Bool) == true {
            guard let raw = try? (data as NSData).decompressed(using: .zlib) else { return nil }
            data = raw as Data
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Lê as caixas pedidas. `since`: ignora o que não mudou desde a última leitura (por caixa).
    static func read(_ completion: @escaping ([Key: (at: TimeInterval, info: [AnyHashable: Any])]) -> Void) {
        center.getPendingNotificationRequests { requests in
            var out: [Key: (at: TimeInterval, info: [AnyHashable: Any])] = [:]
            for r in requests where r.identifier.hasPrefix(prefix) {
                guard let key = Key(rawValue: String(r.identifier.dropFirst(prefix.count))) else { continue }
                let info = r.content.userInfo
                out[key] = ((info["at"] as? TimeInterval) ?? 0, info)
            }
            completion(out)
        }
    }

    static func value<T: Decodable>(_ type: T.Type, from box: (at: TimeInterval, info: [AnyHashable: Any])?) -> T? {
        box.flatMap { decode(type, $0.info) }
    }

    // MARK: Lado do app

    /// Publica os ajustes para a extensão (chamado ao abrir o app e a cada mudança).
    static func publishSettings(_ s: DriverSettings) { put(.settings, s) }

    /// Envia um comando para a extensão (pelos dois caminhos).
    static func send(_ command: AppCommand) {
        SharedStore.command = command
        put(.command, command)
    }

    /// Busca o estado publicado pela extensão e junta no armazenamento do app. `changed` = chegou algo novo.
    static func pull(_ completion: ((_ changed: Bool) -> Void)? = nil) {
        read { boxes in
            var changed = false
            if let state = value(BridgeState.self, from: boxes[.state]) { changed = ingest(state) }
            if let pulse = value(BridgePulse.self, from: boxes[.pulse]), pulse.at > (SharedStore.pulseAt ?? .distantPast) {
                SharedStore.pulseAt = pulse.at
                SharedStore.status = pulse.status
                SharedStore.liveState = pulse.live
                changed = true
            }
            // Reserva: cada notificação de chamado ainda na Central carrega o próprio registro.
            center.getDeliveredNotifications { delivered in
                let records: [OfferRecord] = delivered.compactMap { n in
                    guard let data = n.request.content.userInfo["rec"] as? Data else { return nil }
                    return try? JSONDecoder().decode(OfferRecord.self, from: data)
                }
                if merge(offers: records) { changed = true }
                completion?(changed)
            }
        }
    }

    @discardableResult
    static func ingest(_ s: BridgeState) -> Bool {
        if let last = SharedStore.bridgeAt, s.at <= last { return false }
        SharedStore.bridgeAt = s.at

        // Status: só troca por um mais novo (com App Group, o armazenamento comum pode estar à frente).
        let local = SharedStore.status
        let localStamp = [local.lastFrameAt, local.startedAt].compactMap { $0 }.max() ?? .distantPast
        let remoteStamp = [s.status.lastFrameAt, s.status.startedAt].compactMap { $0 }.max() ?? s.at
        if remoteStamp >= localStamp || local.running != s.status.running { SharedStore.status = s.status }

        merge(offers: s.offers)

        let tripsCleared = SharedStore.tripsClearedAt ?? .distantPast
        let deleted = Set(SharedStore.deletedTrips)
        var trips = SharedStore.trips
        var known = Set(trips.map(\.id))
        for t in s.trips where t.completedAt > tripsCleared && !deleted.contains(t.id) && !known.contains(t.id) {
            trips.append(t)
            known.insert(t.id)
        }
        trips.sort { $0.completedAt > $1.completedAt }
        if trips != SharedStore.trips { SharedStore.trips = trips }

        if s.samples != SharedStore.samples { SharedStore.samples = s.samples }
        if s.misses != SharedStore.misses { SharedStore.misses = s.misses }
        SharedStore.liveState = s.live
        return true
    }

    /// Junta chamados pelo identificador. A versão da extensão vale; o resultado (aceita/recusada) nunca é perdido.
    @discardableResult
    static func merge(offers incoming: [OfferRecord]) -> Bool {
        guard !incoming.isEmpty else { return false }
        let cleared = SharedStore.historyClearedAt ?? .distantPast
        let before = SharedStore.history
        var byId: [String: OfferRecord] = [:]
        for r in before { byId[r.id] = r }
        for r in incoming where r.date > cleared {
            var n = r
            if let old = byId[r.id] {
                if n.outcome == nil { n.outcome = old.outcome }
                if n.screenshot == nil { n.screenshot = old.screenshot }
            }
            byId[r.id] = n
        }
        let merged = byId.values.sorted { $0.date > $1.date }
        guard merged != before else { return false }
        SharedStore.history = merged
        return true
    }

    // MARK: Lado da extensão

    static func pulse(status: BroadcastStatus, live: RideActivityAttributes.ContentState?) {
        put(.pulse, BridgePulse(at: Date(), status: status, live: live))
    }

    /// Publica o estado para o app. Leva só o recente: o app guarda o histórico completo do lado dele.
    static func publish(status: BroadcastStatus, live: RideActivityAttributes.ContentState?) {
        put(.state, BridgeState(
            at: Date(),
            status: status,
            offers: Array(SharedStore.history.prefix(80)),
            trips: Array(SharedStore.trips.prefix(40)),
            samples: Array(SharedStore.samples.suffix(60)),
            live: live,
            misses: SharedStore.misses
        ))
    }

    /// O canal está funcionando? (algum sinal da extensão já chegou ao app)
    static var everReceived: Bool { SharedStore.pulseAt != nil || SharedStore.bridgeAt != nil }
}
