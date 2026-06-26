import SwiftUI

struct AnnotationsOverlay: View {
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
            if ann.kind == .filledRectangle {
                shapePath(for: ann, displayRect: displayRect)
                    .fill(ann.color.color)
            } else {
                shapePath(for: ann, displayRect: displayRect)
                    .stroke(ann.color.color,
                            style: StrokeStyle(lineWidth: ann.stroke * scale,
                                               lineCap: .round, lineJoin: .round))
            }
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
        case .rectangle, .filledRectangle, .select, .hand, .text:
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
        } else if vm.tool == .filledRectangle {
            annotationShape(kind: vm.tool, rect: rect)
                .fill(vm.color.color)
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
