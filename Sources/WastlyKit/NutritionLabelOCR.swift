import CoreGraphics
import Foundation
import ImageIO
@preconcurrency import Vision

public struct RecognizedLabelLine: Equatable, Sendable {
    public var text: String
    public var confidence: Double

    public init(text: String, confidence: Double) {
        self.text = text
        self.confidence = confidence
    }
}

public struct NutritionLabelScan: Equatable, Sendable {
    public var lines: [RecognizedLabelLine]
    public var energyKilojoulesPer100g: Double?
    public var energyKilojoulesPerServing: Double?
    public var servingGrams: Double?
    public var confidence: Double

    public init(
        lines: [RecognizedLabelLine],
        energyKilojoulesPer100g: Double?,
        energyKilojoulesPerServing: Double?,
        servingGrams: Double?,
        confidence: Double
    ) {
        self.lines = lines
        self.energyKilojoulesPer100g = energyKilojoulesPer100g
        self.energyKilojoulesPerServing = energyKilojoulesPerServing
        self.servingGrams = servingGrams
        self.confidence = confidence
    }
}

public enum NutritionLabelOCRError: Error, LocalizedError, Sendable {
    case unreadableImage

    public var errorDescription: String? {
        "That label image couldn’t be read. Try a brighter, straighter photo."
    }
}

/// Runs Apple's on-device Vision text recognizer. Image bytes stay in memory and are never uploaded.
public actor NutritionLabelOCR {
    public init() {}

    public func recognize(imageData: Data) throws -> NutritionLabelScan {
        guard let image = Self.downsampledImage(from: imageData) else {
            throw NutritionLabelOCRError.unreadableImage
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.customWords = ["kJ", "kcal", "serving"]
        request.minimumTextHeight = 0.012

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try handler.perform([request])
        let observations = (request.results ?? []).sorted { lhs, rhs in
            let verticalDistance = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
            if verticalDistance > 0.02 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        let lines = observations.compactMap { observation -> RecognizedLabelLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLabelLine(
                text: candidate.string,
                confidence: Double(candidate.confidence)
            )
        }
        return NutritionLabelParser.parse(lines: lines)
    }

    private static func downsampledImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_400,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

public enum NutritionLabelParser: Sendable {
    public static func parse(lines: [RecognizedLabelLine]) -> NutritionLabelScan {
        var per100g: Double?
        var perServing: Double?

        for (index, line) in lines.enumerated() {
            guard let reading = energyReading(in: line.text) else { continue }
            let contextStart = max(lines.startIndex, index - 1)
            let context = lines[contextStart...index]
                .map(\.text)
                .joined(separator: " ")
                .lowercased()
            if context.range(
                of: #"per\s*100\s*g"#,
                options: .regularExpression
            ) != nil {
                per100g = reading
            } else if context.range(
                of: #"per\s*serv"#,
                options: .regularExpression
            ) != nil {
                perServing = reading
            }
        }

        let joined = lines.map(\.text).joined(separator: " ")
        let servingGrams = servingSize(in: joined)
        if per100g == nil,
           let perServing,
           let servingGrams,
           servingGrams > 0 {
            per100g = perServing * 100 / servingGrams
        }
        if perServing == nil,
           let per100g,
           let servingGrams {
            perServing = per100g * servingGrams / 100
        }

        let confidence = lines.isEmpty
            ? 0
            : lines.map(\.confidence).reduce(0, +) / Double(lines.count)
        return NutritionLabelScan(
            lines: lines,
            energyKilojoulesPer100g: finite(per100g),
            energyKilojoulesPerServing: finite(perServing),
            servingGrams: finite(servingGrams),
            confidence: min(1, max(0, confidence))
        )
    }

    private static func energyReading(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(
            pattern: #"([0-9]+(?:[.,][0-9]+)?)\s*(kcal|kj)\b"#,
            options: .caseInsensitive
        ) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = parseNumber(String(text[valueRange]))
        else { return nil }
        let unit = text[unitRange]
        return unit.caseInsensitiveCompare("kcal") == .orderedSame
            ? Energy.kilojoules(fromKilocalories: value)
            : value
    }

    private static func servingSize(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(
            pattern: #"serving\s*size\s*[:\-]?\s*([0-9]+(?:[.,][0-9]+)?)\s*g\b"#,
            options: .caseInsensitive
        ) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return parseNumber(String(text[valueRange]))
    }

    private static func parseNumber(_ raw: String) -> Double? {
        if raw.contains(","), !raw.contains(".") {
            let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 2, parts[1].count == 3 {
                return Double(parts.joined())
            }
            return Double(raw.replacingOccurrences(of: ",", with: "."))
        }
        return Double(raw.replacingOccurrences(of: ",", with: ""))
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}
