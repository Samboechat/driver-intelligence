import Foundation

/**
 * Guia de onde rodar em Sorocaba e região, por dia da semana e horário.
 *
 * Não existe dado público de demanda por bairro: o guia junta os horários dos polos que geram corrida
 * (shoppings, faculdades, hospitais, rodoviária, bares, fábricas, bairros de perfil Comfort) e,
 * quando há chamados suficientes no seu histórico naquela região e horário, mistura com o que você
 * recebeu de verdade. Quanto mais você roda com o app, mais o guia fica com a sua cara.
 */
public struct DemandWindow: Equatable, Sendable {
    /// Dias (Calendar: 1 = domingo … 7 = sábado).
    public var days: Set<Int>
    /// Minutos desde 0h. `end` menor que `start` = passa da meia-noite.
    public var start: Int
    public var end: Int
    /// 1 fraca · 2 boa · 3 alta.
    public var level: Int
    public var why: String

    public func contains(weekday: Int, minute: Int) -> Bool {
        if start <= end { return days.contains(weekday) && minute >= start && minute < end }
        let prev = weekday == 1 ? 7 : weekday - 1
        return (days.contains(weekday) && minute >= start) || (days.contains(prev) && minute < end)
    }

    public var hours: String {
        func f(_ m: Int) -> String { String(format: "%02d:%02d", (m / 60) % 24, m % 60) }
        return "\(f(start))–\(f(end))"
    }
}

public struct DemandHub: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// Bairros e lugares que a região cobre.
    public var places: [String]
    /// Texto para achar o ponto no mapa da Apple.
    public var query: String
    public var lat: Double
    public var lon: Double
    public var radiusKm: Double
    /// Perfil de passageiro Comfort: 0 baixo · 1 médio · 2 alto.
    public var comfort: Int
    /// Destino de volta vazia.
    public var periphery: Bool
    public var note: String?
    public var windows: [DemandWindow]

    public var point: GeoPoint { GeoPoint(lat: lat, lon: lon, accuracy: 0, time: 0) }
}

/// Chamado do seu histórico com a posição do carro.
public struct HubSample: Sendable {
    public var date: Date
    public var lat: Double
    public var lon: Double
    public var perKm: Double?
    public var green: Bool
    public var perHour: Double?
    public init(date: Date, lat: Double, lon: Double, perKm: Double?, green: Bool, perHour: Double? = nil) {
        self.date = date; self.lat = lat; self.lon = lon; self.perKm = perKm; self.green = green; self.perHour = perHour
    }
}

public struct OwnStats: Equatable, Sendable {
    public var count: Int
    public var avgPerKm: Double?
    public var greenShare: Double
    /// 0–3, na mesma escala do guia.
    public var level: Double
}

public struct HubAdvice: Identifiable, Sendable {
    public enum Verdict: String, Sendable {
        case here, go, maybe, skip
        public var label: String {
            switch self {
            case .here: return "Você está aqui"
            case .go: return "Vale ir"
            case .maybe: return "Talvez"
            case .skip: return "Não vale"
            }
        }
    }
    public var hub: DemandHub
    public var level: Int
    public var window: DemandWindow?
    public var own: OwnStats?
    public var distanceKm: Double?
    public var arrival: Date
    /// Custo para chegar lá vazio (km × custo por km).
    public var tripCost: Double?
    public var score: Double
    public var verdict: Verdict
    /// Próximo horário bom (até 4 h), se agora não estiver bom.
    public var nextPeak: (at: Date, window: DemandWindow)?
    public var id: String { hub.id }

    public var levelLabel: String { DemandGuide.levelLabel(level) }
}

public enum DemandGuide {
    static let all: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    static let monFri: Set<Int> = [2, 3, 4, 5, 6]
    static let monThu: Set<Int> = [2, 3, 4, 5]
    static let monSat: Set<Int> = [2, 3, 4, 5, 6, 7]
    static let friSat: Set<Int> = [6, 7]
    static let satSun: Set<Int> = [7, 1]
    static let sun: Set<Int> = [1]
    static let fri: Set<Int> = [6]

    static func w(_ d: Set<Int>, _ s: String, _ e: String, _ level: Int, _ why: String) -> DemandWindow {
        func m(_ t: String) -> Int { let p = t.split(separator: ":").compactMap { Int($0) }; return p[0] * 60 + (p.count > 1 ? p[1] : 0) }
        return DemandWindow(days: d, start: m(s), end: m(e), level: level, why: why)
    }

