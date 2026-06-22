import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ResizeCorner {
    case topLeft, topRight, bottomLeft, bottomRight
}

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
    private var undoStack: [AnnotationLayer] = []
    private var redoStack: [AnnotationLayer] = []
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
        self.undoStack.removeAll()
        self.redoStack.removeAll()
    }

    static let minZoom: Double = 0.25
    static let maxZoom: Double = 4.0

    func zoomIn()  { zoom = min(Self.maxZoom, zoom * 1.25) }
    func zoomOut() { zoom = max(Self.minZoom, zoom / 1.25) }
    func resetZoom() { zoom = 1.0 }

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

        var newRect: CGRect
        switch corner {
        case .topLeft:
            newRect = CGRect(x: imagePoint.x, y: imagePoint.y,
                             width: anchor.maxX - imagePoint.x,
                             height: anchor.maxY - imagePoint.y)
        case .topRight:
            newRect = CGRect(x: anchor.minX, y: imagePoint.y,
                             width: imagePoint.x - anchor.minX,
                             height: anchor.maxY - imagePoint.y)
        case .bottomLeft:
            newRect = CGRect(x: imagePoint.x, y: anchor.minY,
                             width: anchor.maxX - imagePoint.x,
                             height: imagePoint.y - anchor.minY)
        case .bottomRight:
            newRect = CGRect(x: anchor.minX, y: anchor.minY,
                             width: imagePoint.x - anchor.minX,
                             height: imagePoint.y - anchor.minY)
        }
        if newRect.width < 0 {
            newRect.origin.x += newRect.width
            newRect.size.width = -newRect.width
        }
        if newRect.height < 0 {
            newRect.origin.y += newRect.height
            newRect.size.height = -newRect.height
        }
        layer.annotations[idx].rect = newRect

        if anchor.width > 0, anchor.height > 0 {
            let sx = newRect.width / anchor.width
            let sy = newRect.height / anchor.height
            if let aS = resizeAnchorArrowStart {
                layer.annotations[idx].arrowStart = CGPoint(
                    x: newRect.minX + (aS.x - anchor.minX) * sx,
                    y: newRect.minY + (aS.y - anchor.minY) * sy)
            }
            if let aE = resizeAnchorArrowEnd {
                layer.annotations[idx].arrowEnd = CGPoint(
                    x: newRect.minX + (aE.x - anchor.minX) * sx,
                    y: newRect.minY + (aE.y - anchor.minY) * sy)
            }
            if let pts = resizeAnchorPoints {
                layer.annotations[idx].points = pts.map { p in
                    CGPoint(x: newRect.minX + (p.x - anchor.minX) * sx,
                            y: newRect.minY + (p.y - anchor.minY) * sy)
                }
            }
        }
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
        layer.annotations[idx].rect = CGRect(
            x: anchor.minX + translation.width,
            y: anchor.minY + translation.height,
            width: anchor.width,
            height: anchor.height
        )
        if let aS = moveAnchorArrowStart {
            layer.annotations[idx].arrowStart = CGPoint(
                x: aS.x + translation.width, y: aS.y + translation.height)
        }
        if let aE = moveAnchorArrowEnd {
            layer.annotations[idx].arrowEnd = CGPoint(
                x: aE.x + translation.width, y: aE.y + translation.height)
        }
        if let pts = moveAnchorPoints {
            layer.annotations[idx].points = pts.map {
                CGPoint(x: $0.x + translation.width, y: $0.y + translation.height)
            }
        }
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

