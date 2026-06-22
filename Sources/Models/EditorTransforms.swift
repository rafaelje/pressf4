import Foundation
import CoreGraphics

enum ResizeCorner {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// Pure geometric transforms applied to annotations while the user drags resize handles
/// or moves a selection. Extracted from `EditorViewModel` so they are unit-testable
/// without an AppKit / SwiftUI build.
enum EditorTransforms {
    struct Transformed: Equatable {
        var rect: CGRect
        var arrowStart: CGPoint?
        var arrowEnd: CGPoint?
        var points: [CGPoint]?
    }

    /// Resize a rectangle by dragging one of its corners to `imagePoint`. Optional
    /// arrow endpoints and freehand `points` are rescaled proportionally so they
    /// follow the new rect.
    static func resize(anchor: CGRect,
                       arrowStart: CGPoint?,
                       arrowEnd: CGPoint?,
                       points: [CGPoint]?,
                       corner: ResizeCorner,
                       to imagePoint: CGPoint) -> Transformed {
        var newRect: CGRect
        switch corner {
        case .topLeft:
            newRect = CGRect(x: imagePoint.x, y: imagePoint.y,
                             width: anchor.maxX - imagePoint.x,
                             height: anchor.maxY - imagePoint.y)
        case .topRight:
            newRect = CGRect(x: anchor.minX, y: imagePoint.y,
                             width: imagePoint.x - anchor.minX,
                             height: anchor.maxY - imagePoint.y)
        case .bottomLeft:
            newRect = CGRect(x: imagePoint.x, y: anchor.minY,
                             width: anchor.maxX - imagePoint.x,
                             height: imagePoint.y - anchor.minY)
        case .bottomRight:
            newRect = CGRect(x: anchor.minX, y: anchor.minY,
                             width: imagePoint.x - anchor.minX,
                             height: imagePoint.y - anchor.minY)
        }
        if newRect.width < 0 {
            newRect.origin.x += newRect.width
            newRect.size.width = -newRect.width
        }
        if newRect.height < 0 {
            newRect.origin.y += newRect.height
            newRect.size.height = -newRect.height
        }

        guard anchor.width > 0, anchor.height > 0 else {
            return Transformed(rect: newRect,
                               arrowStart: arrowStart,
                               arrowEnd: arrowEnd,
                               points: points)
        }
        let sx = newRect.width / anchor.width
        let sy = newRect.height / anchor.height
        let mappedStart = arrowStart.map { p in
            CGPoint(x: newRect.minX + (p.x - anchor.minX) * sx,
                    y: newRect.minY + (p.y - anchor.minY) * sy)
        }
        let mappedEnd = arrowEnd.map { p in
            CGPoint(x: newRect.minX + (p.x - anchor.minX) * sx,
                    y: newRect.minY + (p.y - anchor.minY) * sy)
        }
        let mappedPoints = points.map { list in
            list.map { p in
                CGPoint(x: newRect.minX + (p.x - anchor.minX) * sx,
                        y: newRect.minY + (p.y - anchor.minY) * sy)
            }
        }
        return Transformed(rect: newRect,
                           arrowStart: mappedStart,
                           arrowEnd: mappedEnd,
                           points: mappedPoints)
    }

    /// Translate an annotation by `translation`, carrying any arrow endpoints and freehand
    /// points along by the same offset.
    static func move(anchor: CGRect,
                     arrowStart: CGPoint?,
                     arrowEnd: CGPoint?,
                     points: [CGPoint]?,
                     by translation: CGSize) -> Transformed {
        let newRect = CGRect(x: anchor.minX + translation.width,
                             y: anchor.minY + translation.height,
                             width: anchor.width,
                             height: anchor.height)
        let mappedStart = arrowStart.map {
            CGPoint(x: $0.x + translation.width, y: $0.y + translation.height)
        }
        let mappedEnd = arrowEnd.map {
            CGPoint(x: $0.x + translation.width, y: $0.y + translation.height)
        }
        let mappedPoints = points.map { list in
            list.map {
                CGPoint(x: $0.x + translation.width, y: $0.y + translation.height)
            }
        }
        return Transformed(rect: newRect,
                           arrowStart: mappedStart,
                           arrowEnd: mappedEnd,
                           points: mappedPoints)
    }
}
