import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var layer: AnnotationLayer
    @Published var tool: AnnotationTool = .rectangle
    @Published var color: AnnotationColor = .red
    @Published var stroke: Double = 3.0
    @Published var selectedID: UUID?

    @Published var draftRect: CGRect?
    @Published var dragStart: CGPoint?

    private(set) var capture: Capture
    private var undoStack: [AnnotationLayer] = []
    private var redoStack: [AnnotationLayer] = []

    init(capture: Capture) {
        self.capture = capture
        self.layer = LibraryStore.shared.loadAnnotations(for: capture)
    }

    func reload(capture: Capture) {
        self.capture = capture
        self.layer = LibraryStore.shared.loadAnnotations(for: capture)
        self.selectedID = nil
        self.undoStack.removeAll()
        self.redoStack.removeAll()
    }

    private func snapshot() {
        undoStack.append(layer)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(layer)
        layer = prev
        persist()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(layer)
        layer = next
        persist()
    }

    func startDraft(at point: CGPoint) {
        dragStart = point
        draftRect = CGRect(origin: point, size: .zero)
    }

    func updateDraft(to point: CGPoint) {
        guard let s = dragStart else { return }
        draftRect = CGRect(x: min(s.x, point.x),
                           y: min(s.y, point.y),
                           width: abs(point.x - s.x),
                           height: abs(point.y - s.y))
    }

    func commitDraft() {
        defer { dragStart = nil; draftRect = nil }
        guard let r = draftRect, r.width > 3 || r.height > 3 else { return }
        snapshot()
        let kind: AnnotationTool = (tool == .select) ? .rectangle : tool
        let ann = Annotation(kind: kind, rect: r, color: color, stroke: stroke)
        layer.annotations.append(ann)
        selectedID = ann.id
        persist()
    }

    func deleteSelected() {
        guard let sid = selectedID else { return }
        snapshot()
        layer.annotations.removeAll { $0.id == sid }
        selectedID = nil
        persist()
    }

    func clearAll() {
        snapshot()
        layer.annotations.removeAll()
        selectedID = nil
        persist()
    }

    func select(_ id: UUID?) { selectedID = id }

    private func persist() {
        LibraryStore.shared.saveAnnotations(layer, for: capture)
    }

    func render() -> NSImage? {
        guard let base = LibraryStore.shared.loadImage(for: capture) else { return nil }
        let size = base.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                    pixelsWide: Int(size.width),
                                    pixelsHigh: Int(size.height),
                                    bitsPerSample: 8,
                                    samplesPerPixel: 4,
                                    hasAlpha: true,
                                    isPlanar: false,
                                    colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0,
                                    bitsPerPixel: 32)
        guard let rep else { return nil }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        base.draw(in: NSRect(origin: .zero, size: size))

        if let ctx = NSGraphicsContext.current?.cgContext {
            for a in layer.annotations {
                drawAnnotation(a, in: ctx, canvasSize: size)
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        let out = NSImage(size: size)
        out.addRepresentation(rep)
        return out
    }

    private func drawAnnotation(_ a: Annotation, in ctx: CGContext, canvasSize: CGSize) {
        ctx.saveGState()
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setLineWidth(a.stroke)
        ctx.setLineCap(.round)
        let r = a.rect
        switch a.kind {
        case .rectangle, .select:
            ctx.stroke(r)
        case .circle:
            ctx.strokeEllipse(in: r)
        case .arrow:
            drawArrow(from: CGPoint(x: r.minX, y: r.minY),
                      to: CGPoint(x: r.maxX, y: r.maxY),
                      lineWidth: a.stroke,
                      in: ctx)
        case .text:
            let text = a.text ?? "Text"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: a.color.nsColor
            ]
            (text as NSString).draw(at: CGPoint(x: r.minX, y: r.minY),
                                     withAttributes: attrs)
        case .highlight:
            ctx.setFillColor(a.color.cgColor.copy(alpha: 0.3) ?? a.color.cgColor)
            ctx.fill(r)
        }
        ctx.restoreGState()
    }

    private func drawArrow(from a: CGPoint, to b: CGPoint, lineWidth: CGFloat, in ctx: CGContext) {
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
        let angle = atan2(b.y - a.y, b.x - a.x)
        let headLen = max(10, lineWidth * 5)
        let left = CGPoint(x: b.x - headLen * cos(angle - .pi / 6),
                           y: b.y - headLen * sin(angle - .pi / 6))
        let right = CGPoint(x: b.x - headLen * cos(angle + .pi / 6),
                            y: b.y - headLen * sin(angle + .pi / 6))
        ctx.move(to: b); ctx.addLine(to: left)
        ctx.move(to: b); ctx.addLine(to: right)
        ctx.strokePath()
    }

    func copyToPasteboard() {
        guard let img = render() else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([img])
    }

    func saveAs() {
        guard let img = render() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "capture-\(Int(Date().timeIntervalSince1970)).png"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            if let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
            }
        }
    }
}