    public static func levelLabel(_ l: Int) -> String {
        switch l {
        case 3: return "Alta"
        case 2: return "Boa"
        case 1: return "Fraca"
        default: return "Parada"
        }
    }

    /// Hospitais: trocas de plantão e visitas.
    static let hospital: [DemandWindow] = [
        w(all, "06:30", "08:00", 2, "Troca de plantão da manhã"),
        w(all, "18:30", "20:00", 2, "Troca de plantão e fim das visitas"),
        w(monFri, "10:00", "17:00", 1, "Consultas e altas ao longo do dia"),
    ]

    /// Shoppings: abrem 10h–22h (domingo 14h–20h); o pico é no fechamento.
    static func mall(_ close: Int) -> [DemandWindow] {
        [
            w(monSat, "21:45", "23:00", close, "Fechamento do shopping e saída do cinema"),
            w(sun, "19:45", "21:30", close, "Fechamento de domingo"),
            w(satSun, "13:00", "19:30", 2, "Movimento de fim de semana"),
            w(monFri, "11:30", "14:00", 1, "Almoço"),
            w(monFri, "17:30", "21:30", 1, "Fim de tarde"),
        ]
    }

    public static let hubs: [DemandHub] = [
        DemandHub(id: "campolim", name: "Campolim", places: ["Parque Campolim", "Av. Antônio Carlos Comitre", "Jardim Portal da Colina", "Parque Reserva Fazenda Imperial"],
                  query: "Parque Campolim, Sorocaba", lat: -23.5317, lon: -47.4680, radiusKm: 1.6, comfort: 2, periphery: false,
                  note: "O melhor perfil Comfort da cidade. De madrugada saem as corridas para Viracopos e Guarulhos.",
                  windows: [
                    w(all, "04:00", "06:00", 2, "Corridas para os aeroportos"),
                    w(monFri, "06:00", "09:00", 3, "Saída para o trabalho"),
                    w(monThu, "18:00", "23:00", 2, "Restaurantes e academias da Comitre"),
                    w(friSat, "19:00", "03:00", 3, "Bares e baladas do Campolim"),
                    w(sun, "11:00", "16:00", 2, "Almoço de domingo"),
                  ]),
        DemandHub(id: "iguatemi", name: "Iguatemi Esplanada", places: ["Shopping Iguatemi Esplanada", "Esplanada", "divisa com Votorantim"],
                  query: "Shopping Iguatemi Esplanada", lat: -23.5378, lon: -47.4590, radiusKm: 1.0, comfort: 2, periphery: false,
                  note: "Um dos destinos mais pedidos no Uber em Sorocaba.", windows: mall(3)),
        DemandHub(id: "ciane", name: "Pátio Cianê", places: ["Pátio Cianê Shopping", "Centro", "Vila Lucy"],
                  query: "Pátio Cianê Shopping, Sorocaba", lat: -23.4930, lon: -47.4500, radiusKm: 0.9, comfort: 1, periphery: false,
                  note: "O destino mais pedido no Uber em Sorocaba.", windows: mall(3)),
        DemandHub(id: "cidade", name: "Shopping Cidade", places: ["Shopping Cidade Sorocaba"],
                  query: "Shopping Cidade Sorocaba", lat: -23.4880, lon: -47.4430, radiusKm: 0.9, comfort: 1, periphery: false,
                  note: nil, windows: mall(3)),
        DemandHub(id: "sorocabashopping", name: "Sorocaba Shopping", places: ["Sorocaba Shopping Center", "Vila Hortência"],
                  query: "Sorocaba Shopping Center", lat: -23.5050, lon: -47.4420, radiusKm: 0.8, comfort: 1, periphery: false,
                  note: nil, windows: mall(2)),
        DemandHub(id: "centro", name: "Centro", places: ["Centro", "Rua XV de Novembro", "Armarinhos Fernando", "Largo do Rosário", "Vila Carvalho"],
                  query: "Armarinhos Fernando, Sorocaba", lat: -23.5017, lon: -47.4581, radiusKm: 1.2, comfort: 0, periphery: false,
                  note: "Muita corrida curta de UberX; o Centro esvazia à noite.",
                  windows: [
                    w(monFri, "08:00", "18:30", 2, "Comércio e serviços"),
                    w([7], "08:00", "14:00", 2, "Comércio de sábado"),
                    w(monFri, "18:30", "20:00", 1, "Fechamento do comércio"),
                  ]),
        DemandHub(id: "rodoviaria", name: "Rodoviária", places: ["Terminal Rodoviário de Sorocaba"],
                  query: "Rodoviária de Sorocaba", lat: -23.4900, lon: -47.4560, radiusKm: 0.7, comfort: 1, periphery: false,
                  note: "Fila de táxi forte; vale quando chega muito ônibus.",
                  windows: [
                    w(all, "05:00", "07:30", 2, "Ônibus da madrugada chegando"),
                    w(fri, "17:00", "23:00", 2, "Começo do fim de semana"),
                    w(sun, "16:00", "23:30", 3, "Volta do fim de semana"),
                  ]),
        DemandHub(id: "uniso", name: "Uniso", places: ["Uniso Cidade Universitária", "Rod. Raposo Tavares km 92,5", "Jardim Novo Eldorado"],
                  query: "Uniso Cidade Universitária, Sorocaba", lat: -23.5340, lon: -47.4990, radiusKm: 1.0, comfort: 1, periphery: false,
                  note: "Saída da noite enche, mas muita corrida é curta e de estudante.",
                  windows: [
                    w(monFri, "07:00", "08:15", 2, "Chegada das aulas da manhã"),
                    w(monFri, "12:00", "13:30", 2, "Troca de turno das aulas"),
                    w(monFri, "18:30", "19:30", 1, "Chegada das aulas da noite"),
                    w(monFri, "22:15", "23:15", 3, "Saída das aulas da noite"),
                  ]),
        DemandHub(id: "facens", name: "Facens", places: ["Facens", "Rod. Senador José Ermírio de Moraes"],
                  query: "Facens Sorocaba", lat: -23.4700, lon: -47.4310, radiusKm: 0.8, comfort: 1, periphery: false, note: nil,
                  windows: [
                    w(monFri, "07:00", "08:00", 2, "Chegada das aulas da manhã"),
                    w(monFri, "22:15", "23:15", 3, "Saída das aulas da noite"),
                  ]),
        DemandHub(id: "ufscar", name: "UFSCar Sorocaba", places: ["UFSCar campus Sorocaba", "Rod. João Leme dos Santos"],
                  query: "UFSCar Campus Sorocaba", lat: -23.5810, lon: -47.5250, radiusKm: 1.0, comfort: 1, periphery: false,
                  note: "Longe do centro: só compensa se você já estiver perto.",
                  windows: [
                    w(monFri, "17:30", "19:00", 2, "Saída das aulas da tarde"),
                    w(monFri, "22:00", "23:00", 2, "Saída das aulas da noite"),
                  ]),
        DemandHub(id: "unimed", name: "Hospital Unimed", places: ["Hospital Unimed Sorocaba"],
                  query: "Hospital Unimed Sorocaba", lat: -23.5200, lon: -47.4650, radiusKm: 0.6, comfort: 2, periphery: false,
                  note: nil, windows: hospital),
        DemandHub(id: "santacasa", name: "Santa Casa / GPACI", places: ["Santa Casa de Sorocaba", "GPACI", "Hospital Evangélico", "Além Ponte"],
                  query: "Santa Casa de Sorocaba", lat: -23.5080, lon: -47.4430, radiusKm: 0.9, comfort: 1, periphery: false,
                  note: nil, windows: hospital),
        DemandHub(id: "regional", name: "Hospital Regional", places: ["Conjunto Hospitalar de Sorocaba", "Hospital Regional"],
                  query: "Conjunto Hospitalar de Sorocaba", lat: -23.4960, lon: -47.4720, radiusKm: 0.6, comfort: 0, periphery: false,
                  note: nil, windows: hospital),
        DemandHub(id: "boavista", name: "Alto da Boa Vista / Jd. Emília", places: ["Alto da Boa Vista", "Jardim Emília", "Jardim Faculdade", "Jardim Europa"],
                  query: "Alto da Boa Vista, Sorocaba", lat: -23.5150, lon: -47.4740, radiusKm: 1.5, comfort: 2, periphery: false,
                  note: "Residencial de perfil Comfort: forte na saída para o trabalho e nas noites de sexta e sábado.",
                  windows: [
                    w(all, "04:30", "06:00", 1, "Aeroportos e viagens"),
                    w(monFri, "06:00", "09:00", 3, "Saída para o trabalho"),
                    w(monFri, "17:30", "20:00", 2, "Volta para casa e compromissos"),
                    w(friSat, "19:00", "23:30", 2, "Saída para jantar e festas"),
                    w(sun, "10:00", "14:00", 1, "Domingo de manhã"),
                  ]),
        DemandHub(id: "mangal", name: "Mangal / Vergueiro", places: ["Jardim do Mangal", "Jardim Vergueiro", "Jardim Santa Rosa", "Vila Haro"],
                  query: "Jardim do Mangal, Sorocaba", lat: -23.5240, lon: -47.4560, radiusKm: 1.2, comfort: 2, periphery: false, note: nil,
                  windows: [
                    w(monFri, "06:00", "09:00", 3, "Saída para o trabalho"),
                    w(monFri, "17:30", "20:00", 2, "Volta e compromissos"),
                    w(friSat, "19:00", "23:30", 2, "Saída à noite"),
                  ]),
        DemandHub(id: "santarosalia", name: "Santa Rosália", places: ["Jardim Santa Rosália", "Vila Santana", "Jardim Sorocabano", "Vila Adélia"],
                  query: "Jardim Santa Rosália, Sorocaba", lat: -23.4870, lon: -47.4650, radiusKm: 1.2, comfort: 1, periphery: false,
                  note: "Bares e restaurantes perto do Centro.",
                  windows: [
                    w(monFri, "07:00", "09:00", 1, "Saída para o trabalho"),
                    w(friSat, "19:00", "02:00", 2, "Bares e restaurantes"),
                  ]),
        DemandHub(id: "alemponte", name: "Além Ponte / Zona Leste", places: ["Além Ponte", "Jardim Piratininga", "Vila Hortência", "Zoológico Quinzinho de Barros"],
                  query: "Além Ponte, Sorocaba", lat: -23.5080, lon: -47.4350, radiusKm: 1.5, comfort: 1, periphery: false, note: nil,
                  windows: [
                    w(monFri, "06:30", "09:00", 2, "Saída para o trabalho"),
                    w(friSat, "19:00", "00:00", 1, "Saídas da noite"),
                    w(satSun, "09:00", "13:00", 1, "Zoológico e passeios"),
                  ]),
        DemandHub(id: "zonanorte", name: "Zona Norte (Itavuvu)", places: ["Av. Itavuvu", "Vila Barcelona", "Jardim Ipiranga", "Vitória Régia", "Habiteto", "Ana Paula Eleutério", "Carandá"],
                  query: "Avenida Itavuvu, Sorocaba", lat: -23.4580, lon: -47.4560, radiusKm: 3.0, comfort: 0, periphery: true,
                  note: "Região mais populosa: muita demanda cedo, quase toda UberX. Corrida que termina aqui = volta vazia.",
                  windows: [
                    w(monSat, "05:00", "08:00", 3, "Ida ao trabalho"),
                    w(friSat, "20:00", "02:00", 2, "Saídas da noite"),
                    w(sun, "10:00", "14:00", 1, "Domingo"),
                  ]),
        DemandHub(id: "saobento", name: "Parque São Bento", places: ["Parque São Bento", "Parque das Laranjeiras", "Jardim Nova Esperança", "Maria Eugênia"],
                  query: "Parque São Bento, Sorocaba", lat: -23.4430, lon: -47.4720, radiusKm: 2.0, comfort: 0, periphery: true,
                  note: "Bairro mais populoso da cidade; destino de periferia.",
                  windows: [
                    w(monSat, "05:00", "07:30", 2, "Ida ao trabalho"),
                    w(friSat, "21:00", "02:00", 1, "Saídas da noite"),
                  ]),
        DemandHub(id: "eden", name: "Éden / Zona Industrial", places: ["Éden", "Zona Industrial", "Aparecidinha", "Brigadeiro Tobias"],
                  query: "Éden, Sorocaba", lat: -23.4180, lon: -47.4200, radiusKm: 2.5, comfort: 0, periphery: true,
                  note: "Troca de turno das fábricas. Ir até lá vazio raramente compensa.",
                  windows: [
                    w(monSat, "05:00", "06:30", 2, "Troca de turno das fábricas"),
                    w(monSat, "13:30", "15:00", 2, "Troca de turno das fábricas"),
                    w(monSat, "21:30", "23:30", 2, "Troca de turno das fábricas"),
                  ]),
        DemandHub(id: "zonaoeste", name: "Zona Oeste", places: ["Wanel Ville", "Júlio de Mesquita Filho", "Jardim Simus", "Vila Helena"],
                  query: "Wanel Ville, Sorocaba", lat: -23.5000, lon: -47.4950, radiusKm: 2.0, comfort: 0, periphery: false, note: nil,
                  windows: [
                    w(monFri, "05:30", "08:00", 2, "Ida ao trabalho"),
                    w(friSat, "20:00", "00:00", 1, "Saídas da noite"),
                  ]),
        DemandHub(id: "cajuru", name: "Cajuru do Sul", places: ["Cajuru do Sul", "divisa com Itu"],
                  query: "Cajuru do Sul, Sorocaba", lat: -23.4400, lon: -47.3600, radiusKm: 2.0, comfort: 0, periphery: true,
                  note: "Longe: só se você já estiver por perto.",
                  windows: [w(monFri, "05:30", "07:30", 1, "Ida ao trabalho")]),
        DemandHub(id: "votorantim", name: "Votorantim", places: ["Centro de Votorantim", "Vila Albertina", "Parque Bela Vista"],
                  query: "Centro, Votorantim", lat: -23.5460, lon: -47.4380, radiusKm: 2.5, comfort: 0, periphery: true,
                  note: "Destino de periferia: volta vazia.",
                  windows: [
                    w(monFri, "06:00", "08:00", 2, "Ida ao trabalho"),
                    w(friSat, "20:00", "01:00", 1, "Saídas da noite"),
                  ]),
    ]

