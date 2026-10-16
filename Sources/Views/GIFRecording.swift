import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class GIFRecordingController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = GIFRecordingController()

    enum Phase: Equatable {
        case countdown, starting, recording, encoding, ready, failed
    }

    @Published private(set) var phase: Phase = .countdown
    @Published private(set) var countdown = 3
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var gifURL: URL?
    @Published private(set) var message = ""
    private var panel: NSPanel?
    private var session: GIFRecordingSession?
    private var operation: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var generation = UUID()

    func begin() {
        guard panel == nil else { panel?.makeKeyAndOrderFront(nil); return }
        SelectionOverlayController.shared.begin(onComplete: { [weak self] rect in
            self?.prepare(rect: rect)
        }, onCancel: {})
    }

    private func prepare(rect: CGRect) {
        generation = UUID()
        let token = generation
        phase = .countdown
        countdown = 3
        elapsed = 0
        gifURL = nil
        message = "Switch to the app you want to record."
        showPanel()
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                for seconds in (1...3).reversed() {
                    countdown = seconds
                    try await Task.sleep(for: .seconds(1))
                }
                try Task.checkCancellation()
                phase = .starting
                message = "Preparing screen recording…"
                let recording = try GIFRecordingSession { [weak self] error in
                    guard let self, self.generation == token,
                          self.phase == .starting || self.phase == .recording else { return }
                    self.fail(error)
                }
                session = recording
                try await recording.start(rect: rect)
                guard generation == token, !Task.isCancelled, phase == .starting else {
                    await recording.discard()
                    return
                }
                phase = .recording
                message = "Recording selected area. Stops automatically after 15 seconds."
                let start = ProcessInfo.processInfo.systemUptime
                ticker = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(100))
                        guard !Task.isCancelled, let self, self.generation == token, self.phase == .recording else { return }
                        self.elapsed = min(GIFEncoder.maximumDuration, ProcessInfo.processInfo.systemUptime - start)
                        if self.elapsed >= GIFEncoder.maximumDuration { self.stop(); return }
                    }
                }
            } catch is CancellationError {
                // Closing the panel cancels the countdown or stream startup.
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                fail(error)
            }
        }
    }

    func stop() {
        guard phase == .recording, let session else { return }
        ticker?.cancel()
        ticker = nil
        phase = .encoding
        message = "Creating your GIF…"
        let token = generation
        operation = Task { [weak self] in
            do {
                let url = try await session.finish()
                guard let self, self.generation == token, !Task.isCancelled else {
                    await session.discard()
                    return
                }
                self.gifURL = url
                self.phase = .ready
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                self.message = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) + " · Looping GIF · No audio"
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.fail(error)
            }
        }
    }

    private func fail(_ error: Error) {
        ticker?.cancel()
        ticker = nil
        phase = .failed
        message = error.localizedDescription
        if let session {
            self.session = nil
            Task { await session.discard() }
        }
    }

    func cancel() { panel?.close() }

    func save() {
        guard phase == .ready, let gifURL else { return }
        let save = NSSavePanel()
        save.allowedContentTypes = [.gif]
        save.nameFieldStringValue = "recording-\(Int(Date().timeIntervalSince1970)).gif"
        save.canCreateDirectories = true
        guard save.runModal() == .OK, let target = save.url else { return }
        do {
            // Atomic write also supports replacing a user-approved existing file.
            try Data(contentsOf: gifURL).write(to: target, options: .atomic)
            message = "Saved \(target.lastPathComponent)"
        } catch { AppController.shared.presentError(error, title: "Could not save GIF") }
    }

    func copy() {
        guard let gifURL else { return }
        do {
            let data = try Data(contentsOf: gifURL)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(data, forType: NSPasteboard.PasteboardType(UTType.gif.identifier))
            message = "GIF copied. Paste into an app that supports animated images."
        } catch { AppController.shared.presentError(error, title: "Could not copy GIF") }
    }

    private func showPanel() {
        let window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 440, height: 380),
                             styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        window.title = "Record GIF"
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: GIFRecordingView(controller: self))
        window.delegate = self
        panel = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        generation = UUID()
        operation?.cancel()
        ticker?.cancel()
        operation = nil; ticker = nil
        if let session {
            self.session = nil
            Task { await session.discard() }
        }
        gifURL = nil
        panel = nil
    }
}

private struct GIFRecordingView: View {
    @ObservedObject var controller: GIFRecordingController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(title, systemImage: controller.phase == .recording ? "record.circle.fill" : "photo.on.rectangle")
                    .font(.headline)
                    .foregroundStyle(controller.phase == .recording ? Color.red : Color.primary)
                Spacer()
                Text("10 FPS · ≤800 px").font(.caption).foregroundStyle(.secondary)
            }
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                switch controller.phase {
                case .countdown:
                    Text("\(controller.countdown)").font(.system(size: 56, weight: .medium, design: .rounded))
                        .accessibilityLabel("Recording starts in \(controller.countdown) seconds")
                case .recording:
                    VStack(spacing: 12) {
                        Text(String(format: "%.1f / 15 s", controller.elapsed))
                            .font(.system(size: 28, weight: .medium, design: .monospaced))
                        ProgressView(value: controller.elapsed, total: 15).frame(width: 240)
                    }
                case .starting, .encoding:
                    ProgressView()
                case .ready:
                    if let url = controller.gifURL { AnimatedGIFPreview(url: url).padding(8) }
                case .failed:
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
                }
            }.frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 6))
            Text(controller.message).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(controller.phase == .ready || controller.phase == .failed ? "Close" : "Cancel") { controller.cancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if controller.phase == .recording {
                    Button("Stop recording") { controller.stop() }.buttonStyle(.borderedProminent)
                } else if controller.phase == .ready {
                    Button("Copy GIF") { controller.copy() }
                    Button("Save GIF…") { controller.save() }.buttonStyle(.borderedProminent)
                }
            }
        }.padding(20).frame(width: 440)
    }

    private var title: String {
        switch controller.phase {
        case .countdown: return "Get ready"
        case .starting: return "Starting recording"
        case .recording: return "Recording GIF"
        case .encoding: return "Creating GIF"
        case .ready: return "GIF ready"
        case .failed: return "Recording failed"
        }
    }
}

private struct AnimatedGIFPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = FlexibleGIFImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.image = NSImage(contentsOf: url)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {}
}

private final class FlexibleGIFImageView: NSImageView {
    // The recording's pixel dimensions must not dictate the panel's layout.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
