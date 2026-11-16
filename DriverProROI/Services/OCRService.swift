import Foundation
import UIKit
import Vision

/// Valores extraídos de um print do resumo diário (Uber ou 99).
struct OCRResult {
    var total: Double?
    var tips: Double?
    var promotions: Double?
    var trips: Int?
    var onlineHours: Double?
    var suggestedCategory: RideCategory = .uberX
    var lines: [String] = []

    var hasData: Bool {
        total != nil || tips != nil || promotions != nil || trips != nil || onlineHours != nil
    }
}

enum OCRError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "Não foi possível ler a imagem selecionada."
    }
}

/// Leitor OCR de prints usando Apple Vision (VNRecognizeTextRequest), 100% no aparelho.
enum OCRService {
    static func recognize(_ image: UIImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage else { throw OCRError.invalidImage }
        let lines = try await Task.detached(priority: .userInitiated) { () throws -> [String] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["pt-BR", "en-US"]
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            let observations = request.results ?? []
            return observations.compactMap { $0.topCandidates(1).first?.string }
        }.value
        return OCRParser.parse(lines: lines)
    }
}

/// Heurísticas de leitura dos resumos de ganhos em português.
enum OCRParser {
    private static let moneyPattern = #"R\$\s*(\d{1,3}(?:\.\d{3})*,\d{2}|\d+,\d{2}|\d+)"#
    private static let tripsPattern = #"(\d{1,3})\s*(?:viagens|viagem|corridas|corrida)"#
    private static let durationPattern = #"(\d{1,2})\s*h(?:oras?|rs?)?\s*(?:e\s*)?(?:(\d{1,2})\s*(?:min|m)?)?"#
    private static let clockPattern = #"\b(\d{1,2}):(\d{2})(?::\d{2})?\b"#

    static func parse(lines: [String]) -> OCRResult {
        var result = OCRResult()
        result.lines = lines
        let lowered = lines.map { $0.lowercased() }
        let joined = lowered.joined(separator: " ")

        if joined.contains("99pop") || joined.contains("99 pop") || joined.contains("99app") {
            result.suggestedCategory = .pop99
        } else if joined.contains("comfort") {
            result.suggestedCategory = .comfort
        } else {
            result.suggestedCategory = .uberX
        }

        var allValues: [Double] = []
        for (index, line) in lowered.enumerated() {
            let values = moneyValues(in: line)
            allValues.append(contentsOf: values)
            let nearby = values.first ?? moneyNear(index: index, in: lowered)

            if line.contains("gorjeta") {
                if result.tips == nil { result.tips = nearby }
            } else if line.contains("promo") || line.contains("dinâmic") || line.contains("dinamic")
                        || line.contains("desafio") || line.contains("incentivo") || line.contains("bônus") || line.contains("bonus") {
                if let nearby { result.promotions = (result.promotions ?? 0) + nearby }
            } else if line.contains("ganhos") || line.contains("total") || line.contains("saldo") || line.contains("faturamento") {
                if let nearby, nearby > (result.total ?? 0) { result.total = nearby }
            }

            if result.trips == nil {
                if let match = matches(tripsPattern, in: line).first, let count = Int(match[1]) {
                    result.trips = count
                } else if line.contains("viagens") || line.contains("corridas") {
                    result.trips = integerNear(index: index, in: lowered)
                }
            }

            if result.onlineHours == nil,
               line.contains("online") || line.contains("tempo") || line.contains("horas") || line.contains("conectado") {
                result.onlineHours = duration(in: line) ?? durationNear(index: index, in: lowered)
            }
        }

        if result.total == nil {
            result.total = allValues.max()
        }
        if result.onlineHours == nil {
            for line in lowered {
                if let match = matches(durationPattern, in: line).first, !match[2].isEmpty,
                   let hours = Double(match[1]), let minutes = Double(match[2]) {
                    result.onlineHours = hours + minutes / 60
                    break
                }
            }
        }
        return result
    }

    private static func parseNumber(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
    }

    private static func moneyValues(in line: String) -> [Double] {
        matches(moneyPattern, in: line).compactMap { parseNumber($0[1]) }
    }

    private static func moneyNear(index: Int, in lines: [String]) -> Double? {
        for offset in [1, -1, 2] {
            let position = index + offset
            guard lines.indices.contains(position) else { continue }
            if let value = moneyValues(in: lines[position]).first { return value }
        }
        return nil
    }

    private static func integerNear(index: Int, in lines: [String]) -> Int? {
        for offset in [1, -1] {
            let position = index + offset
            guard lines.indices.contains(position) else { continue }
            let candidate = lines[position].trimmingCharacters(in: .whitespaces)
            if candidate.count <= 3, let value = Int(candidate) { return value }
        }
        return nil
    }

    private static func duration(in line: String) -> Double? {
        if let match = matches(durationPattern, in: line).first, let hours = Double(match[1]) {
            let minutes = Double(match[2]) ?? 0
            return hours + minutes / 60
        }
        if let match = matches(clockPattern, in: line).first,
           let hours = Double(match[1]), let minutes = Double(match[2]) {
            return hours + minutes / 60
        }
        return nil
    }

    private static func durationNear(index: Int, in lines: [String]) -> Double? {
        for offset in [1, -1] {
            let position = index + offset
            guard lines.indices.contains(position) else { continue }
            if let value = duration(in: lines[position]) { return value }
        }
        return nil
    }

    /// Retorna, para cada ocorrência, os grupos capturados (índice 0 = ocorrência inteira).
    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let source = text as NSString
        let range = NSRange(location: 0, length: source.length)
        return regex.matches(in: text, options: [], range: range).map { match in
            (0..<match.numberOfRanges).map { group in
                let groupRange = match.range(at: group)
                return groupRange.location == NSNotFound ? "" : source.substring(with: groupRange)
            }
        }
    }
}
