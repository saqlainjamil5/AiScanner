// MARK: - Advanced Feature 1: Document Edge Detection & Auto-Crop
import CoreImage
import CoreImage.CIFilterBuiltins

actor DocumentEdgeDetector {
    func detectAndCrop(image: UIImage) async -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        
        let detector = CIDetector(ofType: CIDetectorTypeRectangle,
                                  context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        
        guard let features = detector?.features(in: ciImage) as? [CIRectangleFeature],
              let rect = features.first else {
            return image // Return original if no rectangle found
        }
        
        // Perspective correction
        let perspectiveCorrection = CIFilter.perspectiveCorrection()
        perspectiveCorrection.inputImage = ciImage
        perspectiveCorrection.topLeft = rect.topLeft
        perspectiveCorrection.topRight = rect.topRight
        perspectiveCorrection.bottomLeft = rect.bottomLeft
        perspectiveCorrection.bottomRight = rect.bottomRight
        
        guard let outputImage = perspectiveCorrection.outputImage else { return image }
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return image
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    func enhanceDocument(image: UIImage) async -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        
        // Color controls for better contrast
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = ciImage
        colorControls.contrast = 1.2
        colorControls.brightness = 0.05
        colorControls.saturation = 0.0 // Black & white
        
        // Sharpen
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = colorControls.outputImage
        sharpen.sharpness = 0.8
        
        guard let output = sharpen.outputImage else { return image }
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else {
            return image
        }
        
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Advanced Feature 2: Multi-Page PDF Export
import PDFKit

actor PDFGenerator {
    func createPDF(from scans: [ScannedDocument]) async -> Data? {
        let pdfMetadata: [String: Any] = [
            kCGPDFContextTitle as String: "Smart Scanner Document",
            kCGPDFContextCreator as String: "Smart Scanner App"
        ]
        
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetadata as [String: Any]
        
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 size
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let data = renderer.pdfData { context in
            for scan in scans {
                context.beginPage()
                
                // Draw image if available
                if let image = scan.image {
                    let imageRect = aspectFitRect(for: image.size, in: pageRect.insetBy(dx: 40, dy: 40))
                    image.draw(in: imageRect)
                }
                
                // Draw text below image
                let textRect = CGRect(x: 40, y: pageRect.height - 200, width: pageRect.width - 80, height: 150)
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .left
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10),
                    .paragraphStyle: paragraphStyle
                ]
                
                let text = String(scan.recognizedText.prefix(300))
                text.draw(in: textRect, withAttributes: attributes)
            }
        }
        
        return data
    }
    
    private func aspectFitRect(for imageSize: CGSize, in rect: CGRect) -> CGRect {
        let aspectRatio = imageSize.width / imageSize.height
        let rectRatio = rect.width / rect.height
        
        var newSize: CGSize
        if aspectRatio > rectRatio {
            newSize = CGSize(width: rect.width, height: rect.width / aspectRatio)
        } else {
            newSize = CGSize(width: rect.height * aspectRatio, height: rect.height)
        }
        
        let x = rect.origin.x + (rect.width - newSize.width) / 2
        let y = rect.origin.y + (rect.height - newSize.height) / 2
        
        return CGRect(origin: CGPoint(x: x, y: y), size: newSize)
    }
}

// MARK: - Advanced Feature 3: AI-Powered Smart Search & Tags
import NaturalLanguage

actor SmartSearchEngine {
    func generateTags(for text: String) async -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = text
        
        var tags = Set<String>()
        
        // Extract named entities
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                           unit: .word,
                           scheme: .nameType,
                           options: [.omitWhitespace]) { tag, tokenRange in
            if let tag = tag {
                let entity = String(text[tokenRange])
                if entity.count > 2 {
                    tags.insert(entity.lowercased())
                }
            }
            return true
        }
        
        // Detect document type
        if text.localizedCaseInsensitiveContains("invoice") ||
           text.localizedCaseInsensitiveContains("bill") {
            tags.insert("invoice")
        }
        if text.localizedCaseInsensitiveContains("receipt") {
            tags.insert("receipt")
        }
        if text.localizedCaseInsensitiveContains("contract") ||
           text.localizedCaseInsensitiveContains("agreement") {
            tags.insert("contract")
        }
        if text.localizedCaseInsensitiveContains("id") ||
           text.localizedCaseInsensitiveContains("passport") ||
           text.localizedCaseInsensitiveContains("license") {
            tags.insert("identification")
        }
        
        return Array(tags.prefix(5))
    }
    
    func search(query: String, in scans: [ScannedDocument]) async -> [ScannedDocument] {
        let lowercaseQuery = query.lowercased()
        
        return scans.filter { scan in
            scan.recognizedText.lowercased().contains(lowercaseQuery) ||
            scan.summary.lowercased().contains(lowercaseQuery) ||
            (scan.extracted.dateString?.lowercased().contains(lowercaseQuery) ?? false) ||
            (scan.extracted.totalAmount?.lowercased().contains(lowercaseQuery) ?? false)
        }
    }
}

