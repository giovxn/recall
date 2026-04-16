import Vision
import UIKit
import CoreImage

struct MemoryAnalysis {
    var classification: String
    var smartLabel: String
    var detectedText: [String]
    var dominantColor: UIColor
}

class VisionAnalyzer {
    static let shared = VisionAnalyzer()
    private let ocrMinConfidence: Float = 0.55
    private let ocrFallbackConfidence: Float = 0.28
    
    func analyze(imageData: Data, completion: @escaping (MemoryAnalysis) -> Void) {
        guard let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else { return }
        
        var classification = "memory"
        var detectedText: [String] = []
        var textWithSizes: [(text: String, size: CGFloat)] = []
        let dominantColor = extractDominantColor(from: uiImage)
        
        let group = DispatchGroup()
        
        group.enter()
        let textRequest = VNRecognizeTextRequest { request, _ in
            defer { group.leave() }
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            for observation in observations {
                guard let candidate = self.bestTextCandidate(from: observation) else { continue }
                let text = Self.normalizeOCRText(candidate.string)
                guard !text.isEmpty else { continue }
                let size = observation.boundingBox.height
                detectedText.append(text)
                textWithSizes.append((text: text, size: size))
            }
            textWithSizes.sort { $0.size > $1.size }
            detectedText = Self.deduplicatedText(detectedText)
        }
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.minimumTextHeight = 0.02
        
        group.enter()
        let classifyRequest = VNClassifyImageRequest { request, _ in
            defer { group.leave() }
            guard let observations = request.results as? [VNClassificationObservation] else { return }
            let top = observations.filter { $0.confidence > 0.2 }.prefix(3)
            classification = Self.mapClassification(top.map { $0.identifier })
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([textRequest, classifyRequest])
        
        group.notify(queue: .main) {
            let smartLabel = Self.buildSmartLabel(
                classification: classification,
                detectedText: detectedText,
                textWithSizes: textWithSizes
            )
            let inferredFromLabel = Self.inferClassification(fromSmartLabel: smartLabel)
            if inferredFromLabel != "memory" {
                classification = inferredFromLabel
            } else if let inferredFromText = Self.inferClassification(fromText: detectedText) {
                classification = inferredFromText
            }
            let analysis = MemoryAnalysis(
                classification: classification,
                smartLabel: smartLabel,
                detectedText: detectedText,
                dominantColor: dominantColor
            )
            completion(analysis)
        }
    }
    
    // MARK: - Smart Label
    private static func buildSmartLabel(
        classification: String,
        detectedText: [String],
        textWithSizes: [(text: String, size: CGFloat)]
    ) -> String {
        
        // Unified text context — handles both parking and plates
        if let contextLabel = extractTextContext(from: textWithSizes) {
            return contextLabel
        }
        
        let usefulText = prioritizedContextText(
            from: textWithSizes,
            classification: classification
        )
        
        switch classification {
        case "parking":
            return usefulText.first.map { "Parking · \($0)" } ?? "Parking spot"
        case "luggage":
            return "Luggage"
        case "food":
            return usefulText.first.map { "Food · \($0)" } ?? "Food"
        case "shop":
            return usefulText.first.map { "Shop · \($0)" } ?? "Shop"
        case "document":
            return usefulText.first.map { "Note · \($0)" } ?? "Document"
        case "person":
            return "Person"
        case "place":
            return usefulText.first ?? "Place"
        default:
            return usefulText.first ?? "Memory"
        }
    }
    
    // MARK: - Unified Text Context (parking vs plate decision tree)
    private static func extractTextContext(from textWithSizes: [(text: String, size: CGFloat)]) -> String? {
        let normalizedItems = textWithSizes
            .map { (text: normalizeOCRText($0.text), size: $0.size) }
            .filter { !$0.text.isEmpty }
        guard !normalizedItems.isEmpty else { return nil }

        let parkingStopWords = Set(["ROW", "CENTRAL", "GALLERIA", "STREET", "ROAD", "EXIT", "ENTRANCE", "IKEA"])
        let parkingKeywords = ["LEVEL", "FLOOR", "ZONE", "BASEMENT", "GROUND", "PARKING", "PARK"]
        let emirates = [
            "DUBAI", "ABU DHABI", "SHARJAH", "AJMAN", "RAK", "FUJAIRAH", "UAQ",
            "دبي", "أبوظبي", "الشارقة", "عجمان", "رأس الخيمة", "الفجيرة"
        ]

        func regexMatch(_ text: String, _ pattern: String) -> Bool {
            text.range(of: pattern, options: .regularExpression) != nil
        }

        // 1) Parking-first candidates (highest priority)
        var parkingCandidates: [(value: String, score: Double)] = []
        for item in normalizedItems {
            let text = item.text
            if parkingStopWords.contains(text) { continue }
            var score = Double(item.size) * 100

            if regexMatch(text, "^[PGBL][0-9]{1,3}\\s?[A-Z]{1,2}$") {
                // Examples: P3C, P3 C, B01, G8 A
                score += 60
                let compact = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                parkingCandidates.append((value: compact, score: score))
                continue
            }
            if regexMatch(text, "^[PGBL][0-9]{1,3}$") {
                // Examples: P1, B01, G8
                score += 42
                parkingCandidates.append((value: text, score: score))
                continue
            }
            if regexMatch(text, "^[A-Z][0-9]{1,3}$") || regexMatch(text, "^[0-9]{1,3}[A-Z]$") {
                // Examples: C8, 8C
                score += 34
                parkingCandidates.append((value: text, score: score))
                continue
            }
            if regexMatch(text, "^(LEVEL|L)\\s?[0-9]{1,2}$") {
                // Examples: LEVEL1, L1
                score += 26
                parkingCandidates.append((value: text.replacingOccurrences(of: "LEVEL", with: "L"), score: score))
            }
        }

        if !parkingCandidates.isEmpty {
            let sorted = parkingCandidates.sorted { $0.score > $1.score }
            let primary = sorted[0].value
            if let secondary = sorted.dropFirst().first(where: { $0.value != primary })?.value,
               secondary.count <= 4,
               regexMatch(secondary, "^([A-Z]{1,2}|[0-9]{1,3}[A-Z]?)$") {
                return "Parking · \(primary) \(secondary)"
            }
            return "Parking · \(primary)"
        }

        // 2) Explicit parking keywords fallback
        if let keywordText = normalizedItems.first(where: { item in
            parkingKeywords.contains(where: { item.text.contains($0) })
        })?.text {
            return "Parking · \(keywordText)"
        }

        // 3) Plate-like fallback
        let letterCodes = normalizedItems
            .filter { regexMatch($0.text, "^[A-Z]{1,3}$") }
            .sorted { $0.size > $1.size }
        let numbers = normalizedItems
            .filter { regexMatch($0.text, "^[0-9]{1,6}$") }
            .sorted { $0.size > $1.size }

        guard let bestNumber = numbers.first?.text else { return nil }
        let digits = bestNumber.count
        let emirateName = normalizedItems.first(where: { item in
            emirates.contains(where: { item.text.localizedCaseInsensitiveContains($0) })
        })?.text

        if let emirateName {
            let bestLetters = letterCodes.first?.text
            var parts = [emirateName]
            if let bestLetters { parts.append(bestLetters) }
            parts.append(bestNumber)
            return parts.joined(separator: " · ")
        }

        if digits >= 4, let bestLetters = letterCodes.first?.text {
            return "\(bestLetters) · \(bestNumber)"
        }
        if digits <= 3, let bestLetters = letterCodes.first?.text {
            return "Parking · \(bestLetters) \(bestNumber)"
        }
        if digits >= 4 { return bestNumber }
        if digits <= 3 { return "Parking · \(bestNumber)" }
        return nil
    }
    
    // MARK: - Classification mapping
    private static func mapClassification(_ identifiers: [String]) -> String {
        let joined = identifiers.joined(separator: " ").lowercased()
        if joined.contains("car") || joined.contains("vehicle") || joined.contains("automobile") { return "parking" }
        if joined.contains("baggage") || joined.contains("luggage") || joined.contains("suitcase") { return "luggage" }
        if joined.contains("food") || joined.contains("dish") || joined.contains("meal") { return "food" }
        if joined.contains("shop") || joined.contains("store") || joined.contains("retail") { return "shop" }
        if joined.contains("document") || joined.contains("text") || joined.contains("paper") { return "document" }
        if joined.contains("person") || joined.contains("face") { return "person" }
        if joined.contains("building") || joined.contains("architecture") { return "place" }
        return "memory"
    }
    
    private static func inferClassification(fromSmartLabel smartLabel: String) -> String {
        let lower = smartLabel.lowercased()
        if lower.contains("parking") { return "parking" }
        if lower.contains("luggage") { return "luggage" }
        if lower.contains("food") { return "food" }
        if lower.contains("shop") { return "shop" }
        if lower.contains("note") || lower.contains("document") { return "document" }
        if lower.contains("person") { return "person" }
        if lower.contains("place") { return "place" }
        return "memory"
    }
    
    private static func inferClassification(fromText detectedText: [String]) -> String? {
        let joined = detectedText.joined(separator: " ").lowercased()
        let parkingTokens = ["parking", "level", "basement", "zone", "floor", "p", "g", "b"]
        if parkingTokens.contains(where: { joined.contains($0) }) {
            return "parking"
        }
        return nil
    }
    
    private func bestTextCandidate(from observation: VNRecognizedTextObservation) -> VNRecognizedText? {
        let candidates = observation.topCandidates(3)
        if let strong = candidates.first(where: { $0.confidence >= ocrMinConfidence }) {
            return strong
        }
        if let fallback = candidates.first(where: { $0.confidence >= ocrFallbackConfidence }) {
            return fallback
        }
        guard let top = candidates.first else { return nil }
        // Keep a final fallback for short parking/plate-like tokens.
        let normalized = Self.normalizeOCRText(top.string)
        let hasParkingLikeToken = normalized.range(of: "^[PGBL][0-9]{1,3}(\\s?[A-Z]{1,2})?$", options: .regularExpression) != nil
            || normalized.range(of: "^[A-Z]{1,3}[0-9]{1,4}$", options: .regularExpression) != nil
        return hasParkingLikeToken ? top : nil
    }
    
    private static func normalizeOCRText(_ raw: String) -> String {
        var normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        normalized = normalized.replacingOccurrences(of: "[^A-Z0-9\\s\\-]", with: "", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: "\\s*\\-\\s*", with: "-", options: .regularExpression)
        normalized = normalized.trimmingCharacters(in: .whitespaces)
        return normalized
    }
    
    private static func deduplicatedText(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }
    
    private static func prioritizedContextText(
        from textWithSizes: [(text: String, size: CGFloat)],
        classification: String
    ) -> [String] {
        let stopPhrases = Set([
            "EXIT", "ENTRANCE", "PARKING", "LEVEL", "FLOOR", "STREET", "ROAD",
            "NO PARKING", "WAY OUT", "LIFT", "STAIRS"
        ])
        
        let ranked = textWithSizes.compactMap { item -> (text: String, score: Double)? in
            let text = item.text.trimmingCharacters(in: .whitespaces)
            guard text.count >= 2, text.count <= 22 else { return nil }
            if stopPhrases.contains(text) { return nil }
            
            let hasDigits = text.rangeOfCharacter(from: .decimalDigits) != nil
            let hasLetters = text.rangeOfCharacter(from: .letters) != nil
            var score = Double(item.size) * 100
            
            if hasDigits && hasLetters { score += 24 }
            if hasDigits && !hasLetters { score += 8 }
            if text.count <= 10 { score += 6 }
            if text.contains("-") { score += 4 }
            
            // Parking/document contexts benefit from compact, code-like tokens.
            if classification == "parking" || classification == "document" {
                if text.range(of: "^[A-Z]{1,3}[0-9]{1,4}$", options: .regularExpression) != nil {
                    score += 20
                }
                if text.range(of: "^[A-Z]{1,3}\\s?[0-9]{1,4}$", options: .regularExpression) != nil {
                    score += 12
                }
                if text.range(of: "^[PGBL][0-9]{1,3}\\s?[A-Z]{1,2}$", options: .regularExpression) != nil {
                    score += 30
                }
                if text.range(of: "^[PGBL][0-9]{1,3}$", options: .regularExpression) != nil {
                    score += 18
                }
            }
            
            return (text, score)
        }
        .sorted { $0.score > $1.score }
        
        return deduplicatedText(ranked.map(\.text)).prefix(2).map { $0 }
    }
    
    // MARK: - Dominant color
    private func extractDominantColor(from image: UIImage) -> UIColor {
        guard let resized = resizeImage(image, to: CGSize(width: 50, height: 50)),
              let cgImage = resized.cgImage else { return .systemBlue }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        
        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .systemBlue }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        let pixelCount = CGFloat(width * height)
        
        for i in stride(from: 0, to: rawData.count, by: bytesPerPixel) {
            r += CGFloat(rawData[i]) / 255.0
            g += CGFloat(rawData[i+1]) / 255.0
            b += CGFloat(rawData[i+2]) / 255.0
        }
        
        return UIColor(red: r/pixelCount, green: g/pixelCount, blue: b/pixelCount, alpha: 1)
    }
    
    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized
    }
}
