import AppKit
import SwiftUI

enum HUDCorner: String, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    func origin(in visible: CGRect, panelSize: NSSize, margin: CGFloat) -> NSPoint {
        switch self {
        case .topLeft:
            return NSPoint(x: visible.minX + margin,
                           y: visible.maxY - panelSize.height - margin)
        case .topRight:
            return NSPoint(x: visible.maxX - panelSize.width - margin,
                           y: visible.maxY - panelSize.height - margin)
        case .bottomLeft:
            return NSPoint(x: visible.minX + margin,
                           y: visible.minY + margin)
        case .bottomRight:
            return NSPoint(x: visible.maxX - panelSize.width - margin,
                           y: visible.minY + margin)
        }
    }
}

@MainActor
final class ThumbnailHUDController: ObservableObject {
    static let shared = ThumbnailHUDController()

    private static let cornerKey = "pressf4.hud.corner"
    private let panelSize = NSSize(width: 252, height: 208)
    private let margin: CGFloat = 22

    private var window: NSWindow?

    @Published var corner: HUDCorner = {
        let raw = UserDefaults.standard.string(forKey: ThumbnailHUDController.cornerKey) ?? ""
        return HUDCorner(rawValue: raw) ?? .bottomRight
    }()

    func setCorner(_ c: HUDCorner) {
        guard corner != c else { return }
        corner = c
        UserDefaults.standard.set(c.rawValue, forKey: Self.cornerKey)
        repositionWindow(animated: true)
    }

    func present(capture: Capture, onOpen: @escaping () -> Void) {
        dismiss()

        guard let screen = activeScreen() else { return }
        let origin = clampedOrigin(in: screen.visibleFrame)
        let rect = NSRect(origin: origin, size: panelSize)

        let w = NSPanel(contentRect: rect,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        w.isFloatingPanel = true
        w.becomesKeyOnlyIfNeeded = true

        let view = ThumbnailHUDView(controller: self,
                                    capture: capture,
                                    onOpen: { [weak self] in
                                        self?.dismiss()
                                        onOpen()
                                    },
                                    onCopy: { [weak self] in
                                        Self.copyToPasteboard(capture: capture)
                                        self?.dismiss()
                                    },
                                    onClose: { [weak self] in
                                        self?.dismiss()
                                    })
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: panelSize)
        w.contentView = host

        w.alphaValue = 0
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            w.animator().alphaValue = 1.0
        }

        window = w
    }

    func dismiss() {
        guard let w = window else { return }
        window = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            w.animator().alphaValue = 0
        }, completionHandler: {
            w.orderOut(nil)
        })
    }

    private func activeScreen() -> NSScreen? {
        let cursor = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(cursor) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// Compute the panel origin for the current corner and pin it inside `visible`
    /// so the panel can never extend off-screen, even if the screen turns out
    /// narrower than the formula assumed.
    private func clampedOrigin(in visible: CGRect) -> NSPoint {
        let raw = corner.origin(in: visible, panelSize: panelSize, margin: margin)
        let maxX = visible.maxX - panelSize.width
        let maxY = visible.maxY - panelSize.height
        let x = max(visible.minX, min(raw.x, maxX))
        let y = max(visible.minY, min(raw.y, maxY))
        return NSPoint(x: x, y: y)
    }

    private func repositionWindow(animated: Bool) {
        guard let w = window else { return }
        let screen = w.screen ?? activeScreen()
        guard let visible = screen?.visibleFrame else { return }
        let origin = clampedOrigin(in: visible)
        let newFrame = NSRect(origin: origin, size: panelSize)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                w.animator().setFrame(newFrame, display: true)
            }
        } else {
            w.setFrame(newFrame, display: true)
        }
    }

    @MainActor
    static func copyToPasteboard(capture: Capture) {
        guard let image = EditorViewModel.renderFlattened(for: capture),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(tiff, forType: .tiff)
        if let png = rep.representation(using: .png, properties: [:]) {
            pb.setData(png, forType: .png)
        }
    }
}

private struct ThumbnailHUDView: View {
    @ObservedObject var controller: ThumbnailHUDController
    let capture: Capture
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onClose: () -> Void

    @State private var hover = false

    var body: some View {
        VStack(spacing: 10) {
            preview
            actionBar
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.40), radius: 22, x: 0, y: 10)
        )
        .overlay(alignment: .topLeading)     { cornerAnchor(.topLeft) }
        .overlay(alignment: .topTrailing)    { cornerAnchor(.topRight) }
        .overlay(alignment: .bottomLeading)  { cornerAnchor(.bottomLeft) }
        .overlay(alignment: .bottomTrailing) { cornerAnchor(.bottomRight) }
        .onHover { hover = $0 }
    }

    private var preview: some View {
        ZStack(alignment: .topTrailing) {
            // Color.clear anchors the layout at 16:10. The image lives in an
            // overlay so its aspect ratio cannot inflate the container — wide
            // captures used to push the action bar buttons off the panel.
            Color.clear
                .frame(maxWidth: .infinity)
                .aspectRatio(16/10, contentMode: .fit)
                .overlay {
                    if let image = LibraryStore.shared.loadImage(for: capture) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        LinearGradient(colors: [.gray.opacity(0.4), .gray.opacity(0.2)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
                .onDrag {
                    let url = LibraryStore.shared.imageURL(for: capture)
                    return NSItemProvider(contentsOf: url) ?? NSItemProvider()
                }

            CloseButton(action: onClose)
                .padding(6)
                .opacity(hover ? 1.0 : 0.55)
                .animation(.easeInOut(duration: 0.15), value: hover)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            Text(capture.displayDims)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.leading, 4)

            Spacer()

            HUDIconButton(icon: "pencil", help: "Edit", action: onOpen)
            HUDIconButton(icon: "doc.on.doc", help: "Copy", action: onCopy)
        }
        .padding(.horizontal, 2)
    }

    private func cornerAnchor(_ c: HUDCorner) -> some View {
        CornerAnchor(corner: c,
                     isActive: controller.corner == c,
                     showHint: hover) {
            controller.setCorner(c)
        }
        .padding(4)
    }
}

private struct CornerAnchor: View {
    let corner: HUDCorner
    let isActive: Bool
    let showHint: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(isActive
                      ? Color.accentColor
                      : Color.white.opacity(hover ? 0.5 : 0.18))
                .overlay(
                    Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5)
                )
                .frame(width: 9, height: 9)
        }
        .buttonStyle(.plain)
        .help(label)
        .opacity(isActive ? 1.0 : (showHint ? 1.0 : 0.0))
        .scaleEffect(hover ? 1.25 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: showHint)
        .animation(.easeInOut(duration: 0.12), value: hover)
        .onHover { hover = $0 }
    }

    private var label: String {
        switch corner {
        case .topLeft:     return "Move to top left"
        case .topRight:    return "Move to top right"
        case .bottomLeft:  return "Move to bottom left"
        case .bottomRight: return "Move to bottom right"
        }
    }
}

private struct CloseButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(
                    Circle().fill(Color.black.opacity(hover ? 0.85 : 0.55))
                )
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help("Close")
        .onHover { hover = $0 }
    }
}

private struct HUDIconButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(hover ? 0.22 : 0.10))
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
    }
}
