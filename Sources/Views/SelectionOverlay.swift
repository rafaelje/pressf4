import AppKit
import SwiftUI

/// Full-screen translucent overlay that lets the user drag-select an area.
/// Calls `onComplete` with a CGRect in global (top-left) coordinates, or `onCancel` on Esc.
@MainActor
final class SelectionOverlayController {
    static let shared = SelectionOverlayController()

    private var windows: [SelectionWindow] = []

    func begin(onComplete: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        guard windows.isEmpty else { return }

        let completion: (CGRect?) -> Void = { [weak self] rect in
            self?.dismiss()
            if let rect = rect { onComplete(rect) } else { onCancel() }
        }

        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen, completion: completion)
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismiss() {
        for w in windows { w.orderOut(nil); w.close() }
        windows.removeAll()
    }
}

final class SelectionWindow: NSWindow {
    private let completion: (CGRect?) -> Void
    private weak var screenRef: NSScreen?

    init(screen: NSScreen, completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
        self.screenRef = screen
        super.init(contentRect: screen.frame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hasShadow = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.setFrame(screen.frame, display: true)

        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                 screen: screen,
                                 completion: completion)
        self.contentView = view
        self.initialFirstResponder = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        completion(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            completion(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}

final class SelectionView: NSView {
    private let screenRef: NSScreen
    private let completion: (CGRect?) -> Void

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var trackingArea: NSTrackingArea?

    private let dimColor   = NSColor(white: 0, alpha: 0.35)
    private let strokeColor = NSColor.white
    private let handleColor = NSColor.white
    private let crosshairColor = NSColor(white: 1.0, alpha: 0.25)

    init(frame: NSRect, screen: NSScreen, completion: @escaping (CGRect?) -> Void) {
        self.screenRef = screen
        self.completion = completion
        super.init(frame: frame)
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        if startPoint == nil {
            currentPoint = convert(event.locationInWindow, from: nil)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let s = startPoint, let c = currentPoint else {
            completion(nil); return
        }
        let localRect = normalize(s, c)
        if localRect.width < 4 || localRect.height < 4 {
            completion(nil); return
        }
        let globalRect = localToGlobalTopLeft(localRect)
        completion(globalRect)
    }

    private func normalize(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x),
               y: min(a.y, b.y),
               width: abs(a.x - b.x),
               height: abs(a.y - b.y))
    }

    /// Convert a rect in this view's local coordinates (bottom-left origin, points relative to its screen)
    /// to a global rect in CG global coordinates (top-left origin, primary screen frame as anchor).
    private func localToGlobalTopLeft(_ local: NSRect) -> CGRect {
        let screenFrame = screenRef.frame
        let globalBottomLeft = NSRect(x: screenFrame.origin.x + local.origin.x,
                                      y: screenFrame.origin.y + local.origin.y,
                                      width: local.width,
                                      height: local.height)
        guard let primary = NSScreen.screens.first else { return globalBottomLeft }
        let topY = primary.frame.height - globalBottomLeft.origin.y - globalBottomLeft.height
        return CGRect(x: globalBottomLeft.origin.x, y: topY,
                      width: globalBottomLeft.width, height: globalBottomLeft.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(dimColor.cgColor)
        ctx.fill(bounds)

        if let s = startPoint, let c = currentPoint {
            let rect = normalize(s, c)

            ctx.setBlendMode(.clear)
            ctx.fill(rect)
            ctx.setBlendMode(.normal)

            ctx.setStrokeColor(strokeColor.cgColor)
            ctx.setLineWidth(1.0)
            ctx.stroke(rect)

            drawHandles(in: rect, ctx: ctx)
            drawDims(rect: rect, ctx: ctx)
        } else if let c = currentPoint {
            ctx.setStrokeColor(crosshairColor.cgColor)
            ctx.setLineWidth(1.0)
            ctx.move(to: CGPoint(x: c.x, y: 0))
            ctx.addLine(to: CGPoint(x: c.x, y: bounds.height))
            ctx.move(to: CGPoint(x: 0, y: c.y))
            ctx.addLine(to: CGPoint(x: bounds.width, y: c.y))
            ctx.strokePath()
        }
    }

    private func drawHandles(in rect: NSRect, ctx: CGContext) {
        let positions: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        ctx.setFillColor(handleColor.cgColor)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(1)
        for p in positions {
            let r = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
            ctx.fillEllipse(in: r)
            ctx.strokeEllipse(in: r)
        }
    }

    private func drawDims(rect: NSRect, ctx: CGContext) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let padding: CGFloat = 6
        let x = rect.midX - (size.width + padding * 2) / 2
        let y = max(8, rect.minY - size.height - padding * 2 - 4)
        let bgRect = NSRect(x: x, y: y, width: size.width + padding * 2, height: size.height + padding)
        let path = NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        path.fill()
        str.draw(at: NSPoint(x: x + padding, y: y + padding / 2))
    }
}
