import Foundation

public struct Box: Equatable, Sendable {
    public var left, top, right, bottom: Int
    public init(left: Int, top: Int, right: Int, bottom: Int) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }
    public var height: Int { bottom - top }
    public var centerY: Int { (top + bottom) / 2 }
}

public struct OcrLine: Equatable, Sendable {
    public var text: String
    public var box: Box?
    public init(_ text: String, box: Box? = nil) { self.text = text; self.box = box }
}

public struct OcrFrame: Equatable, Sendable {
    public var lines: [OcrLine]
    public var width: Int
    public var height: Int
    public init(lines: [OcrLine], width: Int = 0, height: Int = 0) {
        self.lines = lines; self.width = width; self.height = height
    }
    public static func fromText(_ text: String) -> OcrFrame {
        OcrFrame(lines: text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { OcrLine($0) })
    }
}

public struct ParseResult: Equatable, Sendable {
    public var offer: OfferData
    public var confidence: Double
    public var isOfferScreen: Bool
    public var orderInferred: Bool
    public var fareAmbiguous: Bool
    public var ocrCorrections: Int
    /// Parece um cartão de chamado (botão Aceitar ou rótulos), mas faltou ler valor ou distâncias.
    public var nearMiss: Bool = false
    /// A tela é do próprio Driver Intelligence (nunca é chamado).
    public var ownApp: Bool = false
    /// Texto que sobrou depois de tirar a nossa notificação (para diagnóstico).
    public var cleanedText: String = ""
}

/// Normalização de números lidos por OCR (pt-BR e internacional).
public enum NumberNormalizer {
    private static let confusable: [Character: Character] = ["O": "0", "o": "0", "I": "1", "l": "1", "|": "1"]

    public static func parse(_ raw: String, thousandsHint: Bool = false) -> Double? {
        let s = raw.filter { $0 != " " && $0 != "\u{00A0}" && $0 != "\u{202F}" }
        guard !s.isEmpty, s.contains(where: \.isNumber), s.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }) else { return nil }
        let commas = s.filter { $0 == "," }.count
        let dots = s.filter { $0 == "." }.count
        let lastComma = s.lastIndex(of: ",").map { s.distance(from: s.startIndex, to: $0) } ?? -1
        let lastDot = s.lastIndex(of: ".").map { s.distance(from: s.startIndex, to: $0) } ?? -1
        var n: String
        if commas > 0 && dots > 0 {
            n = lastComma > lastDot ? s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") : s.replacingOccurrences(of: ",", with: "")
        } else if commas > 0 {
            let decimals = s.count - lastComma - 1
            if commas > 1 || (decimals == 3 && thousandsHint) { n = s.replacingOccurrences(of: ",", with: "") } else { n = s.replacingOccurrences(of: ",", with: ".") }
        } else if dots > 0 {
            let decimals = s.count - lastDot - 1
            n = (dots > 1 || (decimals == 3 && thousandsHint)) ? s.replacingOccurrences(of: ".", with: "") : s
        } else {
            n = s
        }
        n = n.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard let v = Double(n), v.isFinite else { return nil }
        return v
    }

    /// Corrige O→0, l→1… só quando colados a dígitos. Retorna (texto, nº de correções).
    public static func fixDigitConfusions(_ text: String) -> (String, Int) {
        var chars = Array(text)
        var fixes = 0
        func isDigit(_ i: Int) -> Bool { i >= 0 && i < chars.count && chars[i].isASCII && chars[i].isNumber }
        for i in chars.indices {
            guard let rep = confusable[chars[i]] else { continue }
            let prev: Character? = i > 0 ? chars[i - 1] : nil
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            let prevDigit = isDigit(i - 1) || ((prev == "," || prev == ".") && isDigit(i - 2))
            let nextDigit = isDigit(i + 1) || ((next == "," || next == ".") && isDigit(i + 2))
            let prevLetter = prev.map { $0.isLetter && confusable[$0] == nil } ?? false
            let nextLetter = next.map { $0.isLetter && confusable[$0] == nil } ?? false
            if (prevDigit && !nextLetter) || (nextDigit && !prevLetter) || (prevDigit && nextDigit) {
                chars[i] = rep
                fixes += 1
            }
        }
        return (String(chars), fixes)
    }
}

/// Extrai os dados da oferta do texto da tela (mesma lógica do Android).
public struct OfferTextParser: Sendable {
    public init() {}

