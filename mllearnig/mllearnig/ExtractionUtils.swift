import Foundation

struct ExtractedFields: Codable, Equatable {
    var dateString: String?
    var totalAmount: String?
}

struct ExtractionUtils {
    // Extract common fields from OCR text
    func extract(from text: String) -> ExtractedFields {
        var fields = ExtractedFields()

        // Date (simple patterns: 2025-11-06, 06/11/2025, Nov 6 2025)
        if let date = firstMatch(in: text, patterns: [
            #"(?<!\d)(20\d{2})[-/\.](0?[1-9]|1[0-2])[-/\.](0?[1-9]|[12]\d|3[01])(?!\d)"#, // YYYY-MM-DD
            #"(0?[1-9]|[12]\d|3[01])[-/\.](0?[1-9]|1[0-2])[-/\.](20\d{2})"#,               // DD-MM-YYYY
            #"(0?[1-9]|1[0-2])[-/\.](0?[1-9]|[12]\d|3[01])[-/\.](20\d{2})"#,               // MM-DD-YYYY
            #"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\s+\d{1,2},?\s+20\d{2}"#
        ]) {
            fields.dateString = date
        }

        // Total amount: look for lines containing total/grand/amount and a currency
        if let total = firstMatch(in: text, patterns: [
            #"(?i)\b(total|amount|grand total|balance due)\b[^\d]*([€$£]\s?\d{1,3}(?:[,\s]\d{3})*(?:\.\d{2})?)"#,
            #"[€$£]\s?\d{1,3}(?:[,\s]\d{3})*(?:\.\d{2})?"#
        ], group: 2) ?? firstMatch(in: text, patterns: [
            #"[€$£]\s?\d{1,3}(?:[,\s]\d{3})*(?:\.\d{2})?"#
        ]) {
            fields.totalAmount = total
        }

        return fields
    }

    func summarize(text: String, fields: ExtractedFields) -> String {
        let head = text.split(separator: "\n").prefix(5).joined(separator: " • ")
        var parts: [String] = []
        if let d = fields.dateString { parts.append("Date: \(d)") }
        if let t = fields.totalAmount { parts.append("Total: \(t)") }
        let fieldsSummary = parts.isEmpty ? "" : parts.joined(separator: " | ")
        if head.isEmpty && fieldsSummary.isEmpty { return "" }
        if head.isEmpty { return fieldsSummary }
        if fieldsSummary.isEmpty { return String(head) }
        return "\(fieldsSummary)\n\(head)"
    }

    private func firstMatch(in text: String, patterns: [String], group: Int = 0) -> String? {
        for pattern in patterns {
            if let m = firstMatch(in: text, pattern: pattern, group: group) {
                return m
            }
        }
        return nil
    }

    private func firstMatch(in text: String, pattern: String, group: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range) {
            let g = group < match.numberOfRanges ? group : 0
            if let r = Range(match.range(at: g), in: text) {
                return String(text[r])
            }
        }
        return nil
    }
}
