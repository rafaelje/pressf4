import SwiftUI
import AppKit

@MainActor
final class ScrollingCaptureController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = ScrollingCaptureController()
    @Published var preview: NSImage?
    @Published var busy = false
    @Published var pending: CGImage?
    @Published var overlap = 0.0
    @Published var message = ""
    @Published var frameCount = 1
    private var panel: NSPanel?
    private var rect: CGRect = .zero
    private var combined: CGImage?
    private var previous: CGImage?
    private var generation = UUID()

    func begin() {
        guard panel == nil, !busy else { panel?.orderFrontRegardless(); return }
        SelectionOverlayController.shared.begin(onComplete: { rect in
            self.rect = rect
            self.busy = true
            Task {
                defer { self.busy = false }
                do {
                    let image = try await CaptureService.shared.capture(rectGlobal: rect)
                    self.combined = image
                    self.previous = image
                    self.pending = nil
                    self.frameCount = 1
                    self.preview = NSImage(cgImage: image, size: .zero)
                    self.message = "Scroll down in the source app, leaving some content overlapping. Then capture the next frame."
                    self.showPanel()
                } catch { AppController.shared.presentError(error, title: "Could not start scrolling capture") }
            }
        }, onCancel: {})
    }

    private func showPanel() {
        let window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 420, height: 620),
                             styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        window.title = "Scrolling Capture"
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 380, height: 500)
        window.contentView = NSHostingView(rootView: ScrollingCaptureView(controller: self))
        window.delegate = self
        panel = window
        window.center()
        window.orderFrontRegardless()
    }

    func captureNext() {
        guard !busy, let previous else { return }
        busy = true
        let token = generation
        Task {
            defer { if generation == token { busy = false } }
            do {
                let next = try await CaptureService.shared.capture(rectGlobal: rect)
                guard generation == token else { return }
                guard next.width == previous.width, next.height == previous.height else {
                    throw CaptureError.captureFailed("The capture size changed. Start a new scrolling capture.")
                }
                let match = await Task.detached { ImageStitcher.suggestedOverlap(previous: previous, next: next) }.value
                guard generation == token else { return }
                pending = next
                overlap = Double(match ?? next.height / 3)
                message = match == nil ? "Could not align reliably. Adjust overlap and inspect the join before adding." : "Overlap detected. Inspect the join, then add this frame."
                updatePreview()
            } catch { AppController.shared.presentError(error, title: "Could not capture next frame") }
        }
    }

    func updatePreview() {
        // Preview only the bottom frame and its join so slider work stays bounded
        // as the capture grows, while preserving the actual pixels at the seam.
        guard let combined, let previous, let pending,
              let bottom = combined.cropping(to: CGRect(x: 0, y: combined.height - previous.height,
                                                        width: combined.width, height: previous.height)) else { return }
        preview = ImageStitcher.stitch(bottom, pending, overlap: Int(overlap))
        if preview == nil { message = "The image is too large. Finish this capture and start another." }
    }

    func addFrame() {
        guard !busy, let combined, let pending else { return }
        guard let stitched = ImageStitcher.stitch(combined, pending, overlap: Int(overlap)),
              let cg = stitched.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            message = "The image is too large. Discard this frame and finish the capture."
            return
        }
        self.combined = cg
        preview = stitched
        previous = pending
        self.pending = nil
        frameCount += 1
        message = "Frame added. Scroll down again, or finish to save."
    }

    func discardFrame() {
        pending = nil
        if let combined { preview = NSImage(cgImage: combined, size: .zero) }
        message = "Frame discarded. Scroll down and try again."
    }

    func finish() {
        guard !busy, pending == nil, let combined else { return }
        do {
            try AppController.shared.acceptCapture(combined)
            panel?.close()
            AppController.shared.showMainWindow()
        } catch { AppController.shared.presentError(error, title: "Could not save scrolling capture") }
    }

    func windowWillClose(_ notification: Notification) {
        generation = UUID()
        combined = nil; previous = nil; pending = nil; preview = nil
        panel = nil; busy = false
    }
}

private struct ScrollingCaptureView: View {
    @ObservedObject var controller: ScrollingCaptureController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(controller.frameCount) frame\(controller.frameCount == 1 ? "" : "s")").font(.headline)
            Text("Select only the scrolling content; exclude fixed headers and sidebars.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                if let image = controller.preview {
                    Image(nsImage: image).resizable().scaledToFit()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(controller.message).font(.callout)
            if let pending = controller.pending {
                Text("Overlap: \(Int(controller.overlap)) px").font(.caption.monospacedDigit())
                Slider(value: $controller.overlap, in: 0...Double(max(1, pending.height - 1)), step: 1)
                    .onChange(of: controller.overlap) { controller.updatePreview() }
                HStack {
                    Button("Discard frame") { controller.discardFrame() }
                    Spacer()
                    Button("Add frame") { controller.addFrame() }
                        .disabled(controller.preview == nil).buttonStyle(.borderedProminent)
                }
            } else {
                HStack {
                    Button(controller.busy ? "Capturing…" : "Capture next frame") { controller.captureNext() }
                    Spacer()
                    Button("Finish") { controller.finish() }.buttonStyle(.borderedProminent)
                }.disabled(controller.busy)
            }
        }.padding(16)
    }
}