    private enum Label { case pickup, trip, unlabeled }
    private struct Pair {
        var minutes: Double?; var km: Double; var label: Label; var start: Int; var line: Int
        var endLine: Int = 0
        var meters = false
        /// Par confiável: tem tempo e distância, ou veio com rótulo ("de distância", "viagem").
        var strong: Bool { (minutes != nil || label != .unlabeled) && !(meters && minutes == nil) }
    }
    private struct Money { var value: Double; var line: Int; var start: Int; var isPlus: Bool; var rate: String?; var isExtra: Bool }

    static func rx(_ p: String, _ ci: Bool = true) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: ci ? [.caseInsensitive] : [])
    }

    static let money = rx(#"(\+\s?)?(?:R\s?[$S5]|\$)\s?(\d{1,4}(?:[.,]\d{3})*(?:[.,]\d{1,2})?)(?!\d)(\s?/\s?(?:km|hr|hora|h|min))?"#)
    static let pair = rx(#"(?:(\d{1,2})\s*h(?:oras?|r)?\s*)?(?:(\d{1,3}(?:[.,]\d)?)\s*(?:minutos|minuto|mins|min)\.?\s*)?[(\[{]?\s*(\d{1,3}(?:[.,]\d{1,3})?)\s*(km|mi|m)(?![a-zA-Z])\s*[)\]}]?"#)
    static let pairReversed = rx(#"(\d{1,3}(?:[.,]\d{1,3})?)\s*(km|mi)(?![a-zA-Z])\s*[·•,|\-–]?\s*[(\[{]?\s*(?:(\d{1,2})\s*h\s*)?(\d{1,3})\s*(?:minutos|minuto|mins|min)"#)
    static let distanceOnly = rx(#"\d+(?:[.,]\d+)?\s*(?:km|mi)(?![a-zA-Z])"#)
    static let category = rx(#"\b(Uber\s?XL|Uber\s?X|Comfort|Black\s?Bag|Black|Uber\s?Flash|Flash\s?Moto|Flash|Uber\s?Moto|Moto|Juntos|Promo|Prioridade|Priority|Pet|Envios|Exclusivo|99Pop|99Moto|Pop|Comfort)\b"#)
    static let rating = rx(#"[★*][ \t]*(\d[.,]\d{1,2})|(\d[.,]\d{1,2})[ \t]*[★*]"#, false)

    static let categoryCanonical: [String: String] = [
        "uberx": "UberX", "uberxl": "UberXL", "comfort": "Comfort", "black": "Black", "blackbag": "Black Bag",
        "uberflash": "Flash", "flash": "Flash", "flashmoto": "Flash Moto", "ubermoto": "Moto", "moto": "Moto",
        "juntos": "Juntos", "promo": "Promo", "prioridade": "Prioridade", "priority": "Prioridade", "pet": "Pet",
        "envios": "Envios", "exclusivo": "Exclusivo", "99pop": "99Pop", "99moto": "99Moto", "pop": "99Pop",
    ]
    static let tripKeywords = ["viagem", "trip", "percurso", "corrida de"]
    static let pickupKeywords = ["de distancia", "distancia", "away", "embarque", "ate voce", "ate o passageiro", "pickup"]
    static let pickupSuffixLines = ["de distancia", "distancia", "away"]
    static let acceptKeywords = ["aceitar", "accept", "toque para aceitar", "selecionar", "aceitar corrida", "aceitar viagem"]

    // Nossa própria notificação e o nosso próprio app aparecem na tela gravada: nunca são chamado.
    /// Título da notificação: "🟢 ACEITAR · R$ 19,20" (o emoji pode virar qualquer coisa no OCR).
    static let ownTitle = rx(#"^.{0,4}(ACEITAR|AVALIAR|RECUSAR|CONFERIR|RENTÁVEL|MODERADA|ABAIXO DA META|INCOMPLETO)\b.{0,4}(R\s?[$S5]|Lucro)"#, false)
    /// Linhas do corpo da notificação.
    static let ownBody = rx(#"^.{0,3}(Busca \d|Lucro[: ]|Total \d|Motivo|Volta Vazia|Zona quente|Intermunicipal|Corrida aceita|Corrida conclu|Tempo real|Leitura encerrada)"#)
    static let ownTabs: Set<String> = ["inicio", "painel", "historico", "ajustes", "prints"]
    static let bareMoney = rx(#"^\s*(\d{1,3}[.,]\d{2})\s*$"#)

    /// Tira da leitura as linhas da nossa notificação (e tudo na faixa da tela que ela ocupa).
    static func dropOwnContent(_ frame: OcrFrame) -> (lines: [OcrLine], ownApp: Bool) {
        func isOwnLine(_ t: String) -> Bool {
            let u = t.uppercased()
            if u.contains("DRIVER INTELLIGENCE") || u.hasPrefix("DI ·") { return true }
            let n = t.lowercased()
            if n.contains("/km") && n.contains("/h") { return true } // "R$ 2,16/km · R$ 54/h"
            let r = NSRange(location: 0, length: (t as NSString).length)
            return ownTitle.firstMatch(in: t, range: r) != nil
        }
        func isOwnBody(_ t: String) -> Bool {
            ownBody.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) != nil
        }
        let tabs = frame.lines.filter { ownTabs.contains(normalize($0.text).trimmingCharacters(in: .whitespaces)) }.count
        let ownApp = tabs >= 3

        let geometry = frame.height > 0 && !frame.lines.isEmpty && frame.lines.allSatisfy { $0.box != nil }
        var out: [OcrLine] = []
        if geometry {
            // Uma notificação ocupa até ~17% da altura da tela abaixo do título.
            let bands: [ClosedRange<Int>] = frame.lines.filter { isOwnLine($0.text) }.map {
                let top = $0.box!.top
                return (top - frame.height / 50)...(top + frame.height * 17 / 100)
            }
            out = frame.lines.filter { l in
                if isOwnLine(l.text) || isOwnBody(l.text) { return false }
                return !bands.contains { $0.contains(l.box!.top) }
            }
        } else {
            var inBanner = false
            for l in frame.lines {
                if isOwnLine(l.text) { inBanner = true; continue }
                if isOwnBody(l.text) || (inBanner && l.text.hasPrefix("→")) { continue }
                inBanner = false
                out.append(l)
            }
        }
        return (out, ownApp)
    }

    /// Ordena por linha visual (mesma altura = mesma linha, da esquerda para a direita).
    static func rowSorted(_ lines: [OcrLine]) -> [OcrLine] {
        guard !lines.isEmpty, lines.allSatisfy({ $0.box != nil }) else { return lines }
        let byTop = lines.sorted { $0.box!.centerY < $1.box!.centerY }
        var rows: [[OcrLine]] = []
        for l in byTop {
            if let first = rows.last?.first, abs(l.box!.centerY - first.box!.centerY) <= max(4, min(first.box!.height, l.box!.height) / 2) {
                rows[rows.count - 1].append(l)
            } else {
                rows.append([l])
            }
        }
        return rows.flatMap { $0.sorted { $0.box!.left < $1.box!.left } }
    }
    static let rejectKeywords = ["recusar", "decline", "x"]
    static let extraKeywords = ["inclui", "incluido", "dinamic", "promo", "gorjeta", "bonus", "taxa", "surge", "boost", "includes", "adicional"]

    public static func normalize(_ s: String) -> String {
        s.lowercased().folding(options: [.diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
    }

    public func parse(_ frame: OcrFrame) -> ParseResult {
        var corrections = 0
        let own = Self.dropOwnContent(frame)
        if own.ownApp {
            return ParseResult(offer: OfferData(), confidence: 0, isOfferScreen: false, orderInferred: false,
                               fareAmbiguous: false, ocrCorrections: 0, nearMiss: false, ownApp: true, cleanedText: "")
        }
        let raw = Self.rowSorted(own.lines)
        let lines: [OcrLine] = raw.map { l in
            let (fixed, n) = NumberNormalizer.fixDigitConfusions(l.text.replacingOccurrences(of: "\u{00A0}", with: " ").trimmingCharacters(in: .whitespaces))
            corrections += n
            return OcrLine(fixed, box: l.box)
        }
        let hasGeometry = !lines.isEmpty && lines.allSatisfy { $0.box != nil }
        let text = lines.map(\.text).joined(separator: "\n")
        let ns = text as NSString
        var lineStarts: [Int] = []
        var pos = 0
        for l in lines { lineStarts.append(pos); pos += (l.text as NSString).length + 1 }
        func lineOf(_ index: Int) -> Int {
            var ans = 0
            for (i, s) in lineStarts.enumerated() where s <= index { ans = i }
            return ans
        }
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        let full = NSRange(location: 0, length: ns.length)

        // Valores monetários
        let monies: [Money] = Self.money.matches(in: text, range: full).compactMap { m in
            guard let num = group(m, 2), let v = NumberNormalizer.parse(num, thousandsHint: true) else { return nil }
            let li = lineOf(m.range.location)
            let lineNorm = Self.normalize(lines.indices.contains(li) ? lines[li].text : "")
            let rate = group(m, 3).map { Self.normalize($0).replacingOccurrences(of: "/", with: "").trimmingCharacters(in: .whitespaces) }
            return Money(value: v, line: li, start: m.range.location, isPlus: group(m, 1) != nil, rate: rate, isExtra: Self.extraKeywords.contains { lineNorm.contains($0) })
        }

        // Pares tempo + distância
        var pairs = findPairs(ns, Self.pair, reversed: false, lineOf: lineOf)
        if !pairs.isEmpty && pairs.allSatisfy({ $0.minutes == nil }) {
            let alt = findPairs(ns, Self.pairReversed, reversed: true, lineOf: lineOf)
            if alt.contains(where: { $0.minutes != nil }) { pairs = alt }
        }
        // Distância solta ("300 m" da navegação, "8,9 km" de um resumo) não é par de chamado.
        pairs = pairs.filter(\.strong)
        var pickup = pairs.first { $0.label == .pickup }
        var trip = pairs.first { $0.label == .trip }
        let unlabeled = pairs.filter { $0.label == .unlabeled }
        var inferred = false
        if pickup == nil && trip == nil {
            if unlabeled.count >= 2 { pickup = unlabeled[0]; trip = unlabeled[1]; inferred = true }
        } else if pickup == nil, let t = trip {
            pickup = unlabeled.last { $0.start < t.start }
            if pickup != nil { inferred = true }
        } else if trip == nil, let p = pickup {
            trip = unlabeled.first { $0.start > p.start }
            if trip != nil { inferred = true }
        }
        let extraPairs = max(0, pairs.count - [pickup, trip].compactMap { $0 }.count)

        // Valor da corrida
        var candidates = monies.filter { !$0.isPlus && $0.rate == nil && !$0.isExtra }
        var fareFromBareNumber = false
        if hasGeometry, let t = trip ?? pickup {
            // O valor fica acima das distâncias, dentro do mesmo cartão.
            let limitY = lines[t.line].box!.centerY
            let span = Int(Double(frame.height > 0 ? frame.height : 2400) * 0.6)
            let inCard = candidates.filter { let y = lines[$0.line].box!.centerY; return y <= limitY && limitY - y <= span }
            if !inCard.isEmpty { candidates = inCard }
        }
        if candidates.isEmpty, pickup != nil || trip != nil {
            // "R$" lido separado do número (fonte menor): aceita um número solto com centavos acima das distâncias.
            let firstPairLine = [pickup, trip].compactMap { $0?.line }.min() ?? 0
            let bare: [Money] = lines.enumerated().compactMap { i, l in
                guard i < firstPairLine else { return nil }
                let r = NSRange(location: 0, length: (l.text as NSString).length)
                guard let m = Self.bareMoney.firstMatch(in: l.text, range: r),
                      let v = NumberNormalizer.parse((l.text as NSString).substring(with: m.range(at: 1))), v >= 3 else { return nil }
                return Money(value: v, line: i, start: lineStarts[i], isPlus: false, rate: nil, isExtra: false)
            }
            if hasGeometry, let tallest = bare.max(by: { lines[$0.line].box!.height < lines[$1.line].box!.height }) {
                candidates = [tallest]
                fareFromBareNumber = true
            } else if bare.count == 1 {
                candidates = bare
                fareFromBareNumber = true
            }
        }
        var ambiguous = false
        var fareHit: Money?
        if candidates.count == 1 {
            fareHit = candidates[0]
        } else if candidates.count > 1 {
            if hasGeometry {
                let heights = candidates.map { Double(max(1, lines[$0.line].box!.height)) }
                let maxH = heights.max()!
                let anchorTop = (pickup ?? trip).map { lines[$0.line].box!.top }
                let span = frame.height > 0 ? Double(frame.height) * 0.35 : 600
                let scored = candidates.enumerated().map { i, hit -> (Money, Double) in
                    let prox = anchorTop.map { 1 - min(1, abs(Double(lines[hit.line].box!.centerY - $0)) / span) } ?? 0
                    return (hit, 0.6 * heights[i] / maxH + 0.4 * prox)
                }.sorted { $0.1 > $1.1 }
                if scored.count > 1 && scored[0].1 - scored[1].1 < 0.08 && scored[0].0.value != scored[1].0.value { ambiguous = true }
                fareHit = scored[0].0
            } else {
                let firstPair = [pickup, trip].compactMap { $0?.start }.min()
                let before = firstPair.map { fp in candidates.filter { $0.start < fp } } ?? []
                if Set(candidates.map(\.value)).count > 1 && before.count != 1 { ambiguous = true }
                fareHit = before.last ?? candidates.first
            }
        }

        let surge = monies.filter { $0.isPlus || $0.isExtra }.map(\.value).max()
        let displayedRate = monies.first { $0.rate == "km" }?.value
        let category = Self.category.firstMatch(in: text, range: full).map { m -> String in
            let r = ns.substring(with: m.range)
            return Self.categoryCanonical[r.lowercased().replacingOccurrences(of: " ", with: "")] ?? r
        }
        let rating = Self.rating.matches(in: text, range: full).lazy.compactMap { m -> Double? in
            (group(m, 1) ?? group(m, 2)).flatMap { NumberNormalizer.parse($0) }.flatMap { (1...5).contains($0) ? $0 : nil }
        }.first

        // Âncoras do cartão: botão de aceitar (linha própria), rótulos das distâncias, categoria ou nota.
        let hasAccept = lines.contains { l in
            let n = Self.normalize(l.text).trimmingCharacters(in: .whitespaces)
            return Self.acceptKeywords.contains { n == $0 || n.hasPrefix($0 + " ") }
        }
        let hasLabels = pairs.contains { $0.label != .unlabeled }
        let anchored = hasAccept || hasLabels || category != nil || rating != nil
        // Lista de várias viagens (radar): muitos valores e muitos pares na mesma tela.
        let isList = Set(candidates.map(\.value)).count >= 3 && pairs.count >= 4
        // Chamado = valor + busca + viagem + pelo menos uma âncora. Menos que isso não vira notificação.
        let isOffer = fareHit != nil && pickup != nil && trip != nil && anchored && !isList
        let nearMiss = !isOffer && !isList && (hasAccept || hasLabels) && (fareHit != nil || !pairs.isEmpty)

        var conf = 0.0
        if fareHit != nil { conf += 0.35 }
        if let p = pickup { conf += p.minutes != nil ? 0.25 : 0.18 }
        if let t = trip { conf += t.minutes != nil ? 0.25 : 0.18 }
        if pickup != nil && trip != nil { conf += inferred ? 0.07 : 0.15 }
        conf -= min(0.15, 0.05 * Double(corrections))
        if ambiguous { conf -= 0.20 }
        if fareFromBareNumber { conf -= 0.15 }
        conf -= min(0.10, 0.05 * Double(extraPairs))
        conf = min(1, max(0, conf))

        let offer = OfferData(
            fare: fareHit?.value,
            pickupDistanceKm: pickup?.km,
            tripDistanceKm: trip?.km,
            pickupTimeMin: pickup?.minutes,
            tripTimeMin: trip?.minutes,
            category: category,
            origin: pickup.flatMap { addressAfter(lines, $0.endLine, maxLines: 2) },
            destination: trip.flatMap { addressAfter(lines, $0.endLine, maxLines: 3) },
            surgeAmount: surge,
            displayedRatePerKm: displayedRate,
            passengerRating: rating
        )
        return ParseResult(offer: offer, confidence: conf, isOfferScreen: isOffer, orderInferred: inferred, fareAmbiguous: ambiguous,
                           ocrCorrections: corrections, nearMiss: nearMiss, ownApp: false, cleanedText: text)
    }

    private func findPairs(_ ns: NSString, _ regex: NSRegularExpression, reversed: Bool, lineOf: (Int) -> Int) -> [Pair] {
        let text = ns as String
        var out: [Pair] = []
        func g(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let hoursRaw, minutesRaw, distRaw, unitRaw: String?
            if !reversed {
                hoursRaw = g(m, 1); minutesRaw = g(m, 2); distRaw = g(m, 3); unitRaw = g(m, 4)
            } else {
                distRaw = g(m, 1); unitRaw = g(m, 2); hoursRaw = g(m, 3); minutesRaw = g(m, 4)
            }
            guard let distRaw, let unitRaw, let rawKm = NumberNormalizer.parse(distRaw) else { continue }
            let km: Double
            switch unitRaw.lowercased() {
            case "m": km = rawKm / 1000
            case "mi": km = rawKm * 1.609344
            default: km = rawKm
            }
            let h = hoursRaw.flatMap { NumberNormalizer.parse($0) }
            let mi = minutesRaw.flatMap { NumberNormalizer.parse($0) }
            let minutes: Double? = (h == nil && mi == nil) ? nil : (h ?? 0) * 60 + (mi ?? 0)

            let start = m.range.location
            let end = m.range.location + m.range.length
            func lastNewline(before i: Int) -> Int {
                guard i > 0 else { return -1 }
                let r = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: min(i, ns.length)))
                return r.location == NSNotFound ? -1 : r.location
            }
            func nextNewline(from i: Int) -> Int {
                guard i < ns.length else { return ns.length }
                let r = ns.range(of: "\n", range: NSRange(location: i, length: ns.length - i))
                return r.location == NSNotFound ? ns.length : r.location
            }
            let lineStart = lastNewline(before: start) + 1
            let prevLineStart = lineStart <= 1 ? 0 : lastNewline(before: lineStart - 1) + 1
            let lineEnd = nextNewline(from: end)
            let n = OfferTextParser.normalize
            let sameBefore = n(ns.substring(with: NSRange(location: lineStart, length: start - lineStart)))
            let prevLine = n(ns.substring(with: NSRange(location: prevLineStart, length: max(0, lineStart - prevLineStart)))).trimmingCharacters(in: .whitespacesAndNewlines)
            let after = n(ns.substring(with: NSRange(location: end, length: max(0, lineEnd - end))))
            var nextLine = ""
            if lineEnd < ns.length {
                let e = nextNewline(from: lineEnd + 1)
                nextLine = n(ns.substring(with: NSRange(location: lineEnd + 1, length: e - lineEnd - 1))).trimmingCharacters(in: .whitespaces)
            }
            let label: Label
            if Self.tripKeywords.contains(where: { sameBefore.contains($0) || after.contains($0) }) {
                label = .trip
            } else if Self.pickupKeywords.contains(where: { sameBefore.contains($0) || after.contains($0) }) {
                label = .pickup
            } else if Self.tripKeywords.contains(where: { prevLine == $0 || prevLine.hasPrefix("\($0) ") || prevLine.hasPrefix("\($0):") }) {
                label = .trip
            } else if Self.pickupSuffixLines.contains(nextLine) {
                label = .pickup
            } else {
                label = .unlabeled
            }
            out.append(Pair(minutes: minutes, km: km, label: label, start: start, line: lineOf(start),
                            endLine: lineOf(max(start, end - 1)), meters: unitRaw.lowercased() == "m"))
        }
        return out
    }

    /// Endereço logo abaixo do par (pode ocupar mais de uma linha; as linhas ficam separadas por "\n").
    private func addressAfter(_ lines: [OcrLine], _ pairLine: Int, maxLines: Int) -> String? {
        guard pairLine + 1 < lines.count else { return nil }
        var parts: [String] = []
        var i = pairLine + 1
        var skipped = 0
        while i < lines.count, parts.count < maxLines {
            let t = lines[i].text.trimmingCharacters(in: .whitespaces)
            let n = Self.normalize(t)
            i += 1
            if n.isEmpty || Self.pickupSuffixLines.contains(n) || n == "de viagem" || n == "viagem" {
                skipped += 1
                if skipped > 2 { break }
                continue
            }
            let r = NSRange(location: 0, length: (t as NSString).length)
            if Self.money.firstMatch(in: t, range: r) != nil || Self.distanceOnly.firstMatch(in: t, range: r) != nil { break }
            if Self.pair.firstMatch(in: t, range: r) != nil || Self.rating.firstMatch(in: t, range: r) != nil { break }
            if Self.acceptKeywords.contains(where: { n == $0 || n.hasPrefix($0 + " ") }) || Self.rejectKeywords.contains(n) { break }
            if Self.tripKeywords.contains(where: { n == $0 || n.hasPrefix("\($0) ") || n.hasPrefix("\($0):") }) { break }
            if n.range(of: #"^\d{1,3}\s*(min|minutos?)\b"#, options: .regularExpression) != nil { break }
            guard t.filter(\.isLetter).count >= 3 else { break }
            parts.append(String(t.prefix(80)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}
