import AppKit

/// Vertical stitching with explicit rejection of uncertain or unchanged frames.
enum ImageStitcher {
    static func suggestedOverlap(previous: CGImage, next: CGImage) -> Int? {
        guard previous.width == next.width, previous.height == next.height,
              previous.height >= 64,
              let a = samples(previous), let b = samples(next) else { return nil }
        guard a != b else { return nil }
        let height = previous.height, width = 48
        var best = Double.greatestFiniteMagnitude
        var overlap: Int?
        // Comparing spread-out rows ignores isolated cursors and avoids assuming
        // that scrolling always advances by the same number of pixels.
        for candidate in 24..<(height - 8) {
            var error = 0.0, sum = 0.0, sumSquared = 0.0
            var count = 0
            for row in 0..<24 {
                let y = row * (candidate - 1) / 23
                for x in stride(from: 2, to: width - 2, by: 2) {
                    let v = Double(a[(height - candidate + y) * width + x])
                    let w = Double(b[y * width + x])
                    error += abs(v - w)
                    sum += v; sumSquared += v * v; count += 1
                }
            }
            let variance = sumSquared / Double(count) - pow(sum / Double(count), 2)
            guard variance > 100 else { continue }
            let score = error / Double(count)
            if score < best { best = score; overlap = candidate }
        }
        guard best < 8 else { return nil }
        return overlap
    }

    static func stitch(_ previous: CGImage, _ next: CGImage, overlap: Int) -> NSImage? {
        guard previous.width == next.width, overlap >= 0, overlap < next.height else { return nil }
        let height = previous.height + next.height - overlap
        return CaptureRenderer.bitmap(size: CGSize(width: previous.width, height: height)) {
            NSImage(cgImage: previous, size: .zero).draw(in: CGRect(x: 0, y: 0, width: previous.width, height: previous.height))
            let source = CGRect(x: 0, y: overlap, width: next.width, height: next.height - overlap)
            if let bottom = next.cropping(to: source) {
                NSImage(cgImage: bottom, size: .zero).draw(in: CGRect(x: 0, y: previous.height, width: bottom.width, height: bottom.height))
            }
        }
    }

    private static func samples(_ image: CGImage) -> [UInt8]? {
        let width = 48, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return success ? bytes : nil
    }
}
