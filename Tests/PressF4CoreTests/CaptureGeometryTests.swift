import XCTest
import CoreGraphics
@testable import PressF4Core

final class CaptureGeometryTests: XCTestCase {
    func testClampedCropRectShrinksOverflowToImageBounds() {
        let imgSize = CGSize(width: 2000, height: 1200)
        let overflow = CGRect(x: -50, y: 1000, width: 600, height: 400)

        let clamped = CaptureGeometry.clampedCropRect(overflow, imagePixelSize: imgSize)

        XCTAssertNotNil(clamped)
        XCTAssertEqual(clamped?.minX, 0, "negative x is clamped to 0")
        XCTAssertEqual(clamped?.minY, 1000, "valid y kept")
        XCTAssertEqual(clamped?.width, 550, "width recomputed from clamped origin (600 - 50)")
        XCTAssertEqual(clamped?.height, 200, "height truncated to image bottom (1200 - 1000)")
        XCTAssertLessThanOrEqual(clamped?.maxX ?? .infinity, imgSize.width)
        XCTAssertLessThanOrEqual(clamped?.maxY ?? .infinity, imgSize.height)
    }

    func testClampedCropRectReturnsNilWhenFullyOutsideImage() {
        let imgSize = CGSize(width: 2000, height: 1200)
        let outside = CGRect(x: 5000, y: 5000, width: 100, height: 100)

        XCTAssertNil(CaptureGeometry.clampedCropRect(outside, imagePixelSize: imgSize))
    }

    func testClampedCropRectReturnsNilForZeroSizeRect() {
        let imgSize = CGSize(width: 2000, height: 1200)
        let zero = CGRect(x: 100, y: 100, width: 0, height: 0)

        // The previous in-line code could feed CGImage.cropping a 0×0 rect; the helper
        // guards against that.
        XCTAssertNil(CaptureGeometry.clampedCropRect(zero, imagePixelSize: imgSize))
    }

    func testToGlobalTopLeftMapsTopLeftCornerToZero() {
        // 1920×1080 primary screen, a 100×100 NSScreen frame in the top-left has y = 980.
        let primaryHeight: CGFloat = 1080
        let topLeftWindow = CGRect(x: 0, y: 980, width: 100, height: 100)

        let global = CaptureGeometry.toGlobalTopLeft(topLeftWindow, primaryHeight: primaryHeight)

        XCTAssertEqual(global.origin.x, 0)
        XCTAssertEqual(global.origin.y, 0, "top-left of primary maps to global y=0")
        XCTAssertEqual(global.height, 100)
    }

    func testToGlobalTopLeftHandlesMonitorAbovePrimary() {
        // A secondary monitor positioned above the primary (NSScreen y > primaryHeight)
        // must produce a negative global y so CG global coords remain consistent.
        let primaryHeight: CGFloat = 1080
        let aboveFrame = CGRect(x: 0, y: 1080, width: 800, height: 600)

        let global = CaptureGeometry.toGlobalTopLeft(aboveFrame, primaryHeight: primaryHeight)

        XCTAssertEqual(global.origin.y, -600,
                       "secondary monitor above primary has negative global y")
    }

    func testDisplayLocalRectScalesByDisplayPixelDensity() {
        // 1000×500 point display at global (200, 100) with 2× pixel density (2000×1000 px).
        let displayFrame = CGRect(x: 200, y: 100, width: 1000, height: 500)
        let displayPixels = CGSize(width: 2000, height: 1000)
        let request = CGRect(x: 300, y: 200, width: 400, height: 200)

        let local = CaptureGeometry.displayLocalRect(
            globalRect: request,
            displayFrameGlobal: displayFrame,
            displayPixelSize: displayPixels)

        XCTAssertEqual(local.origin.x, 200, "x offset and scaled (100pt * 2)")
        XCTAssertEqual(local.origin.y, 200, "y offset and scaled (100pt * 2)")
        XCTAssertEqual(local.width, 800, "width scaled by display density")
        XCTAssertEqual(local.height, 400, "height scaled by display density")
    }
}