    /// Melhor janela de uma região num momento.
    public static func level(_ hub: DemandHub, at date: Date, calendar: Calendar = .current) -> (Int, DemandWindow?) {
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let wd = c.weekday ?? 1
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let best = hub.windows.filter { $0.contains(weekday: wd, minute: m) }.max { $0.level < $1.level }
        return (best?.level ?? 0, best)
    }

    /// Próximo horário bom (nível 2+) em até `hours` horas.
    public static func nextPeak(_ hub: DemandHub, after date: Date, hours: Double = 4,
                                calendar: Calendar = .current) -> (at: Date, window: DemandWindow)? {
        var t = date
        let limit = date.addingTimeInterval(hours * 3600)
        while t <= limit {
            let (l, w) = level(hub, at: t, calendar: calendar)
            if l >= 2, let w { return (t, w) }
            t = t.addingTimeInterval(15 * 60)
        }
        return nil
    }

    /// Janelas de uma região num dia da semana, em ordem de horário.
    public static func windows(_ hub: DemandHub, weekday: Int) -> [DemandWindow] {
        hub.windows.filter { $0.days.contains(weekday) }.sorted { $0.start < $1.start }
    }

    /// Seus chamados naquela região, no mesmo dia da semana e até 1 h de diferença do horário.
    public static func own(_ hub: DemandHub, at date: Date, samples: [HubSample], acceptPerKm: Double,
                           calendar: Calendar = .current) -> OwnStats? {
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let near = samples.filter { s in
            let sc = calendar.dateComponents([.weekday, .hour, .minute], from: s.date)
            let sm = (sc.hour ?? 0) * 60 + (sc.minute ?? 0)
            var diff = abs(sm - m)
            diff = min(diff, 1440 - diff)
            return sc.weekday == c.weekday && diff <= 60
                && GeoPoint(lat: s.lat, lon: s.lon, accuracy: 0, time: 0).distance(to: hub.point) <= hub.radiusKm * 1000
        }
        guard near.count >= 4 else { return nil }
        let km = near.compactMap(\.perKm)
        let avg = km.isEmpty ? nil : km.reduce(0, +) / Double(km.count)
        let green = Double(near.filter(\.green).count) / Double(near.count)
        // Frequência (até 3 por janela de 2 h por semana vista) e qualidade.
        let quality = 3 * green + ((avg ?? 0) >= acceptPerKm ? 0.5 : 0)
        let level = min(3, max(0, 0.5 * min(3, Double(near.count) / 2) + 0.5 * quality))
        return OwnStats(count: near.count, avgPerKm: avg, greenShare: green, level: level)
    }

