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

    @Published var zoom: Double = 1.0

    @Published var draftRect: CGRect?
    @Published var dragStart: CGPoint?
    @Published var draftEnd: CGPoint?
    @Published var draftPoints: [CGPoint] = []

    @Published var editingTextID: UUID?

    private(set) var capture: Capture
    private var history = LayerHistory<AnnotationLayer>()
    private var resizeAnchor: CGRect?
    private var resizeAnchorArrowStart: CGPoint?
    private var resizeAnchorArrowEnd: CGPoint?
    private var resizeAnchorPoints: [CGPoint]?
    private var moveAnchor: CGRect?
    private var moveAnchorArrowStart: CGPoint?
    private var moveAnchorArrowEnd: CGPoint?
    private var moveAnchorPoints: [CGPoint]?

    init(capture: Capture) {
        self.capture = capture
        self.layer = LibraryStore.shared.loadAnnotations(for: capture)
    }

    func reload(capture: Capture) {
        self.capture = capture
        self.layer = LibraryStore.shared.loadAnnotations(for: capture)
        self.selectedID = nil
        self.zoom = 1.0
        self.editingTextID = nil
        self.draftRect = nil
        self.dragStart = nil
        self.draftEnd = nil
        self.draftPoints = []
        self.resizeAnchor = nil
        self.resizeAnchorArrowStart = nil
        self.resizeAnchorArrowEnd = nil
        self.resizeAnchorPoints = nil
        self.moveAnchor = nil
        self.moveAnchorArrowStart = nil
        self.moveAnchorArrowEnd = nil
        self.moveAnchorPoints = nil
        self.history.reset()
    }

    static let minZoom: Double = 0.25
    static let maxZoom: Double = 4.0

    func zoomIn()  { zoom = min(Self.maxZoom, zoom * 1.25) }
    func zoomOut() { zoom = max(Self.minZoom, zoom / 1.25) }
    func resetZoom() { zoom = 1.0 }

    private func snapshot() {
        history.snapshot(layer)
    }

    func undo() {
        guard let prev = history.undo(current: layer) else { return }
        layer = prev
        persist()
    }

    func redo() {
        guard let next = history.redo(current: layer) else { return }
        layer = next
        persist()
    }

    func startDraft(at point: CGPoint) {
        dragStart = point
        draftEnd = point
        draftRect = CGRect(origin: point, size: .zero)
        draftPoints = (tool == .freehand) ? [point] : []
    }

    func updateDraft(to point: CGPoint) {
        guard let s = dragStart else { return }
        draftEnd = point
        if tool == .freehand {
            if let last = draftPoints.last {
                if hypot(point.x - last.x, point.y - last.y) >= 1.0 {
                    draftPoints.append(point)
                }
            } else {
                draftPoints.append(point)
            }
            draftRect = boundingRect(of: draftPoints)
        } else {
            draftRect = CGRect(x: min(s.x, point.x),
                               y: min(s.y, point.y),
                               width: abs(point.x - s.x),
                               height: abs(point.y - s.y))
        }
    }

    func commitDraft() {
        defer { dragStart = nil; draftRect = nil; draftEnd = nil; draftPoints = [] }
        guard var r = draftRect, let s = dragStart, let e = draftEnd else { return }
        if tool == .text {
            if r.width < 20 { r.size.width = 160 }
            if r.height < 20 { r.size.height = 30 }
        } else if tool == .freehand {
            guard draftPoints.count > 1 else { return }
        } else {
            guard r.width > 3 || r.height > 3 else { return }
        }
        snapshot()
        let kind: AnnotationTool = (tool == .select) ? .rectangle : tool
        let ann = Annotation(kind: kind, rect: r, color: color, stroke: stroke,
                             text: tool == .text ? "" : nil,
                             arrowStart: tool == .arrow ? s : nil,
                             arrowEnd: tool == .arrow ? e : nil,
                             points: tool == .freehand ? draftPoints : nil)
        layer.annotations.append(ann)
        selectedID = ann.id
        if tool == .text {
            editingTextID = ann.id
        }
        persist()
    }

    private func boundingRect(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points.dropFirst() {
            if p.x < minX { minX = p.x }
            if p.y < minY { minY = p.y }
            if p.x > maxX { maxX = p.x }
            if p.y > maxY { maxY = p.y }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
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

    func resize(annotationID: UUID, corner: ResizeCorner, to imagePoint: CGPoint) {
        guard let idx = layer.annotations.firstIndex(where: { $0.id == annotationID }) else { return }
        if resizeAnchor == nil {
            snapshot()
            resizeAnchor = layer.annotations[idx].rect
            resizeAnchorArrowStart = layer.annotations[idx].arrowStart
            resizeAnchorArrowEnd = layer.annotations[idx].arrowEnd
            resizeAnchorPoints = layer.annotations[idx].points
        }
        guard let anchor = resizeAnchor else { return }
        let result = EditorTransforms.resize(
            anchor: anchor,
            arrowStart: resizeAnchorArrowStart,
            arrowEnd: resizeAnchorArrowEnd,
            points: resizeAnchorPoints,
            corner: corner,
            to: imagePoint)
        layer.annotations[idx].rect = result.rect
        layer.annotations[idx].arrowStart = result.arrowStart
        layer.annotations[idx].arrowEnd = result.arrowEnd
        layer.annotations[idx].points = result.points
    }

    func endResize() {
        guard resizeAnchor != nil else { return }
        resizeAnchor = nil
        resizeAnchorArrowStart = nil
        resizeAnchorArrowEnd = nil
        resizeAnchorPoints = nil
        persist()
    }

    func move(annotationID: UUID, by translation: CGSize) {
        guard let idx = layer.annotations.firstIndex(where: { $0.id == annotationID }) else { return }
        if moveAnchor == nil {
            snapshot()
            moveAnchor = layer.annotations[idx].rect
            moveAnchorArrowStart = layer.annotations[idx].arrowStart
            moveAnchorArrowEnd = layer.annotations[idx].arrowEnd
            moveAnchorPoints = layer.annotations[idx].points
            if selectedID != annotationID { selectedID = annotationID }
        }
        guard let anchor = moveAnchor else { return }
        let result = EditorTransforms.move(
            anchor: anchor,
            arrowStart: moveAnchorArrowStart,
            arrowEnd: moveAnchorArrowEnd,
            points: moveAnchorPoints,
            by: translation)
        layer.annotations[idx].rect = result.rect
        layer.annotations[idx].arrowStart = result.arrowStart
        layer.annotations[idx].arrowEnd = result.arrowEnd
        layer.annotations[idx].points = result.points
    }

    func endMove() {
        guard moveAnchor != nil else { return }
        moveAnchor = nil
        moveAnchorArrowStart = nil
        moveAnchorArrowEnd = nil
        moveAnchorPoints = nil
        persist()
    }

    func startEditingText(_ id: UUID) {
        editingTextID = id
        selectedID = id
    }

    func updateAnnotationText(_ id: UUID, text: String) {
        guard let idx = layer.annotations.firstIndex(where: { $0.id == id }) else { return }
        let newText = text.trimmingCharacters(in: .whitespaces)
        if newText.isEmpty {
            snapshot()
            layer.annotations.remove(at: idx)
            if selectedID == id { selectedID = nil }
            persist()
        } else if layer.annotations[idx].text != newText {
            snapshot()
            layer.annotations[idx].text = newText
            persist()
        }
    }

    func finishEditingText() {
        editingTextID = nil
    }

    private func persist() {
        LibraryStore.shared.saveAnnotations(layer, for: capture)
    }

    func render() -> NSImage? {
        Self.render(base: LibraryStore.shared.loadImage(for: capture),
                    annotations: layer.annotations)
    }

    static func renderFlattened(for capture: Capture) -> NSImage? {
        let base = LibraryStore.shared.loadImage(for: capture)
        let annotations = LibraryStore.shared.loadAnnotations(for: capture).annotations
        return render(base: base, annotations: annotations)
    }

    private static func render(base: NSImage?, annotations: [Annotation]) -> NSImage? {
        guard let base else { return nil }
        let size = base.size
        return NSImage(size: size, flipped: true) { _ in
            base.draw(in: NSRect(origin: .zero, size: size))
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            for a in annotations {
                drawAnnotation(a, in: ctx)
            }
            return true
        }
    }

    private static func drawAnnotation(_ a: Annotation, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setLineWidth(a.stroke)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let r = a.rect
        switch a.kind {
        case .rectangle, .select, .hand:
            ctx.stroke(r)
        case .circle:
            ctx.strokeEllipse(in: r)
        case .arrow:
            let p1 = a.arrowStart ?? CGPoint(x: r.minX, y: r.minY)
            let p2 = a.arrowEnd ?? CGPoint(x: r.maxX, y: r.maxY)
            drawArrow(from: p1, to: p2, lineWidth: a.stroke, in: ctx)
        case .text:
            let text = a.text ?? "Text"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: a.color.nsColor
            ]
            (text as NSString).draw(at: CGPoint(x: r.minX, y: r.minY),
                                     withAttributes: attrs)
        case .freehand:
            if let pts = a.points, pts.count > 1 {
                ctx.beginPath()
                ctx.move(to: pts[0])
                for p in pts.dropFirst() { ctx.addLine(to: p) }
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }

    private static func drawArrow(from a: CGPoint, to b: CGPoint, lineWidth: CGFloat, in ctx: CGContext) {
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
        guard let img = render(),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(tiff, forType: .tiff)
        if let png = rep.representation(using: .png, properties: [:]) {
            pb.setData(png, forType: .png)
        }
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
