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
                guard let candidate = observation.topCandidates(1).first else { continue }
                let text = candidate.string
                let size = observation.boundingBox.height
                detectedText.append(text)
                textWithSizes.append((text: text, size: size))
            }
            textWithSizes.sort { $0.size > $1.size }
        }
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false
        textRequest.minimumTextHeight = 0.02
        
        group.enter()
        let classifyRequest = VNClassifyImageRequest { request, _ in
            defer { group.leave() }
            guard let observations = request.results as? [VNClassificationObservation] else { return }
            let top = observations.filter { $0.confidence > 0.3 }.prefix(3)
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
        
        let usefulText = detectedText.filter {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t.count >= 1 && t.count <= 20
        }.prefix(2)
        
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
        let emirates = ["Dubai", "Abu Dhabi", "Sharjah", "Ajman", "RAK", "Fujairah", "UAQ",
                        "دبي", "أبوظبي", "الشارقة", "عجمان", "رأس الخيمة", "الفجيرة"]
        let parkingPrefixes = ["P", "G", "B", "L"]
        let parkingKeywords = ["level", "floor", "zone", "basement", "ground", "parking", "park"]
        
        var emirateName: String? = nil
        var hasParkingKeyword = false
        var parkingPrefixText: String? = nil
        var letterCodes: [(code: String, size: CGFloat)] = []
        var numbers: [(number: String, size: CGFloat)] = []
        
        for item in textWithSizes {
            let trimmed = item.text.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            
            // Emirate detection
            for emirate in emirates {
                if trimmed.localizedCaseInsensitiveContains(emirate) {
                    emirateName = emirate
                }
            }
            
            // Parking keyword detection
            for keyword in parkingKeywords {
                if lower.contains(keyword) {
                    hasParkingKeyword = true
                }
            }
            
            // Combined parking format e.g. "P5AA", "P5 AA", "G3BB"
            if trimmed.range(of: "^[PGBL][0-9]{1,3}\\s?[A-Z]{1,2}$", options: .regularExpression) != nil {
                return "Parking · \(trimmed)"
            }
            
            // Parking prefix format e.g. "P5", "G3", "B2"
            for prefix in parkingPrefixes {
                if trimmed.range(of: "^\(prefix)[0-9]{1,3}$", options: .regularExpression) != nil {
                    parkingPrefixText = trimmed
                }
            }
            
            // Letter codes (1-3 uppercase letters only)
            if trimmed.range(of: "^[A-Z]{1,3}$", options: .regularExpression) != nil {
                letterCodes.append((code: trimmed, size: item.size))
            }
            
            // Numbers (1-6 digits)
            if trimmed.range(of: "^[0-9]{1,6}$", options: .regularExpression) != nil {
                numbers.append((number: trimmed, size: item.size))
            }
        }
        
        // Sort by size descending (largest = closest/most prominent)
        numbers.sort { $0.size > $1.size }
        letterCodes.sort { $0.size > $1.size }
        
        // RULE 1 — explicit parking keyword → parking
        if hasParkingKeyword {
            let keywordText = textWithSizes.first(where: { item in
                parkingKeywords.contains(where: { item.text.lowercased().contains($0) })
            })?.text.trimmingCharacters(in: .whitespaces) ?? ""
            return "Parking · \(keywordText)"
        }
        
        // RULE 2 — parking prefix present (P5, G3 etc)
        if let prefix = parkingPrefixText {
            // Check for adjacent letter code (P5 + AA = P5 AA)
            if let letters = letterCodes.first {
                return "Parking · \(prefix) \(letters.code)"
            }
            return "Parking · \(prefix)"
        }
        
        guard let bestNumber = numbers.first else { return nil }
        let digits = bestNumber.number.count
        
        // RULE 3 — emirate name present → definitely a plate
        if let emirate = emirateName {
            let bestLetters = letterCodes.min(by: {
                abs($0.size - bestNumber.size) < abs($1.size - bestNumber.size)
            })
            var parts = [emirate]
            if let letters = bestLetters { parts.append(letters.code) }
            parts.append(bestNumber.number)
            return parts.joined(separator: " · ")
        }
        
        // RULE 4 — 4-5 digits + letters → plate
        if digits >= 4, let bestLetters = letterCodes.first {
            return "\(bestLetters.code) · \(bestNumber.number)"
        }
        
        // RULE 5 — 1-3 digits + letters → parking
        if digits <= 3, let bestLetters = letterCodes.first {
            return "Parking · \(bestLetters.code) \(bestNumber.number)"
        }
        
        // RULE 6 — 4+ digits alone → likely plate
        if digits >= 4 {
            return "\(bestNumber.number)"
        }
        
        // RULE 7 — 1-3 digits alone → parking
        if digits <= 3 {
            return "Parking · \(bestNumber.number)"
        }
        
        return nil
    }
    
    // MARK: - Classification mapping
    private static func mapClassification(_ identifiers: [String]) -> String {
        let joined = identifiers.joined(separator: " ")
        if joined.contains("car") || joined.contains("vehicle") || joined.contains("automobile") { return "parking" }
        if joined.contains("baggage") || joined.contains("luggage") || joined.contains("suitcase") { return "luggage" }
        if joined.contains("food") || joined.contains("dish") || joined.contains("meal") { return "food" }
        if joined.contains("shop") || joined.contains("store") || joined.contains("retail") { return "shop" }
        if joined.contains("document") || joined.contains("text") || joined.contains("paper") { return "document" }
        if joined.contains("person") || joined.contains("face") { return "person" }
        if joined.contains("building") || joined.contains("architecture") { return "place" }
        return "memory"
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
