import XCTest
import CoreGraphics
@testable import PressF4Core

final class AnnotationTests: XCTestCase {
    func testAnnotationLayerRoundTripsThroughJSON() throws {
        let layer = AnnotationLayer(annotations: [
            Annotation(kind: .rectangle,
                       rect: CGRect(x: 10, y: 20, width: 100, height: 50),
                       color: .red, stroke: 3),
            Annotation(kind: .circle,
                       rect: CGRect(x: 200, y: 50, width: 80, height: 80),
                       color: .blue, stroke: 4),
            Annotation(kind: .text,
                       rect: CGRect(x: 0, y: 0, width: 100, height: 20),
                       color: .black, stroke: 1, text: "Hello"),
            Annotation(kind: .arrow,
                       rect: CGRect(x: 0, y: 0, width: 50, height: 50),
                       color: .green, stroke: 2,
                       arrowStart: CGPoint(x: 0, y: 0),
                       arrowEnd: CGPoint(x: 50, y: 50)),
            Annotation(kind: .freehand,
                       rect: CGRect(x: 5, y: 5, width: 20, height: 20),
                       color: .orange, stroke: 3,
                       points: [CGPoint(x: 5, y: 5), CGPoint(x: 25, y: 25)]),
        ])

        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(AnnotationLayer.self, from: data)

        XCTAssertEqual(decoded, layer)
    }

    func testEmptyLayerRoundTrip() throws {
        let layer = AnnotationLayer()

        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(AnnotationLayer.self, from: data)

        XCTAssertEqual(decoded.annotations.count, 0)
    }

    func testPaletteExposesSixDistinctColors() {
        XCTAssertEqual(AnnotationColor.palette.count, 6)
        XCTAssertEqual(Set(AnnotationColor.palette).count, AnnotationColor.palette.count,
                       "palette entries must be distinct")
    }

    func testRedConstantMatchesExpectedComponents() {
        let red = AnnotationColor.red
        XCTAssertGreaterThan(red.r, 0.9)
        XCTAssertLessThan(red.g, 0.3)
        XCTAssertLessThan(red.b, 0.3)
    }

    func testFilledRectangleRoundTripsThroughJSON() throws {
        let layer = AnnotationLayer(annotations: [
            Annotation(kind: .filledRectangle,
                       rect: CGRect(x: 12, y: 24, width: 80, height: 40),
                       color: .yellow, stroke: 3),
        ])

        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(AnnotationLayer.self, from: data)

        XCTAssertEqual(decoded, layer)
        XCTAssertEqual(decoded.annotations.first?.kind, .filledRectangle)
    }

    func testLegacyJSONWithoutFilledRectangleStillDecodes() throws {
        // Encode a layer using only pre-existing tool cases — the on-disk shape
        // a file written by an earlier app build would have — and confirm the
        // decoder (which now also knows about `filledRectangle`) still accepts it.
        let legacyLayer = AnnotationLayer(annotations: [
            Annotation(kind: .rectangle,
                       rect: CGRect(x: 10, y: 20, width: 30, height: 40),
                       color: .red, stroke: 3),
            Annotation(kind: .circle,
                       rect: CGRect(x: 5, y: 5, width: 20, height: 20),
                       color: .blue, stroke: 2),
        ])
        let data = try JSONEncoder().encode(legacyLayer)

        let asString = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(asString.contains("filledRectangle"),
                       "legacy fixture must not reference the new case")

        let decoded = try JSONDecoder().decode(AnnotationLayer.self, from: data)
        XCTAssertEqual(decoded, legacyLayer)
    }

    func testColorRoundTripsThroughJSON() throws {
        let original = AnnotationColor(r: 0.42, g: 0.13, b: 0.77, a: 0.5)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnnotationColor.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}
