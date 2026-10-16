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

    func testRecoveredRebuildsEntryFromUUIDNamedPNG() throws {
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let c = try XCTUnwrap(Capture.recovered(imageFileName: "\(id.uuidString).png",
                                                createdAt: created,
                                                width: 800, height: 600, sizeBytes: 1234))

        XCTAssertEqual(c.id, id)
        XCTAssertEqual(c.annotationsFileName, "\(id.uuidString).json")
        XCTAssertEqual(c.createdAt, created)
        XCTAssertEqual(c.displayDims, "800×600")
        XCTAssertEqual(c.sizeBytes, 1234)
    }

    func testRecoveredIgnoresFilesThatAreNotUUIDNamedPNGs() {
        for name in ["screenshot.png", "\(UUID().uuidString).json", "index.json"] {
            XCTAssertNil(Capture.recovered(imageFileName: name, createdAt: Date(),
                                           width: 1, height: 1, sizeBytes: 0),
                         "\(name) should not be recovered")
        }
    }
}
