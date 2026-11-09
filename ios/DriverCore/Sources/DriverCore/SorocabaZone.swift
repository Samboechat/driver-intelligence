import Foundation

/// Tipo de região do destino, para a matriz de aceite.
public enum ZoneKind: String, Codable, Sendable {
    /// Bairros com demanda alta: a volta costuma sair carregada.
    case hot
    /// Periferia / "km morto": a volta costuma ser vazia.
    case periphery
    /// Outra cidade: só compensa a partir de um valor mínimo (volta vazia inteira).
    case intercity
    /// Sem regra específica.
    case neutral

    public var label: String {
        switch self {
        case .hot: return "Zona quente"
        case .periphery: return "Periferia"
        case .intercity: return "Intermunicipal"
        case .neutral: return "Sem zona"
        }
    }
}

/// Cidade de destino com valor mínimo para aceitar.
public struct IntercityRule: Equatable, Codable, Sendable {
    public var name: String
    /// Nomes da cidade como aparecem no destino (comparados com o trecho "cidade" do endereço).
    public var cities: [String]
    /// Pontos que valem em qualquer lugar do texto (ex.: "viracopos").
    public var landmarks: [String]
    public var minimumFare: Double

    public init(name: String, cities: [String], landmarks: [String] = [], minimumFare: Double) {
        self.name = name
        self.cities = cities
        self.landmarks = landmarks
        self.minimumFare = minimumFare
    }
}

/// Regras de bairros e cidades. As listas são palavras-chave (sem acento, minúsculas).
public struct ZoneConfig: Equatable, Codable, Sendable {
    public var hot: [String]
    public var periphery: [String]
    public var intercity: [IntercityRule]
    /// Cidades "de casa": se o destino cita uma delas, nunca é intermunicipal.
    public var homeCities: [String]
    /// R$/km mínimo para destinos de periferia.
    public var peripheryMinPerKm: Double
    public var peripheryAlert: String

    public init(hot: [String], periphery: [String], intercity: [IntercityRule], homeCities: [String],
                peripheryMinPerKm: Double = 2.20, peripheryAlert: String = "Volta Vazia - Ligar Direcionamento") {
        self.hot = hot
        self.periphery = periphery
        self.intercity = intercity
        self.homeCities = homeCities
        self.peripheryMinPerKm = peripheryMinPerKm
        self.peripheryAlert = peripheryAlert
    }

    /// Sorocaba-SP.
    public static let sorocaba = ZoneConfig(
        hot: ["campolim", "iguatemi", "alto da boa vista", "mangal", "jardim emilia"],
        periphery: [
            "zona norte", "eden", "cajuru", "votorantim",
            // Bairros da Zona Norte (o endereço mostra o bairro, não "Zona Norte").
            "parque sao bento", "vitoria regia", "parque das laranjeiras", "habiteto",
            "maria eugenia", "nova esperanca", "paineiras",
        ],
        intercity: [
            IntercityRule(name: "Itu", cities: ["itu"], minimumFare: 128),
            IntercityRule(name: "Salto", cities: ["salto"], minimumFare: 168),
            IntercityRule(name: "Campinas/Viracopos", cities: ["campinas"], landmarks: ["viracopos"], minimumFare: 360),
            IntercityRule(name: "Jundiaí", cities: ["jundiai"], minimumFare: 380),
            IntercityRule(name: "Guarulhos", cities: ["guarulhos"], landmarks: ["aeroporto de guarulhos", "gru airport", "cumbica"], minimumFare: 530),
            IntercityRule(name: "SP Capital", cities: ["sao paulo"], landmarks: ["congonhas"], minimumFare: 422),
        ],
        homeCities: ["sorocaba", "votorantim"]
    )
}

public struct ZoneMatch: Equatable, Sendable {
    public var kind: ZoneKind
    /// Bairro ou cidade que casou (como configurado).
    public var name: String?
    /// Valor mínimo (só intermunicipal).
    public var minimumFare: Double?

    public static let neutral = ZoneMatch(kind: .neutral, name: nil, minimumFare: nil)
}

/**
 * Classifica o destino da oferta por palavras-chave.
 *
 * Cuidados para não confundir rua com cidade:
 *  - cidade só casa com o trecho inteiro do endereço ("Centro, Itu - SP" → trecho "itu"),
 *    ou com o fim de um trecho que não começa por tipo de logradouro/bairro
 *    ("Avenida São Paulo" e "Jardim São Paulo" NÃO são a capital);
 *  - se o destino cita Sorocaba ou Votorantim, não é intermunicipal;
 *  - "Salto de Pirapora" não é Salto.
 * Ordem: intermunicipal › periferia › zona quente.
 */
