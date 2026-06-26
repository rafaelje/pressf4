import Foundation
import CoreGraphics
import SwiftUI

enum AnnotationTool: String, CaseIterable, Codable {
    case select, hand, rectangle, filledRectangle, circle, arrow, text, freehand

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .hand: return "hand.raised.fill"
        case .rectangle: return "rectangle"
        case .filledRectangle: return "rectangle.fill"
        case .circle: return "circle"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        case .freehand: return "scribble.variable"
        }
    }

    var label: String {
        switch self {
        case .select: return "Select"
        case .hand: return "Pan"
        case .rectangle: return "Rectangle"
        case .filledRectangle: return "Filled"
        case .circle: return "Circle"
        case .arrow: return "Arrow"
        case .text: return "Text"
        case .freehand: return "Draw"
        }
    }
}

struct AnnotationColor: Codable, Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .red
        self.r = Double(ns.redComponent)
        self.g = Double(ns.greenComponent)
        self.b = Double(ns.blueComponent)
        self.a = Double(ns.alphaComponent)
    }

    init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var cgColor: CGColor { nsColor.cgColor }

    static let red    = AnnotationColor(r: 1.0, g: 0.23, b: 0.19)
    static let orange = AnnotationColor(r: 1.0, g: 0.58, b: 0.0)
    static let yellow = AnnotationColor(r: 1.0, g: 0.8,  b: 0.0)
    static let green  = AnnotationColor(r: 0.2, g: 0.78, b: 0.35)
    static let blue   = AnnotationColor(r: 0.31, g: 0.55, b: 1.0)
    static let black  = AnnotationColor(r: 0.1, g: 0.11, b: 0.14)

    static let palette: [AnnotationColor] = [.red, .orange, .yellow, .green, .blue, .black]
}

struct Annotation: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var kind: AnnotationTool
    var rect: CGRect
    var color: AnnotationColor
    var stroke: Double
    var text: String?
    var arrowStart: CGPoint?
    var arrowEnd: CGPoint?
    var points: [CGPoint]?

    init(id: UUID = UUID(),
         kind: AnnotationTool,
         rect: CGRect,
         color: AnnotationColor,
         stroke: Double = 3.0,
         text: String? = nil,
         arrowStart: CGPoint? = nil,
         arrowEnd: CGPoint? = nil,
         points: [CGPoint]? = nil) {
        self.id = id
        self.kind = kind
        self.rect = rect
        self.color = color
        self.stroke = stroke
        self.text = text
        self.arrowStart = arrowStart
        self.arrowEnd = arrowEnd
        self.points = points
    }
}

struct AnnotationLayer: Codable, Equatable {
    var annotations: [Annotation] = []
}
