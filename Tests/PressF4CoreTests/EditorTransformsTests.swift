import XCTest
import CoreGraphics
@testable import PressF4Core

final class EditorTransformsTests: XCTestCase {

    // MARK: - move

    func testMoveTranslatesRectArrowAndPoints() {
        let anchor = CGRect(x: 100, y: 100, width: 80, height: 40)

        let result = EditorTransforms.move(
            anchor: anchor,
            arrowStart: CGPoint(x: 100, y: 100),
            arrowEnd: CGPoint(x: 180, y: 140),
            points: [CGPoint(x: 110, y: 110), CGPoint(x: 170, y: 130)],
            by: CGSize(width: 20, height: -10))

        XCTAssertEqual(result.rect, CGRect(x: 120, y: 90, width: 80, height: 40))
        XCTAssertEqual(result.arrowStart, CGPoint(x: 120, y: 90))
        XCTAssertEqual(result.arrowEnd, CGPoint(x: 200, y: 130))
        XCTAssertEqual(result.points, [CGPoint(x: 130, y: 100), CGPoint(x: 190, y: 120)])
    }

    func testMoveKeepsNilArrowAndPointsNil() {
        let anchor = CGRect(x: 100, y: 100, width: 80, height: 40)

        let result = EditorTransforms.move(
            anchor: anchor, arrowStart: nil, arrowEnd: nil, points: nil,
            by: CGSize(width: 5, height: 5))

        XCTAssertNil(result.arrowStart)
        XCTAssertNil(result.arrowEnd)
        XCTAssertNil(result.points)
    }

    // MARK: - resize (corner geometry)

    func testResizeBottomRightGrowsRectDownAndRight() {
        let anchor = CGRect(x: 100, y: 100, width: 100, height: 100)

        let result = EditorTransforms.resize(
            anchor: anchor, arrowStart: nil, arrowEnd: nil, points: nil,
            corner: .bottomRight, to: CGPoint(x: 250, y: 220))

        XCTAssertEqual(result.rect, CGRect(x: 100, y: 100, width: 150, height: 120))
    }

    func testResizeTopLeftExpandsOriginUpLeft() {
        let anchor = CGRect(x: 100, y: 100, width: 100, height: 100)

        let result = EditorTransforms.resize(
            anchor: anchor, arrowStart: nil, arrowEnd: nil, points: nil,
            corner: .topLeft, to: CGPoint(x: 90, y: 80))

        XCTAssertEqual(result.rect, CGRect(x: 90, y: 80, width: 110, height: 120))
    }

    func testResizeTopRightShiftsOriginYAndGrowsWidth() {
        let anchor = CGRect(x: 100, y: 100, width: 100, height: 100)

        let result = EditorTransforms.resize(
            anchor: anchor, arrowStart: nil, arrowEnd: nil, points: nil,
            corner: .topRight, to: CGPoint(x: 220, y: 60))

        XCTAssertEqual(result.rect, CGRect(x: 100, y: 60, width: 120, height: 140))
    }

    func testResizeBottomLeftShiftsOriginXAndGrowsHeight() {
        let anchor = CGRect(x: 100, y: 100, width: 100, height: 100)

        let result = EditorTransforms.resize(
            anchor: anchor, arrowStart: nil, arrowEnd: nil, points: nil,
            corner: .bottomLeft, to: CGPoint(x: 80, y: 220))

        XCTAssertEqual(result.rect, CGRect(x: 80, y: 100, width: 120, height: 120))
    }

    func testResizeNormalizesRectWhenDragCrossesOppositeCorner() {
        // Drag bottomRight past the topLeft corner → the helper must flip the rect so
        // width/height stay non-negative.
        let anchor = CGRect(x: 100, y: 100, width: 50, height: 50)

        let result = EditorTransforms.resize(
            anchor: anchor, arrowStart: nil, arrowEnd: nil, points: nil,
            corner: .bottomRight, to: CGPoint(x: 80, y: 70))

        XCTAssertGreaterThanOrEqual(result.rect.width, 0)
        XCTAssertGreaterThanOrEqual(result.rect.height, 0)
        XCTAssertEqual(result.rect, CGRect(x: 80, y: 70, width: 20, height: 30))
    }

    // MARK: - resize (arrow + freehand preservation)

    func testResizeScalesArrowEndpointsProportionally() {
        let anchor = CGRect(x: 100, y: 100, width: 100, height: 100)

        let result = EditorTransforms.resize(
            anchor: anchor,
            arrowStart: CGPoint(x: 100, y: 100),  // anchor's top-left
            arrowEnd:   CGPoint(x: 200, y: 200),  // anchor's bottom-right
            points: nil,
            corner: .bottomRight,
            to: CGPoint(x: 300, y: 300))           // doubles both axes

        XCTAssertEqual(result.rect, CGRect(x: 100, y: 100, width: 200, height: 200))
        XCTAssertEqual(result.arrowStart, CGPoint(x: 100, y: 100),
                       "arrow start anchored at rect origin stays at new origin")
        XCTAssertEqual(result.arrowEnd, CGPoint(x: 300, y: 300),
                       "arrow end at bottom-right scales to new bottom-right")
    }

    func testResizeScalesFreehandPointsProportionally() {
        let anchor = CGRect(x: 100, y: 100, width: 100, height: 100)

        let result = EditorTransforms.resize(
            anchor: anchor,
            arrowStart: nil, arrowEnd: nil,
            points: [CGPoint(x: 150, y: 150)],  // center of anchor
            corner: .bottomRight,
            to: CGPoint(x: 300, y: 300))         // 2× scale

        XCTAssertEqual(result.points, [CGPoint(x: 200, y: 200)],
                       "freehand point at anchor center remains at new center")
    }

    func testResizeWithDegenerateAnchorLeavesArrowAndPointsUnchanged() {
        // A zero-sized anchor cannot be scaled (would divide by zero). The helper
        // must leave arrow/points as-is rather than crash or produce NaNs.
        let anchor = CGRect(x: 100, y: 100, width: 0, height: 0)
        let arrowStart = CGPoint(x: 100, y: 100)
        let arrowEnd = CGPoint(x: 100, y: 100)
        let points = [CGPoint(x: 100, y: 100)]

        let result = EditorTransforms.resize(
            anchor: anchor,
            arrowStart: arrowStart, arrowEnd: arrowEnd, points: points,
            corner: .bottomRight, to: CGPoint(x: 150, y: 150))

        XCTAssertEqual(result.arrowStart, arrowStart)
        XCTAssertEqual(result.arrowEnd, arrowEnd)
        XCTAssertEqual(result.points, points)
    }
}
