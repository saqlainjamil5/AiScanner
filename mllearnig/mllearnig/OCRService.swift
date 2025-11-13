import Foundation
import Vision
import UIKit

actor OCRService {
    func recognizeText(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    print("OCR error: \(error)")
                    continuation.resume(returning: "")
                    return
                }
                var lines: [String] = []
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                for obs in observations {
                    if let top = obs.topCandidates(1).first {
                        lines.append(top.string)
                    }
                }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLanguages = ["en_US", "en_GB"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("VNImageRequestHandler error: \(error)")
                continuation.resume(returning: "")
            }
        }
    }
}
