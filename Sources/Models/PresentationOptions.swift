import Foundation

struct PresentationOptions: Codable, Equatable {
    var background: Background = .none
    var padding: Double = 48
    var cornerRadius: Double = 12
    var shadow: Bool = true
    var outputWidth: Int? = nil

    enum Background: String, Codable, CaseIterable {
        case none, white, charcoal, ocean, sunset, lavender
        var label: String { rawValue.capitalized }
    }

    func outputSize(content: CGSize) -> CGSize {
        let inset = background == .none ? 0 : max(0, padding)
        let natural = CGSize(width: content.width + 2 * inset, height: content.height + 2 * inset)
        guard let width = outputWidth, width > 0, natural.width > 0 else { return natural }
        let bounded = min(width, 16384)
        return CGSize(width: CGFloat(bounded), height: max(1, (natural.height * CGFloat(bounded) / natural.width).rounded()))
    }
}