    /**
     * Ranking das regiões para um horário, a partir de onde você está.
     * Considera a hora em que você CHEGARIA lá (28 km/h de média, ruas ≈ 1,3 × a linha reta),
     * o perfil Comfort, a periferia (volta vazia), o seu histórico e o custo de ir vazio.
     */
    public static func advice(at date: Date, from here: GeoPoint?, samples: [HubSample] = [], comfortDriver: Bool = true,
                              acceptPerKm: Double = 2.30, costPerKm: Double = 0.50, hubs: [DemandHub] = hubs,
                              calendar: Calendar = .current) -> [HubAdvice] {
        hubs.map { hub in
            let dist = here.map { $0.distance(to: hub.point) / 1000 * 1.3 }
            let arrival = date.addingTimeInterval((dist ?? 0) / 28 * 3600)
            let (lvl, win) = level(hub, at: arrival, calendar: calendar)
            let own = own(hub, at: arrival, samples: samples, acceptPerKm: acceptPerKm, calendar: calendar)
            var base = Double(lvl)
            if comfortDriver {
                base += Double(hub.comfort) * 0.35
                if hub.periphery { base -= 0.3 }
            }
            if let own { base = 0.5 * base + 0.5 * own.level }
            let score = base - (dist ?? 0) * 0.08
            let verdict: HubAdvice.Verdict
            if let d = dist, d < max(1.2, hub.radiusKm) {
                verdict = .here
            } else if score >= 2.2, (dist ?? 0) <= 10 {
                verdict = .go
            } else if score >= 1.5, (dist ?? 0) <= 6 {
                verdict = .maybe
            } else {
                verdict = .skip
            }
            let next = lvl >= 2 ? nil : nextPeak(hub, after: arrival, calendar: calendar)
            return HubAdvice(hub: hub, level: lvl, window: win, own: own, distanceKm: dist, arrival: arrival,
                             tripCost: dist.map { $0 * costPerKm }, score: score, verdict: verdict, nextPeak: next)
        }
        .sorted { $0.score > $1.score }
    }
}

