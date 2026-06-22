import AppKit
import SwiftUI

@MainActor
final class ThumbnailHUDController {
    static let shared = ThumbnailHUDController()

    private var window: NSWindow?

    func present(capture: Capture, onOpen: @escaping () -> Void) {
        dismiss()

        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 252, height: 208)
        let margin: CGFloat = 22
        let originX = screen.visibleFrame.maxX - size.width - margin
        let originY = screen.visibleFrame.minY + margin
        let rect = NSRect(x: originX, y: originY, width: size.width, height: size.height)

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

        let view = ThumbnailHUDView(capture: capture,
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
        host.frame = NSRect(origin: .zero, size: size)
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

    static func copyToPasteboard(capture: Capture) {
        guard let image = LibraryStore.shared.loadImage(for: capture) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }
}

private struct ThumbnailHUDView: View {
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
        .onHover { hover = $0 }
    }

    private var preview: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = LibraryStore.shared.loadImage(for: capture) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: [.gray.opacity(0.4), .gray.opacity(0.2)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16/10, contentMode: .fit)
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
