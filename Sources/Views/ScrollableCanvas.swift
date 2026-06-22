import SwiftUI
import AppKit

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