struct EditorView: View {
    @ObservedObject var vm: EditorViewModel
    @State private var scrollController = CanvasScrollController()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.4)
            canvas
            Divider().opacity(0.4)
            statusBar
        }
        .background(Color(nsColor: NSColor.windowBackgroundColor))
        .background(deleteShortcutHost)
    }

    private var deleteShortcutHost: some View {
        Group {
            Button("") { vm.deleteSelected() }
                .keyboardShortcut(.delete, modifiers: [])
            Button("") { vm.deleteSelected() }
                .keyboardShortcut(.deleteForward, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .disabled(vm.selectedID == nil || vm.editingTextID != nil)
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
                .keyboardShortcut("z", modifiers: .command)
            Button { vm.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .help("Redo (⇧⌘Z)")
                .buttonStyle(.bordered)
                .keyboardShortcut("z", modifiers: [.command, .shift])
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
        HStack(spacing: 0) {
            imageCanvas
            Divider().opacity(0.4)
            zoomBar
        }
    }

    private var imageCanvas: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: NSColor.underPageBackgroundColor)
                if let img = LibraryStore.shared.loadImage(for: vm.capture) {
                    let base = fitSize(image: img.size, into: proxy.size)
                    let displaySize = CGSize(
                        width: base.size.width * vm.zoom,
                        height: base.size.height * vm.zoom)
                    let docSize = CGSize(
                        width: max(displaySize.width, proxy.size.width),
                        height: max(displaySize.height, proxy.size.height))
                    ScrollableCanvas(contentSize: docSize, controller: scrollController) {
                        ZStack(alignment: .topLeading) {
                            Image(nsImage: img)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: displaySize.width, height: displaySize.height)
                                .shadow(color: .black.opacity(0.35), radius: 18, y: 6)

                            AnnotationsOverlay(vm: vm, imageSize: img.size, displaySize: displaySize)
                                .frame(width: displaySize.width, height: displaySize.height)
                                .contentShape(Rectangle())
                                .gesture(canvasGesture(imageSize: img.size, displaySize: displaySize))
                        }
                        .frame(width: displaySize.width, height: displaySize.height)
                        .position(x: docSize.width / 2, y: docSize.height / 2)
                    }
                } else {
                    Text("Could not load image")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .focusable()
            .onKeyPress(.delete) {
                vm.deleteSelected()
                return .handled
            }
        }
    }

    private var zoomBar: some View {
        VStack(spacing: 10) {
            Button { vm.zoomIn() } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Zoom in")
            .keyboardShortcut("=", modifiers: .command)

            Slider(value: $vm.zoom,
                   in: EditorViewModel.minZoom...EditorViewModel.maxZoom)
                .rotationEffect(.degrees(-90))
                .frame(width: 160)
                .frame(width: 28, height: 160)

            Button { vm.zoomOut() } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Zoom out")
            .keyboardShortcut("-", modifiers: .command)

            Button {
                vm.resetZoom()
            } label: {
                Text("\(Int(vm.zoom * 100))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reset zoom (100%)")
            .keyboardShortcut("0", modifiers: .command)
        }
        .padding(.vertical, 12)
        .frame(width: 44)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
    }

    private func fitSize(image: CGSize, into container: CGSize) -> (size: CGSize, scale: CGFloat) {
        let padding: CGFloat = 32
        let avail = CGSize(width: max(100, container.width - padding * 2),
                           height: max(100, container.height - padding * 2))
        let scale = min(avail.width / image.width, avail.height / image.height, 1.0)
        return (CGSize(width: image.width * scale, height: image.height * scale), scale)
    }

    private func canvasGesture(imageSize: CGSize, displaySize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if vm.tool == .hand {
                    scrollController.beginPanIfNeeded()
                    scrollController.applyPan(translation: value.translation)
                    return
                }
                guard vm.tool != .select else { return }
                let scaled = scaleToImage(point: value.location,
                                          imageSize: imageSize, displaySize: displaySize)
                if vm.dragStart == nil {
                    vm.startDraft(at: scaleToImage(point: value.startLocation,
                                                    imageSize: imageSize, displaySize: displaySize))
                }
                vm.updateDraft(to: scaled)
            }
            .onEnded { _ in
                if vm.tool == .hand {
                    scrollController.endPan()
                    return
                }
                guard vm.tool != .select else { return }
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
                annotationView(for: ann)
            }

            if let draft = vm.draftRect {
                draftShape(rect: scaledToDisplay(rect: draft))
            }
        }
        .coordinateSpace(name: "canvas")
    }

    @ViewBuilder
    private func annotationView(for ann: Annotation) -> some View {
        let displayRect = scaledToDisplay(rect: ann.rect)
        let body = ZStack(alignment: .topLeading) {
            shapePath(for: ann, displayRect: displayRect)
                .stroke(ann.color.color,
                        style: StrokeStyle(lineWidth: ann.stroke * scale,
                                           lineCap: .round, lineJoin: .round))
            if ann.kind == .text {
                if vm.editingTextID == ann.id {
                    TextAnnotationEditor(vm: vm, ann: ann,
                                         displayRect: displayRect, scale: scale)
                } else {
                    Text(ann.text?.isEmpty == false ? ann.text! : "Text")
                        .font(.system(size: 18 * scale, weight: .semibold))
                        .foregroundStyle(ann.color.color)
                        .frame(width: displayRect.width, height: displayRect.height,
                               alignment: .topLeading)
                        .position(x: displayRect.midX, y: displayRect.midY)
                        .onTapGesture(count: 2) { vm.startEditingText(ann.id) }
                }
            }
            if vm.selectedID == ann.id && vm.editingTextID != ann.id {
                selectionHandles(for: ann, displayRect: displayRect)
            }
        }
        .contentShape(Rectangle().path(in: displayRect.insetBy(dx: -8, dy: -8)))
        .onTapGesture { vm.select(ann.id) }

        if vm.tool == .select && vm.editingTextID != ann.id {
            body.gesture(moveGesture(for: ann))
        } else {
            body
        }
    }

    private func moveGesture(for ann: Annotation) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("canvas"))
            .onChanged { value in
                let dx = value.translation.width * (imageSize.width / displaySize.width)
                let dy = value.translation.height * (imageSize.height / displaySize.height)
                vm.move(annotationID: ann.id, by: CGSize(width: dx, height: dy))
            }
            .onEnded { _ in
                vm.endMove()
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
        case .rectangle, .select, .hand, .text:
            path.addRect(rect)
        case .circle:
            path.addEllipse(in: rect)
        case .arrow:
            path = arrowPath(from: CGPoint(x: rect.minX, y: rect.minY),
                             to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .freehand:
            break
        }
        return path
    }

    private func shapePath(for ann: Annotation, displayRect: CGRect) -> Path {
        switch ann.kind {
        case .arrow:
            let s = ann.arrowStart.map(scaleImageToDisplay)
                    ?? CGPoint(x: displayRect.minX, y: displayRect.minY)
            let e = ann.arrowEnd.map(scaleImageToDisplay)
                    ?? CGPoint(x: displayRect.maxX, y: displayRect.maxY)
            return arrowPath(from: s, to: e)
        case .freehand:
            guard let pts = ann.points, pts.count > 1 else { return Path() }
            var path = Path()
            let display = pts.map(scaleImageToDisplay)
            path.move(to: display[0])
            for p in display.dropFirst() { path.addLine(to: p) }
            return path
        default:
            return annotationShape(kind: ann.kind, rect: displayRect)
        }
    }

    private func scaleImageToDisplay(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * scale, y: p.y * scale)
    }

    private func arrowPath(from a: CGPoint, to b: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        let dx = b.x - a.x
        let dy = b.y - a.y
        guard dx != 0 || dy != 0 else { return path }
        let angle = atan2(dy, dx)
        let headLen: CGFloat = 14
        let left = CGPoint(x: b.x - headLen * cos(angle - .pi/6),
                           y: b.y - headLen * sin(angle - .pi/6))
        let right = CGPoint(x: b.x - headLen * cos(angle + .pi/6),
                            y: b.y - headLen * sin(angle + .pi/6))
        path.move(to: b); path.addLine(to: left)
        path.move(to: b); path.addLine(to: right)
        return path
    }

    @ViewBuilder
    private func draftShape(rect: CGRect) -> some View {
        let stroke = StrokeStyle(lineWidth: vm.stroke * scale, dash: [4, 4], dashPhase: 0)
        if vm.tool == .freehand, vm.draftPoints.count > 1 {
            freehandPath(points: vm.draftPoints.map(scaleImageToDisplay))
                .stroke(vm.color.color,
                        style: StrokeStyle(lineWidth: vm.stroke * scale,
                                           lineCap: .round, lineJoin: .round))
        } else if vm.tool == .arrow, let s = vm.dragStart, let e = vm.draftEnd {
            arrowPath(from: scaleImageToDisplay(s), to: scaleImageToDisplay(e))
                .stroke(vm.color.color.opacity(0.85), style: stroke)
        } else {
            annotationShape(kind: vm.tool, rect: rect)
                .stroke(vm.color.color.opacity(0.85), style: stroke)
        }
    }

    private func freehandPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        return path
    }

    private func selectionHandles(for ann: Annotation, displayRect: CGRect) -> some View {
        let handles: [(CGPoint, ResizeCorner)] = [
            (CGPoint(x: displayRect.minX, y: displayRect.minY), .topLeft),
            (CGPoint(x: displayRect.maxX, y: displayRect.minY), .topRight),
            (CGPoint(x: displayRect.minX, y: displayRect.maxY), .bottomLeft),
            (CGPoint(x: displayRect.maxX, y: displayRect.maxY), .bottomRight)
        ]
        return ZStack {
            ForEach(handles.indices, id: \.self) { i in
                let (pos, corner) = handles[i]
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                    .contentShape(Circle().scale(1.8))
                    .position(pos)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .named("canvas"))
                            .onChanged { value in
                                let p = scaleToImagePoint(value.location)
                                vm.resize(annotationID: ann.id, corner: corner, to: p)
                            }
                            .onEnded { _ in
                                vm.endResize()
                            }
                    )
            }
        }
    }

    private func scaleToImagePoint(_ p: CGPoint) -> CGPoint {
        let sx = imageSize.width / displaySize.width
        let sy = imageSize.height / displaySize.height
        return CGPoint(x: p.x * sx, y: p.y * sy)
    }
}