// MARK: - Advanced Feature 4: iCloud Sync & Backup
import CloudKit

actor CloudSyncManager {
    // Make container/database optional and lazily created to avoid touching CloudKit without entitlements
    private var container: CKContainer?
    private var database: CKDatabase?
    
    init() {}
    
    private func ensureContainer() throws {
        // If already set up, return
        if container != nil, database != nil { return }
        
        // Try to access the default container. If entitlements are missing, this may trap.
        // To avoid crashing, guard with a runtime check by using NSClassFromString and only proceed if CloudKit is usable.
        // Since we already import CloudKit, the symbol exists, but entitlement may still cause issues.
        // The safest is to attempt accountStatus via a background container created on demand and catch errors.
//        let c = CKContainer.default()
        // We can’t await here (actor sync method), so just set and rely on callers to handle errors thrown later.
//        self.container = c
//        self.database = c.privateCloudDatabase
    }
    
    func uploadScan(_ scan: ScannedDocument) async throws {
        do {
            try ensureContainer()
        } catch {
            throw error
        }
        guard let database else {
            throw NSError(domain: "CloudSync", code: -10, userInfo: [NSLocalizedDescriptionKey: "CloudKit unavailable"])
        }
        
        let record = CKRecord(recordType: "ScannedDocument")
        record["timestamp"] = scan.timestamp
        record["recognizedText"] = scan.recognizedText
        record["summary"] = scan.summary
        record["dateString"] = scan.extracted.dateString
        record["totalAmount"] = scan.extracted.totalAmount
        
        if let imageData = scan.image?.jpegData(compressionQuality: 0.8) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")
            try imageData.write(to: tempURL)
            record["image"] = CKAsset(fileURL: tempURL)
        }
        
        _ = try await database.save(record)
    }
    
    func fetchScans() async throws -> [ScannedDocument] {
        do {
            try ensureContainer()
        } catch {
            throw error
        }
        guard let database else {
            throw NSError(domain: "CloudSync", code: -10, userInfo: [NSLocalizedDescriptionKey: "CloudKit unavailable"])
        }
        
        let query = CKQuery(recordType: "ScannedDocument", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        let results = try await database.records(matching: query)
        var scans: [ScannedDocument] = []
        
        for (_, result) in results.matchResults {
            if case .success(let record) = result {
                if let scan = scanFromRecord(record) {
                    scans.append(scan)
                }
            }
        }
        
        return scans
    }
    
    private func scanFromRecord(_ record: CKRecord) -> ScannedDocument? {
        guard let timestamp = record["timestamp"] as? Date,
              let text = record["recognizedText"] as? String else {
            return nil
        }
        
        let extracted = ExtractedFields(
            dateString: record["dateString"] as? String,
            totalAmount: record["totalAmount"] as? String
        )
        
        var image: UIImage?
        if let asset = record["image"] as? CKAsset,
           let url = asset.fileURL,
           let data = try? Data(contentsOf: url) {
            image = UIImage(data: data)
        }
        
        return ScannedDocument(
            id: UUID(),
            timestamp: timestamp,
            image: image,
            recognizedText: text,
            extracted: extracted,
            summary: record["summary"] as? String ?? ""
        )
    }
}

// MARK: - Advanced Feature 5: OCR Language Detection & Translation
import NaturalLanguage

actor LanguageProcessor {
    func detectLanguage(in text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        
        guard let language = recognizer.dominantLanguage else {
            return "unknown"
        }
        
        return language.rawValue
    }
    
    func translate(text: String, to targetLanguage: String) async -> String {
        // Note: For production, integrate with translation API (Google Translate, DeepL, etc.)
        // This is a placeholder showing the structure
        return text // Placeholder
    }
    
    func getSupportedLanguages() -> [String] {
        return ["en", "es", "fr", "de", "it", "pt", "ru", "ja", "ko", "zh", "ar"]
    }
}

