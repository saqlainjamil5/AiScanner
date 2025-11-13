import Foundation
import UIKit
import Combine

final class ScannedDocument: Identifiable, ObservableObject {
    let id: UUID
    let timestamp: Date
    var image: UIImage?
    @Published var thumbnail: UIImage?
    let recognizedText: String
    let extracted: ExtractedFields
    let summary: String

    init(id: UUID, timestamp: Date, image: UIImage?, recognizedText: String, extracted: ExtractedFields, summary: String) {
        self.id = id
        self.timestamp = timestamp
        self.image = image
        self.recognizedText = recognizedText
        self.extracted = extracted
        self.summary = summary
    }

    var title: String {
        if let firstLine = recognizedText.split(separator: "\n").first, !firstLine.isEmpty {
            return String(firstLine.prefix(40))
        }
        return "Scan \(timestamp.formatted(date: .abbreviated, time: .shortened))"
    }

    func generateThumbnailIfNeeded(maxSide: CGFloat) {
        guard thumbnail == nil, let image else { return }
        let scale = max(image.size.width, image.size.height) / maxSide
        let targetSize = CGSize(width: image.size.width / scale, height: image.size.height / scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let thumb = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        self.thumbnail = thumb
    }
}
