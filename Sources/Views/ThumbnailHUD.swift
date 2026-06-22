import AppKit
import SwiftUI

@MainActor
final class ThumbnailHUDController {
    static let shared = ThumbnailHUDController()

    private var window: NSWindow?
    private var dismissWork: DispatchWorkItem?

    func present(capture: Capture, onOpen: @escaping () -> Void) {
        dismiss()

        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 220, height: 160)
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
        w.hasShadow = true
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
                                    })
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        w.contentView = host

        w.alphaValue = 0
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            w.animator().alphaValue = 1.0
        }

        window = w
        scheduleDismiss(after: 4.0)
    }

    func dismiss() {
        dismissWork?.cancel()
        guard let w = window else { return }
        window = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            w.animator().alphaValue = 0
        }, completionHandler: {
            w.orderOut(nil)
        })
    }

    private func scheduleDismiss(after seconds: Double) {
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
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

    @State private var hover = false

    var body: some View {
        VStack(spacing: 6) {
            preview
                .frame(maxWidth: .infinity)
                .aspectRatio(16/10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture(perform: onOpen)

            HStack(spacing: 6) {
                Text("\(capture.displayDims) · PNG")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Button(action: onOpen) {
                    Image(systemName: "pencil")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(HUDButtonStyle())
                .help("Editar")

                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(HUDButtonStyle())
                .help("Copiar")
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .onHover { hover = $0 }
    }

    private var preview: some View {
        Group {
            if let image = LibraryStore.shared.loadImage(for: capture) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray
            }
        }
    }
}

private struct HUDButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .font(.system(size: 11))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed
                          ? Color.white.opacity(0.2)
                          : Color.white.opacity(0.08))
            )
    }
}