// MARK: - Advanced Feature 6: Batch Processing & Filters
enum ScanFilter: String, CaseIterable {
    case all = "All"
    case receipts = "Receipts"
    case invoices = "Invoices"
    case contracts = "Contracts"
    case identification = "ID Documents"
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    
    func filter(_ scans: [ScannedDocument]) -> [ScannedDocument] {
        switch self {
        case .all:
            return scans
        case .receipts:
            return scans.filter { $0.recognizedText.localizedCaseInsensitiveContains("receipt") }
        case .invoices:
            return scans.filter { $0.recognizedText.localizedCaseInsensitiveContains("invoice") }
        case .contracts:
            return scans.filter { $0.recognizedText.localizedCaseInsensitiveContains("contract") }
        case .identification:
            return scans.filter {
                $0.recognizedText.localizedCaseInsensitiveContains("id") ||
                $0.recognizedText.localizedCaseInsensitiveContains("passport") ||
                $0.recognizedText.localizedCaseInsensitiveContains("license")
            }
        case .today:
            let calendar = Calendar.current
            return scans.filter { calendar.isDateInToday($0.timestamp) }
        case .thisWeek:
            let calendar = Calendar.current
            return scans.filter { calendar.isDate($0.timestamp, equalTo: Date(), toGranularity: .weekOfYear) }
        case .thisMonth:
            let calendar = Calendar.current
            return scans.filter { calendar.isDate($0.timestamp, equalTo: Date(), toGranularity: .month) }
        }
    }
}

// MARK: - Advanced Feature 7: Smart Folders & Organization
struct SmartFolder: Identifiable, Codable {
    let id: UUID
    var name: String
    var icon: String
    var color: String
    var rules: [FilterRule]
    
    struct FilterRule: Codable {
        enum RuleType: String, Codable {
            case contains, startsWith, endsWith, hasAmount, hasDate
        }
        
        let type: RuleType
        let value: String
    }
    
    func matches(_ scan: ScannedDocument) -> Bool {
        for rule in rules {
            switch rule.type {
            case .contains:
                if !scan.recognizedText.localizedCaseInsensitiveContains(rule.value) {
                    return false
                }
            case .startsWith:
                if !scan.recognizedText.lowercased().hasPrefix(rule.value.lowercased()) {
                    return false
                }
            case .endsWith:
                if !scan.recognizedText.lowercased().hasSuffix(rule.value.lowercased()) {
                    return false
                }
            case .hasAmount:
                if scan.extracted.totalAmount == nil {
                    return false
                }
            case .hasDate:
                if scan.extracted.dateString == nil {
                    return false
                }
            }
        }
        return true
    }
}

// MARK: - Advanced Feature 8: Export to Multiple Formats
enum ExportFormat {
    case pdf, text, json, markdown, csv
}

actor ExportManager {
    func export(scans: [ScannedDocument], format: ExportFormat) async -> Data? {
        switch format {
        case .pdf:
            return await PDFGenerator().createPDF(from: scans)
        case .text:
            return exportAsText(scans: scans)
        case .json:
            return exportAsJSON(scans: scans)
        case .markdown:
            return exportAsMarkdown(scans: scans)
        case .csv:
            return exportAsCSV(scans: scans)
        }
    }
    
    private func exportAsText(scans: [ScannedDocument]) -> Data {
        var text = ""
        for (index, scan) in scans.enumerated() {
            text += "--- Scan \(index + 1) ---\n"
            text += "Date: \(scan.timestamp.formatted())\n"
            if let date = scan.extracted.dateString {
                text += "Document Date: \(date)\n"
            }
            if let amount = scan.extracted.totalAmount {
                text += "Amount: \(amount)\n"
            }
            text += "\nContent:\n\(scan.recognizedText)\n\n"
        }
        return text.data(using: .utf8) ?? Data()
    }
    
    private func exportAsJSON(scans: [ScannedDocument]) -> Data? {
        let exportData = scans.map { scan in
            [
                "id": scan.id.uuidString,
                "timestamp": scan.timestamp.ISO8601Format(),
                "text": scan.recognizedText,
                "date": scan.extracted.dateString ?? "",
                "amount": scan.extracted.totalAmount ?? "",
                "summary": scan.summary
            ]
        }
        return try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }
    
    private func exportAsMarkdown(scans: [ScannedDocument]) -> Data {
        var markdown = "# Scanned Documents\n\n"
        for (index, scan) in scans.enumerated() {
            markdown += "## Scan \(index + 1)\n\n"
            markdown += "**Date:** \(scan.timestamp.formatted())\n\n"
            if let date = scan.extracted.dateString {
                markdown += "**Document Date:** \(date)\n\n"
            }
            if let amount = scan.extracted.totalAmount {
                markdown += "**Amount:** \(amount)\n\n"
            }
            markdown += "### Content\n\n```\n\(scan.recognizedText)\n```\n\n---\n\n"
        }
        return markdown.data(using: .utf8) ?? Data()
    }
    
    private func exportAsCSV(scans: [ScannedDocument]) -> Data {
        var csv = "Scan Date,Document Date,Amount,Text\n"
        for scan in scans {
            let date = scan.timestamp.formatted()
            let docDate = scan.extracted.dateString ?? ""
            let amount = scan.extracted.totalAmount ?? ""
            let text = scan.recognizedText.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\"\(date)\",\"\(docDate)\",\"\(amount)\",\"\(text)\"\n"
        }
        return csv.data(using: .utf8) ?? Data()
    }
}