private struct TextAnnotationEditor: View {
    @ObservedObject var vm: EditorViewModel
    let ann: Annotation
    let displayRect: CGRect
    let scale: CGFloat

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Type…", text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 18 * scale, weight: .semibold))
            .foregroundStyle(ann.color.color)
            .focused($focused)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(ann.color.color.opacity(0.55), lineWidth: 1)
                    )
            )
            .frame(width: max(120, displayRect.width),
                   height: max(28, displayRect.height))
            .position(x: displayRect.midX, y: displayRect.midY)
            .onAppear {
                draft = ann.text ?? ""
                DispatchQueue.main.async { focused = true }
            }
            .onSubmit { commit() }
            .onExitCommand { commit() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
    }

    private func commit() {
        vm.updateAnnotationText(ann.id, text: draft)
        vm.finishEditingText()
    }
}

@MainActor
final class CanvasScrollController {
    weak var scrollView: NSScrollView?
    private var panStartOrigin: CGPoint?

    func beginPanIfNeeded() {
        guard panStartOrigin == nil else { return }
        panStartOrigin = scrollView?.contentView.bounds.origin
    }

    func applyPan(translation: CGSize) {
        guard let scrollView, let start = panStartOrigin else { return }
        let docSize = scrollView.documentView?.frame.size ?? .zero
        let visible = scrollView.contentView.bounds.size
        let maxX = max(0, docSize.width - visible.width)
        let maxY = max(0, docSize.height - visible.height)
        let origin = CGPoint(
            x: min(maxX, max(0, start.x - translation.width)),
            y: min(maxY, max(0, start.y - translation.height)))
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func endPan() {
        panStartOrigin = nil
    }
}

struct ScrollableCanvas<Content: View>: NSViewRepresentable {
    let contentSize: CGSize
    let controller: CanvasScrollController
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let hosting = NSHostingView(rootView: content())
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        scroll.documentView = hosting
        context.coordinator.hosting = hosting

        controller.scrollView = scroll
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let hosting = context.coordinator.hosting as? NSHostingView<Content> else { return }
        hosting.rootView = content()
        let newFrame = NSRect(origin: .zero, size: contentSize)
        if hosting.frame != newFrame {
            hosting.frame = newFrame
        }
        if controller.scrollView !== scroll {
            controller.scrollView = scroll
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var hosting: NSView?
    }
}
