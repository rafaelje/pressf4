import SwiftUI
import AppKit

@MainActor
final class PinnedCaptureController: NSObject, NSWindowDelegate {
    static let shared = PinnedCaptureController()
    private var panels: [NSPanel] = []

    func present(image: NSImage) {
        let ratio = min(1, 560 / max(image.size.width, image.size.height))
        let size = CGSize(width: max(220, image.size.width * ratio), height: max(160, image.size.height * ratio) + 40)
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Pinned Capture"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = CGSize(width: 220, height: 160)
        panel.contentView = NSHostingView(rootView: PinnedCaptureView(image: image, panel: panel))
        panel.delegate = self
        panels.append(panel)
        panel.center()
        panel.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSPanel else { return }
        panels.removeAll { $0 === window }
    }
}

private struct PinnedCaptureView: View {
    let image: NSImage
    weak var panel: NSPanel?
    @State private var opacity = 1.0

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text("Opacity")
                Slider(value: $opacity, in: 0.2...1).accessibilityLabel("Window opacity")
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                }
            }.padding(8)
        }
        .onChange(of: opacity) { panel?.alphaValue = opacity }
    }
}