// MARK: - Previsão por região (saída e destino de um chamado)

/// O que esperar de uma região num horário: movimento e R$/h previsto para quem fica rodando ali.
public struct RegionOutlook: Equatable, Sendable {
    public var name: String
    public var level: Int
    public var perHour: Double
    public var periphery: Bool
    public var at: Date
    public var why: String?

    /// "Campolim · Alta · ~R$ 62/h".
    public var short: String {
        periphery ? "\(name) · volta vazia · ~R$ \(Br.decimal(perHour, 0))/h"
            : "\(name) · \(DemandGuide.levelLabel(level)) · ~R$ \(Br.decimal(perHour, 0))/h"
    }
}

extension DemandGuide {
    /// Região de um endereço (o nome de bairro, shopping ou avenida mais específico que aparecer).
    public static func hub(matching text: String?, hubs: [DemandHub] = hubs) -> DemandHub? {
        guard let text, !text.isEmpty else { return nil }
        let t = " " + SorocabaZone.normalize(text) + " "
        var best: (DemandHub, Int)?
        for h in hubs {
            for k in [h.name] + h.places {
                let n = SorocabaZone.normalize(k)
                guard n.count >= 5, t.contains(" " + n + " ") else { continue }
                if n.count > (best?.1 ?? 0) { best = (h, n.count) }
            }
        }
        return best?.0
    }

