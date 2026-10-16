import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct GIFFrame {
    let url: URL
    /// Seconds since the first complete screen frame.
    let time: TimeInterval
}

enum GIFError: LocalizedError {
    case noFrames
    case invalidFrames
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .noFrames: return "No screen frames were recorded. Try recording again."
        case .invalidFrames: return "The recorded frames could not be read or have inconsistent dimensions."
        case .encodingFailed: return "The GIF could not be written. Check available disk space and try again."
        }
    }
}

enum GIFEncoder {
    static let maximumDuration: TimeInterval = 15
    static let framesPerSecond = 10
    static let maximumFrames = 150
    static let maximumDimension = 800

    static func outputSize(for size: CGSize) -> CGSize {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return .zero }
        let scale = min(1, CGFloat(maximumDimension) / max(size.width, size.height))
        return CGSize(width: max(1, floor(size.width * scale)), height: max(1, floor(size.height * scale)))
    }

    /// Preserve pauses when ScreenCaptureKit omits unchanged frames. Quantize
    /// cumulative timestamps (not individual delays) to avoid duration drift.
    static func delays(for frames: [GIFFrame], duration: TimeInterval) throws -> [TimeInterval] {
        guard !frames.isEmpty else { throw GIFError.noFrames }
        guard frames.count <= maximumFrames, duration.isFinite, duration > 0,
              duration <= maximumDuration + 0.01, frames[0].time == 0 else { throw GIFError.invalidFrames }
        var result: [TimeInterval] = []
        for index in frames.indices {
            let start = frames[index].time
            let end = index + 1 < frames.count ? frames[index + 1].time : duration
            guard start.isFinite, end.isFinite, start >= 0, end > start,
                  end <= maximumDuration + 0.01 else { throw GIFError.invalidFrames }
            let ticks = (end * 100).rounded() - (start * 100).rounded()
            guard ticks >= 1 else { throw GIFError.invalidFrames }
            result.append(ticks / 100)
        }
        return result
    }

    /// Loads one PNG at a time. No array of uncompressed screenshots is retained.
    static func encode(frames: [GIFFrame], duration: TimeInterval, to output: URL) throws {
        let timing = try delays(for: frames, duration: duration)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString,
                                                                frames.count, nil) else { throw GIFError.encodingFailed }
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: output) } }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        var expectedSize: CGSize?
        for (index, frame) in frames.enumerated() {
            try autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(frame.url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                      image.width <= maximumDimension, image.height <= maximumDimension else { throw GIFError.invalidFrames }
                let size = CGSize(width: image.width, height: image.height)
                guard expectedSize == nil || expectedSize == size else { throw GIFError.invalidFrames }
                expectedSize = size
                CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: timing[index],
                    kCGImagePropertyGIFUnclampedDelayTime: timing[index]
                ]] as CFDictionary)
            }
        }
        guard CGImageDestinationFinalize(destination) else { throw GIFError.encodingFailed }
        succeeded = true
    }
}
