import AppKit
import CoreImage

/// A single pixel renderer serves the canvas, clipboard, export, OCR and drag-out.
/// Originals and editable layers remain local; shared images are always flattened.
enum CaptureRenderer {
    private static let ciContext = CIContext()

    static func bitmap(size: CGSize, draw: () -> Void) -> NSImage? {
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 0, h > 0, w <= 32768, h <= 32768, Double(w) * Double(h) <= 100_000_000,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.translateBy(x: 0, y: CGFloat(h))
        context.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: NSSize(width: w, height: h))
        result.addRepresentation(rep)
        return result
    }

    static func render(base: NSImage, layer: AnnotationLayer, presentation: Bool = true) -> NSImage? {
        guard let annotated = bitmap(size: base.size, draw: {
            base.draw(in: CGRect(origin: .zero, size: base.size))
            for annotation in layer.annotations where annotation.kind != .redact { draw(annotation, base: base) }
            for annotation in layer.annotations where annotation.kind == .redact { draw(annotation, base: base) }
        }) else { return nil }
        guard presentation else { return annotated }
        let bounds = CGRect(origin: .zero, size: base.size)
        let crop = (layer.cropRect ?? bounds).intersection(bounds).integral
        guard !crop.isNull, crop.width > 0, crop.height > 0 else { return nil }
        let options = layer.presentation ?? PresentationOptions()
        let pad = options.background == .none ? 0 : max(0, options.padding)
        let natural = CGSize(width: crop.width + 2 * pad, height: crop.height + 2 * pad)
        let output = options.outputSize(content: crop.size)
        return bitmap(size: output) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            ctx.scaleBy(x: output.width / natural.width, y: output.height / natural.height)
            let canvas = CGRect(origin: .zero, size: natural)
            drawBackground(options.background, in: canvas)
            let imageRect = CGRect(x: pad, y: pad, width: crop.width, height: crop.height)
            let radius = options.background == .none ? 0 : options.cornerRadius
            let imagePath = NSBezierPath(roundedRect: imageRect, xRadius: radius, yRadius: radius)
            ctx.saveGState()
            if options.background != .none && options.shadow {
                ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 20,
                              color: NSColor.black.withAlphaComponent(0.28).cgColor)
                ctx.setFillColor(NSColor.white.cgColor)
                imagePath.fill()
                ctx.setShadow(offset: .zero, blur: 0, color: nil)
            }
            imagePath.addClip()
            // Source image rectangles use bottom-left coordinates.
            annotated.draw(in: imageRect,
                           from: CGRect(x: crop.minX, y: base.size.height - crop.maxY,
                                        width: crop.width, height: crop.height),
                           operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            ctx.restoreGState()
        }
    }

    private static func drawBackground(_ background: PresentationOptions.Background, in rect: CGRect) {
        let colors: [NSColor]
        switch background {
        case .none: return
        case .white: colors = [.white, .white]
        case .charcoal: colors = [NSColor(white: 0.13, alpha: 1), NSColor(white: 0.22, alpha: 1)]
        case .ocean: colors = [NSColor(srgbRed: 0.07, green: 0.29, blue: 0.55, alpha: 1), .systemTeal]
        case .sunset: colors = [.systemOrange, .systemPink]
        case .lavender: colors = [NSColor(srgbRed: 0.4, green: 0.32, blue: 0.65, alpha: 1), .systemIndigo]
        }
        NSGradient(starting: colors[0], ending: colors[1])?.draw(in: rect, angle: 35)
    }

    private static func draw(_ a: Annotation, base: NSImage) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setFillColor(a.color.cgColor)
        ctx.setLineWidth(a.stroke)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let r = a.rect
        switch a.kind {
        case .select, .hand, .crop: break
        case .rectangle: ctx.stroke(r)
        case .filledRectangle: ctx.fill(r)
        case .highlight:
            ctx.setFillColor(a.color.nsColor.withAlphaComponent(0.3).cgColor)
            ctx.fill(r)
        case .redact:
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(r.integral)
        case .blur, .pixelate:
            drawFiltered(a, base: base)
        case .circle: ctx.strokeEllipse(in: r)
        case .counter:
            ctx.fillEllipse(in: r)
            let string = (a.text ?? "1") as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(10, min(r.width, r.height) * 0.55), weight: .bold),
                .foregroundColor: NSColor.white]
            let size = string.size(withAttributes: attrs)
            string.draw(at: CGPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
        case .text:
            NSBezierPath(rect: r).addClip()
            ((a.text ?? "") as NSString).draw(with: r, options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: a.color.nsColor])
        case .arrow:
            let start = a.arrowStart ?? CGPoint(x: r.minX, y: r.minY)
            let end = a.arrowEnd ?? CGPoint(x: r.maxX, y: r.maxY)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let length = max(10, a.stroke * 5)
            ctx.move(to: start); ctx.addLine(to: end)
            for delta in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                ctx.move(to: end)
                ctx.addLine(to: CGPoint(x: end.x - length * cos(angle + delta), y: end.y - length * sin(angle + delta)))
            }
            ctx.strokePath()
        case .freehand:
            guard let points = a.points, let first = points.first else { return }
            ctx.move(to: first)
            for p in points.dropFirst() { ctx.addLine(to: p) }
            ctx.strokePath()
        }
    }

    private static func drawFiltered(_ a: Annotation, base: NSImage) {
        let rect = a.rect.intersection(CGRect(origin: .zero, size: base.size)).integral
        guard !rect.isEmpty, !rect.isNull else { return }
        // Filter only the selected pixels, never reveal original pixels on failure.
        guard let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let region = cg.cropping(to: rect) else {
            NSColor.black.setFill(); rect.fill(); return
        }
        let input = CIImage(cgImage: region)
        let filtered: CIImage
        if a.kind == .blur {
            filtered = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(12, a.stroke * 4)])
        } else {
            filtered = input.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(12, a.stroke * 5)])
        }
        guard let result = ciContext.createCGImage(filtered, from: input.extent) else {
            NSColor.black.setFill(); rect.fill(); return
        }
        NSImage(cgImage: result, size: rect.size).draw(in: rect)
    }
}