    /**
     * R$/h previsto numa região: pelo movimento do horário (alta ≈ 20% acima do ideal, boa = ideal,
     * fraca = piso, parada ≈ 15% abaixo do piso), descontando a volta vazia da periferia.
     * Quando há histórico próprio na região e horário, usa a média do que você recebeu ali.
     */
    public static func outlook(_ text: String?, at date: Date, hourFloor: Double, hourIdeal: Double,
                               samples: [HubSample] = [], hubs: [DemandHub] = hubs,
                               calendar: Calendar = .current) -> RegionOutlook? {
        guard let h = hub(matching: text, hubs: hubs) else { return nil }
        let (lvl, w) = level(h, at: date, calendar: calendar)
        var perHour: Double
        switch lvl {
        case 3: perHour = hourIdeal * 1.2
        case 2: perHour = hourIdeal
        case 1: perHour = hourFloor
        default: perHour = hourFloor * 0.85
        }
        if h.periphery { perHour *= 0.9 }
        let mine = samples.filter { s in
            guard let ph = s.perHour, ph > 0 else { return false }
            let sc = calendar.dateComponents([.weekday, .hour], from: s.date)
            let c = calendar.dateComponents([.weekday, .hour], from: date)
            return sc.weekday == c.weekday && abs((sc.hour ?? 0) - (c.hour ?? 0)) <= 1
                && GeoPoint(lat: s.lat, lon: s.lon, accuracy: 0, time: 0).distance(to: h.point) <= h.radiusKm * 1000
        }.compactMap(\.perHour)
        if mine.count >= 4 { perHour = 0.4 * perHour + 0.6 * mine.reduce(0, +) / Double(mine.count) }
        return RegionOutlook(name: h.name, level: lvl, perHour: perHour, periphery: h.periphery, at: date, why: w?.why)
    }
}
