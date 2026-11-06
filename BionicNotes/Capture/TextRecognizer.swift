import UIKit
import Vision

/// Texterkennung (OCR) für Folien – on-device mit Vision.
enum TextRecognizer {
    static func recognizeText(in image: UIImage, languages: [String]) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages.map { Locale.Language(identifier: $0) }
        do {
            let observations = try await request.perform(on: cgImage, orientation: image.cgOrientation)
            return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        } catch {
            return ""
        }
    }
}

private extension UIImage {
    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
