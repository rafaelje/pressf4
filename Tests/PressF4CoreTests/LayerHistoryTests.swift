import XCTest
@testable import PressF4Core

final class LayerHistoryTests: XCTestCase {
    func testUndoReturnsMostRecentSnapshot() {
        var h = LayerHistory<String>()
        h.snapshot("a")
        h.snapshot("b")

        XCTAssertEqual(h.undo(current: "c"), "b")
    }

    func testUndoWalksBackThroughHistory() {
        var h = LayerHistory<String>()
        h.snapshot("a")
        h.snapshot("b")

        let first = h.undo(current: "c")
        let second = h.undo(current: first ?? "")

        XCTAssertEqual(first, "b")
        XCTAssertEqual(second, "a")
    }

    func testUndoReturnsNilWhenStackEmpty() {
        var h = LayerHistory<String>()
        XCTAssertNil(h.undo(current: "anything"))
    }

    func testRedoRestoresValuesPoppedByUndo() {
        var h = LayerHistory<String>()
        h.snapshot("a")
        h.snapshot("b")
        _ = h.undo(current: "c")    // current = "b"
        _ = h.undo(current: "b")    // current = "a"

        XCTAssertEqual(h.redo(current: "a"), "b")
        XCTAssertEqual(h.redo(current: "b"), "c")
        XCTAssertNil(h.redo(current: "c"), "redo stack exhausted")
    }

    func testSnapshotClearsRedoStack() {
        var h = LayerHistory<String>()
        h.snapshot("a")
        h.snapshot("b")
        _ = h.undo(current: "c")    // redo stack now contains "c"

        h.snapshot("x")             // creating a new branch must drop the redo history

        XCTAssertNil(h.redo(current: "x"),
                     "starting a new branch must drop the redo history")
    }

    func testStackRespectsLimitByDroppingOldest() {
        var h = LayerHistory<Int>(limit: 3)
        for i in 0..<10 { h.snapshot(i) }

        XCTAssertEqual(h.undoStack.count, 3)
        XCTAssertEqual(h.undoStack, [7, 8, 9],
                       "oldest snapshots dropped once the limit is exceeded")
    }

    func testResetClearsBothStacks() {
        var h = LayerHistory<Int>()
        h.snapshot(1); h.snapshot(2)
        _ = h.undo(current: 3)

        h.reset()

        XCTAssertNil(h.undo(current: 1))
        XCTAssertNil(h.redo(current: 1))
    }
}
