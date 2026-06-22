import SwiftUI
import AppKit

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
