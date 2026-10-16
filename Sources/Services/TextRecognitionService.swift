import Vision
import CoreGraphics

struct TextRecognitionService {
    static func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .accurate
            text.usesLanguageCorrection = true
            text.automaticallyDetectsLanguage = true
            let codes = VNDetectBarcodesRequest()
            codes.symbologies = [.qr]
            try VNImageRequestHandler(cgImage: image).perform([text, codes])
            let lines = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let payloads = (codes.results ?? []).compactMap(\.payloadStringValue)
            return (lines + payloads.map { "QR: \($0)" }).joined(separator: "\n")
        }.value
    }
}
