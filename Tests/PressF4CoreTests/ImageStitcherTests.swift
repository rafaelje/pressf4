import XCTest
import AppKit
@testable import PressF4Core

final class ImageStitcherTests: XCTestCase {
    func testDetectsOverlapAndStitchesWithoutDuplicateRows() throws {
        let source = try XCTUnwrap(CaptureRenderer.bitmap(size: CGSize(width: 96, height: 300)) {
            for y in 0..<300 {
                for x in 0..<96 {
                    let value = CGFloat((y * 71 + x * 37 + y * x * 13) % 251) / 250
                    NSColor(white: value, alpha: 1).setFill()
                    CGRect(x: x, y: y, width: 1, height: 1).fill()
                }
            }
        })
        let cg = try XCTUnwrap(source.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let a = try XCTUnwrap(cg.cropping(to: CGRect(x: 0, y: 0, width: 96, height: 200)))
        let b = try XCTUnwrap(cg.cropping(to: CGRect(x: 0, y: 100, width: 96, height: 200)))
        XCTAssertNil(ImageStitcher.suggestedOverlap(previous: a, next: a))
        XCTAssertEqual(ImageStitcher.suggestedOverlap(previous: a, next: b), 100)
        let result = try XCTUnwrap(ImageStitcher.stitch(a, b, overlap: 100))
        XCTAssertEqual(result.size, source.size)
        let resultCG = try XCTUnwrap(result.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let original = NSBitmapImageRep(cgImage: cg)
        let stitched = NSBitmapImageRep(cgImage: resultCG)
        for y in [0, 99, 199, 200, 299] {
            XCTAssertEqual(stitched.colorAt(x: 25, y: y), original.colorAt(x: 25, y: y))
        }
    }

    func testBlankFramesAreNotAcceptedAsAutomaticMatches() throws {
        let image = try XCTUnwrap(CaptureRenderer.bitmap(size: CGSize(width: 96, height: 100)) {
            NSColor.white.setFill()
            CGRect(x: 0, y: 0, width: 96, height: 100).fill()
        })
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertNil(ImageStitcher.suggestedOverlap(previous: cg, next: cg))
        XCTAssertNil(ImageStitcher.stitch(cg, cg, overlap: 100))
    }
}