public enum SorocabaZone {
    static let abbreviations: [(String, String)] = [
        ("jd", "jardim"), ("jdim", "jardim"), ("pq", "parque"), ("pque", "parque"), ("vl", "vila"),
        ("res", "residencial"), ("av", "avenida"), ("r", "rua"), ("rod", "rodovia"), ("al", "alameda"),
        ("sta", "santa"), ("sto", "santo"),
    ]

    /// Palavras que indicam rua ou bairro (o nome que vem depois não é a cidade).
    static let placePrefixes: Set<String> = [
        "rua", "avenida", "rodovia", "estrada", "alameda", "travessa", "praca", "viela", "largo", "via",
        "jardim", "vila", "parque", "residencial", "conjunto", "bairro", "condominio", "chacara", "loteamento",
        "terminal", "shopping", "hospital", "escola",
    ]

    static let trailingNoise: Set<String> = ["sp", "brasil", "br"]

    /// Minúsculas, sem acento, abreviações expandidas, só letras/dígitos separados por espaço.
    public static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
        var out = ""
        var lastSpace = true
        for ch in folded.unicodeScalars {
            let isWord = (ch.value >= 97 && ch.value <= 122) || (ch.value >= 48 && ch.value <= 57)
            if isWord {
                out.unicodeScalars.append(ch)
                lastSpace = false
            } else if !lastSpace {
                out += " "
                lastSpace = true
            }
        }
        let tokens = out.split(separator: " ").map { t -> String in
            let w = String(t)
            return abbreviations.first { $0.0 == w }?.1 ?? w
        }
        return tokens.joined(separator: " ")
    }

    /// Trechos do endereço (separados por vírgula, ponto e vírgula, travessão, barra ou quebra de linha).
    static func segments(_ s: String) -> [String] {
        var parts = [s]
        for sep in [",", ";", "\n", " - ", " – ", " — ", "/", "|", "•", "·"] {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        return parts.map(normalize).filter { !$0.isEmpty }
    }

    static func containsWords(_ text: String, _ keyword: String) -> Bool {
        let k = normalize(keyword)
        guard !k.isEmpty else { return false }
        return (" " + text + " ").contains(" " + k + " ")
    }

    /// O trecho É a cidade (ignorando "SP"/"Brasil" no fim), ou termina com ela sem ser rua/bairro.
    static func segmentIsCity(_ segment: String, _ city: String) -> Bool {
        let c = normalize(city)
        guard !c.isEmpty else { return false }
        var tokens = segment.split(separator: " ").map(String.init)
        while let last = tokens.last, trailingNoise.contains(last), tokens.count > 1 { tokens.removeLast() }
        let seg = tokens.joined(separator: " ")
        if seg == c { return true }
        guard seg.hasSuffix(" " + c) else { return false }
        // "Centro Itu" casa; "Rua Itu" / "Jardim São Paulo" não.
        return !tokens.contains(where: placePrefixes.contains)
    }

    public static func classify(_ destination: String?, config: ZoneConfig = .sorocaba) -> ZoneMatch {
        guard let destination, !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .neutral }
        let whole = normalize(destination)
        // O endereço pode vir quebrado em linhas: testa os trechos por linha e também com as linhas emendadas.
        var segs = segments(destination)
        for seg in segments(destination.replacingOccurrences(of: "\n", with: " ")) where !segs.contains(seg) { segs.append(seg) }

        let isHome = config.homeCities.contains { home in segs.contains { segmentIsCity($0, home) } }
        if !isHome {
            // Cidades com nome próprio antes da capital ("Itu, São Paulo" é Itu).
            let isCapital: (IntercityRule) -> Bool = { $0.cities.contains { normalize($0) == "sao paulo" } }
            let ordered = config.intercity.filter { !isCapital($0) } + config.intercity.filter(isCapital)
            for rule in ordered {
                if rule.landmarks.contains(where: { containsWords(whole, $0) }) {
                    return ZoneMatch(kind: .intercity, name: rule.name, minimumFare: rule.minimumFare)
                }
            }
            for rule in ordered {
                let hit = rule.cities.contains { city in segs.contains { segmentIsCity($0, city) } }
                if hit { return ZoneMatch(kind: .intercity, name: rule.name, minimumFare: rule.minimumFare) }
            }
        }
        if let k = config.periphery.first(where: { containsWords(whole, $0) }) {
            return ZoneMatch(kind: .periphery, name: k, minimumFare: nil)
        }
        if let k = config.hot.first(where: { containsWords(whole, $0) }) {
            return ZoneMatch(kind: .hot, name: k, minimumFare: nil)
        }
        return .neutral
    }
}