struct EditorView: View {
    @ObservedObject var vm: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.4)
            canvas
            Divider().opacity(0.4)
            statusBar
        }
        .background(Color(nsColor: NSColor.windowBackgroundColor))
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                Button {
                    vm.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 28, height: 28)
                        .background(vm.tool == tool
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(vm.tool == tool ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
                .help(tool.label)
            }

            Divider().frame(height: 20).padding(.horizontal, 6)

            ForEach(AnnotationColor.palette, id: \.self) { c in
                Button {
                    vm.color = c
                } label: {
                    Circle()
                        .fill(c.color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.accentColor, lineWidth: vm.color == c ? 2 : 0)
                        )
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 20).padding(.horizontal, 6)

            HStack(spacing: 8) {
                Image(systemName: "lineweight")
                Slider(value: $vm.stroke, in: 1...10)
                    .frame(width: 80)
                Text("\(Int(vm.stroke)) px")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 38, alignment: .trailing)
            }

            Spacer()

            Button { vm.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .help("Undo (⌘Z)")
                .buttonStyle(.bordered)
            Button { vm.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .help("Redo (⇧⌘Z)")
                .buttonStyle(.bordered)
            Button("Copy") { vm.copyToPasteboard() }
                .keyboardShortcut("c", modifiers: .command)
            Button("Save") { vm.saveAs() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var canvas: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: NSColor.underPageBackgroundColor)
                if let img = LibraryStore.shared.loadImage(for: vm.capture) {
                    let fitted = fitSize(image: img.size, into: proxy.size)
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: fitted.size.width, height: fitted.size.height)
                            .shadow(color: .black.opacity(0.35), radius: 18, y: 6)

                        AnnotationsOverlay(vm: vm, imageSize: img.size, displaySize: fitted.size)
                            .frame(width: fitted.size.width, height: fitted.size.height)
                            .contentShape(Rectangle())
                            .gesture(drawingGesture(imageSize: img.size, displaySize: fitted.size))
                    }
                    .frame(width: fitted.size.width, height: fitted.size.height)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                } else {
                    Text("Could not load image")
                        .foregroundStyle(.secondary)
                }
            }
            .focusable()
            .onKeyPress(.delete) {
                vm.deleteSelected()
                return .handled
            }
        }
    }

    private func fitSize(image: CGSize, into container: CGSize) -> (size: CGSize, scale: CGFloat) {
        let padding: CGFloat = 32
        let avail = CGSize(width: max(100, container.width - padding * 2),
                           height: max(100, container.height - padding * 2))
        let scale = min(avail.width / image.width, avail.height / image.height, 1.0)
        return (CGSize(width: image.width * scale, height: image.height * scale), scale)
    }

    private func drawingGesture(imageSize: CGSize, displaySize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let scaled = scaleToImage(point: value.location,
                                          imageSize: imageSize, displaySize: displaySize)
                if vm.dragStart == nil {
                    vm.startDraft(at: scaleToImage(point: value.startLocation,
                                                    imageSize: imageSize, displaySize: displaySize))
                }
                vm.updateDraft(to: scaled)
            }
            .onEnded { _ in
                vm.commitDraft()
            }
    }

    private func scaleToImage(point: CGPoint, imageSize: CGSize, displaySize: CGSize) -> CGPoint {
        let sx = imageSize.width / displaySize.width
        let sy = imageSize.height / displaySize.height
        return CGPoint(x: point.x * sx, y: point.y * sy)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Text("\(vm.tool.label) · \(Int(vm.stroke)) px")
                .foregroundStyle(.secondary)
            Text("•").foregroundStyle(.secondary)
            Text("\(vm.layer.annotations.count) annotation\(vm.layer.annotations.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            Spacer()
            Text(vm.capture.displayDims)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct AnnotationsOverlay: View {
    @ObservedObject var vm: EditorViewModel
    let imageSize: CGSize
    let displaySize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(vm.layer.annotations) { ann in
                let displayRect = scaledToDisplay(rect: ann.rect)
                ZStack(alignment: .topLeading) {
                    annotationShape(kind: ann.kind, rect: displayRect)
                        .stroke(ann.color.color,
                                style: StrokeStyle(lineWidth: ann.stroke * scale, lineCap: .round))
                    if ann.kind == .highlight {
                        annotationShape(kind: ann.kind, rect: displayRect)
                            .fill(ann.color.color.opacity(0.3))
                    }
                    if ann.kind == .text {
                        Text(ann.text ?? "Text")
                            .font(.system(size: 18 * scale, weight: .semibold))
                            .foregroundStyle(ann.color.color)
                            .position(x: displayRect.midX, y: displayRect.midY)
                    }
                    if vm.selectedID == ann.id {
                        selectionHandles(in: displayRect)
                    }
                }
                .contentShape(Rectangle().path(in: displayRect.insetBy(dx: -8, dy: -8)))
                .onTapGesture { vm.select(ann.id) }
            }

            if let draft = vm.draftRect {
                draftShape(rect: scaledToDisplay(rect: draft))
            }
        }
    }

    private var scale: CGFloat {
        displaySize.width / imageSize.width
    }

    private func scaledToDisplay(rect: CGRect) -> CGRect {
        let s = scale
        return CGRect(x: rect.origin.x * s, y: rect.origin.y * s,
                      width: rect.width * s, height: rect.height * s)
    }

    private func annotationShape(kind: AnnotationTool, rect: CGRect) -> Path {
        var path = Path()
        switch kind {
        case .rectangle, .select, .text:
            path.addRect(rect)
        case .circle:
            path.addEllipse(in: rect)
        case .arrow:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            let angle = atan2(rect.maxY - rect.minY, rect.maxX - rect.minX)
            let headLen: CGFloat = 14
            let left = CGPoint(x: rect.maxX - headLen * cos(angle - .pi/6),
                               y: rect.maxY - headLen * sin(angle - .pi/6))
            let right = CGPoint(x: rect.maxX - headLen * cos(angle + .pi/6),
                                y: rect.maxY - headLen * sin(angle + .pi/6))
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY)); path.addLine(to: left)
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY)); path.addLine(to: right)
        case .highlight:
            path.addRect(rect)
        }
        return path
    }

    @ViewBuilder
    private func draftShape(rect: CGRect) -> some View {
        let stroke = StrokeStyle(lineWidth: vm.stroke * scale, dash: [4, 4], dashPhase: 0)
        annotationShape(kind: vm.tool, rect: rect)
            .stroke(vm.color.color.opacity(0.85), style: stroke)
    }

    private func selectionHandles(in rect: CGRect) -> some View {
        let points: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        return ZStack {
            ForEach(0..<points.count, id: \.self) { i in
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                    .position(points[i])
            }
        }
    }
}
