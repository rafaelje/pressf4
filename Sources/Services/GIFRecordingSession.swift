import AppKit
import ScreenCaptureKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// All frame state belongs to the serial sample queue. The stream is owned by
/// the main actor; encoding and disk cleanup are queued after frame delivery.
private final class GIFFrameWriter: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.rafaelje.pressf4.gif.frames", qos: .userInitiated)
    let directory: URL
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var frames: [GIFFrame] = []
    private var firstTimestamp: Double?
    private var firstArrival: TimeInterval?
    private var sealed = false
    private var failure: Error?
    private let onFailure: @Sendable (Error) -> Void

    init(directory: URL, onFailure: @escaping @Sendable (Error) -> Void) {
        self.directory = directory
        self.onFailure = onFailure
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !sealed, failure == nil, frames.count < GIFEncoder.maximumFrames,
              sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let timestamp = sampleBuffer.presentationTimeStamp.seconds
        guard timestamp.isFinite else { return }
        let origin = firstTimestamp ?? timestamp
        let time = timestamp - origin
        guard time >= 0, time <= GIFEncoder.maximumDuration - 0.1 + 0.001,
              frames.last.map({ time - $0.time >= 0.1 - 0.001 }) ?? true else { return }
        do {
            try autoreleasepool {
                let input = CIImage(cvPixelBuffer: pixelBuffer)
                guard let cg = context.createCGImage(input, from: input.extent) else { throw GIFError.encodingFailed }
                let url = directory.appendingPathComponent("frame-\(frames.count).png")
                guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                    throw GIFError.encodingFailed
                }
                CGImageDestinationAddImage(destination, cg, nil)
                guard CGImageDestinationFinalize(destination) else { throw GIFError.encodingFailed }
                if firstTimestamp == nil {
                    firstTimestamp = timestamp
                    firstArrival = ProcessInfo.processInfo.systemUptime
                }
                frames.append(GIFFrame(url: url, time: time))
            }
        } catch {
            failure = error
            onFailure(error)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onFailure(error)
    }

    func finish(at stoppedAt: TimeInterval) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.sealed = true
                do {
                    if let error = self.failure { throw error }
                    guard let firstArrival = self.firstArrival, let last = self.frames.last else { throw GIFError.noFrames }
                    // Keep the last delivered frame visible for at least one GIF tick.
                    let duration = min(GIFEncoder.maximumDuration, max(last.time + 0.01, stoppedAt - firstArrival))
                    let output = self.directory.appendingPathComponent("capture.gif")
                    try GIFEncoder.encode(frames: self.frames, duration: duration, to: output)
                    for frame in self.frames { try? FileManager.default.removeItem(at: frame.url) }
                    self.frames.removeAll()
                    continuation.resume(returning: output)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func discard() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.sealed = true
                self.frames.removeAll()
                try? FileManager.default.removeItem(at: self.directory)
                continuation.resume()
            }
        }
    }
}

@MainActor
final class GIFRecordingSession {
    private let writer: GIFFrameWriter
    private var stream: SCStream?
    private var starting = false

    init(onFailure: @escaping @MainActor @Sendable (Error) -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pressf4-gif-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        writer = GIFFrameWriter(directory: directory) { error in
            Task { @MainActor in onFailure(error) }
        }
    }

    func start(rect: CGRect) async throws {
        guard !starting, stream == nil else { return }
        starting = true
        defer { starting = false }
        let content = try await SCShareableContent.excludingDesktopWindows(UserDefaults.standard.bool(forKey: "pressf4.hideDesktop"), onScreenWindowsOnly: true)
        try Task.checkCancellation()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let display = content.displays.first(where: { CGDisplayBounds($0.displayID).contains(center) }) else {
            throw CaptureError.noDisplay
        }
        let displayBounds = CGDisplayBounds(display.displayID)
        let region = rect.intersection(displayBounds)
        guard !region.isNull, region.width >= 4, region.height >= 4 else { throw CaptureError.emptyRect }
        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = region.offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY)
        let scale = CGFloat(display.width) / displayBounds.width
        let size = GIFEncoder.outputSize(for: CGSize(width: region.width * scale, height: region.height * scale))
        config.width = Int(size.width)
        config.height = Int(size.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(GIFEncoder.framesPerSecond))
        config.queueDepth = 3
        config.showsCursor = UserDefaults.standard.bool(forKey: "pressf4.captureCursor")
        config.capturesAudio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.scalesToFit = true
        let stream = SCStream(filter: filter, configuration: config, delegate: writer)
        try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.queue)
        self.stream = stream
        do {
            try await stream.startCapture()
            try Task.checkCancellation()
        } catch {
            try? await stream.stopCapture()
            self.stream = nil
            throw error
        }
    }

    func finish() async throws -> URL {
        let stoppedAt = ProcessInfo.processInfo.systemUptime
        if let stream {
            self.stream = nil
            try await stream.stopCapture()
        }
        return try await writer.finish(at: stoppedAt)
    }

    func discard() async {
        if let stream {
            self.stream = nil
            try? await stream.stopCapture()
        }
        await writer.discard()
    }
}
