import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import PressF4Core

final class GIFEncoderTests: XCTestCase {
    private func workspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func frame(in directory: URL, name: String, color: NSColor, time: Double, width: Int = 16) throws -> GIFFrame {
        let image = try XCTUnwrap(CaptureRenderer.bitmap(size: CGSize(width: width, height: 12)) {
            color.setFill()
            CGRect(x: 0, y: 0, width: width, height: 12).fill()
        })
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let url = directory.appendingPathComponent(name + ".png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return GIFFrame(url: url, time: time)
    }

    func testAnimatedGIFContainsFramesTimingLoopAndDimensions() throws {
        let folder = try workspace()
        let frames = try [frame(in: folder, name: "red", color: .red, time: 0),
                          frame(in: folder, name: "green", color: .green, time: 0.3),
                          frame(in: folder, name: "blue", color: .blue, time: 0.5)]
        let url = folder.appendingPathComponent("test.gif")
        try GIFEncoder.encode(frames: frames, duration: 1.2, to: url)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 3)
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.gif.identifier)
        let global = try XCTUnwrap(CGImageSourceCopyProperties(source, nil) as? [String: Any])
        let gif = try XCTUnwrap(global[kCGImagePropertyGIFDictionary as String] as? [String: Any])
        XCTAssertEqual(gif[kCGImagePropertyGIFLoopCount as String] as? Int, 0)
        for (index, delay) in [0.3, 0.2, 0.7].enumerated() {
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any])
            let frameGIF = try XCTUnwrap(properties[kCGImagePropertyGIFDictionary as String] as? [String: Any])
            XCTAssertEqual(try XCTUnwrap(frameGIF[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double), delay, accuracy: 0.01)
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, index, nil))
            XCTAssertEqual(image.width, 16)
            XCTAssertEqual(image.height, 12)
            let color = try XCTUnwrap(NSBitmapImageRep(cgImage: image).colorAt(x: 5, y: 5)?.usingColorSpace(.deviceRGB))
            let components = [color.redComponent, color.greenComponent, color.blueComponent]
            XCTAssertGreaterThan(components[index], 0.9)
        }
    }

    func testStaticScreenKeepsFullRecordingDuration() throws {
        let folder = try workspace()
        let still = try frame(in: folder, name: "still", color: .white, time: 0)
        XCTAssertEqual(try GIFEncoder.delays(for: [still], duration: 15), [15])
        let url = folder.appendingPathComponent("still.gif")
        try GIFEncoder.encode(frames: [still], duration: 15, to: url)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 1)
    }

    func testOutputSizeCapsBothDimensionsAndDoesNotUpscale() {
        XCTAssertEqual(GIFEncoder.outputSize(for: CGSize(width: 1920, height: 1080)), CGSize(width: 800, height: 450))
        XCTAssertEqual(GIFEncoder.outputSize(for: CGSize(width: 400, height: 2400)), CGSize(width: 133, height: 800))
        XCTAssertEqual(GIFEncoder.outputSize(for: CGSize(width: 200, height: 100)), CGSize(width: 200, height: 100))
        XCTAssertEqual(GIFEncoder.outputSize(for: CGSize(width: 0, height: 20)), .zero)
    }

    func testInvalidTimelineAndEmptyRecordingAreRejected() throws {
        let url = URL(fileURLWithPath: "/unused")
        XCTAssertThrowsError(try GIFEncoder.delays(for: [], duration: 1))
        XCTAssertThrowsError(try GIFEncoder.delays(for: [GIFFrame(url: url, time: 1)], duration: 2))
        XCTAssertThrowsError(try GIFEncoder.delays(for: [GIFFrame(url: url, time: 0)], duration: 16))
        XCTAssertThrowsError(try GIFEncoder.delays(for: [GIFFrame(url: url, time: 0), GIFFrame(url: url, time: 0)], duration: 1))
        let frames = (0..<151).map { GIFFrame(url: url, time: Double($0) / 10) }
        XCTAssertThrowsError(try GIFEncoder.delays(for: frames, duration: 15))
    }

    func testMissingAndMismatchedFramesLeaveNoPartialGIF() throws {
        let folder = try workspace()
        let first = try frame(in: folder, name: "first", color: .red, time: 0)
        let other = try frame(in: folder, name: "other", color: .blue, time: 0.1, width: 30)
        let output = folder.appendingPathComponent("partial.gif")
        XCTAssertThrowsError(try GIFEncoder.encode(frames: [first, other], duration: 0.2, to: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let missing = GIFFrame(url: folder.appendingPathComponent("missing.png"), time: 0.1)
        XCTAssertThrowsError(try GIFEncoder.encode(frames: [first, missing], duration: 0.2, to: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
}
