import Foundation

/// Bounded undo/redo stack. Generic and pure so it can be unit-tested without
/// the editor view model and its disk dependencies.
struct LayerHistory<T> {
    let limit: Int
    private(set) var undoStack: [T] = []
    private(set) var redoStack: [T] = []

    init(limit: Int = 50) {
        self.limit = limit
    }

    mutating func snapshot(_ current: T) {
        undoStack.append(current)
        if undoStack.count > limit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    mutating func undo(current: T) -> T? {
        guard let prev = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return prev
    }

    mutating func redo(current: T) -> T? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    mutating func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
