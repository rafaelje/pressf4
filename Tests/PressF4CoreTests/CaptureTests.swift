import XCTest
@testable import PressF4Core

final class CaptureTests: XCTestCase {
    func testRoundTripsThroughJSON() throws {
        let original = Capture(imageFileName: "x.png",
                               annotationsFileName: "x.json",
                               width: 800, height: 600, sizeBytes: 1234)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Capture.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testDisplayDimsFormatsWidthAndHeight() {
        let c = Capture(imageFileName: "x.png", annotationsFileName: "x.json",
                        width: 1920, height: 1080, sizeBytes: 0)

        XCTAssertEqual(c.displayDims, "1920×1080")
    }

    func testDisplaySizePrintsKilobytesUnderOneMegabyte() {
        let c = Capture(imageFileName: "x.png", annotationsFileName: "x.json",
                        width: 0, height: 0, sizeBytes: 524_288)

        XCTAssertTrue(c.displaySize.contains("KB"),
                      "got '\(c.displaySize)' for a 512 KB capture")
    }

    func testDisplaySizePrintsMegabytesAtAndAboveOneMegabyte() {
        let c = Capture(imageFileName: "x.png", annotationsFileName: "x.json",
                        width: 0, height: 0, sizeBytes: 5 * 1024 * 1024)

        XCTAssertTrue(c.displaySize.contains("MB"),
                      "got '\(c.displaySize)' for a 5 MB capture")
    }
}
