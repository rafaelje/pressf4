import Foundation
import CoreGraphics

/// Pure geometric helpers used by `CaptureService`. Kept free of AppKit / ScreenCaptureKit
/// so they can be exercised from the smoke-test target.
enum CaptureGeometry {
    /// Convert an NSScreen-style frame (bottom-left origin, primary screen at (0,0))
    /// into CG global coordinates (top-left origin), given the height of the primary screen.
    static func toGlobalTopLeft(_ frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        let topY = primaryHeight - frame.origin.y - frame.height
        return CGRect(x: frame.origin.x, y: topY, width: frame.width, height: frame.height)
    }

    /// Translate a rect in global top-left coords into the local pixel coordinates of a display,
    /// given the display's frame in global coords and the display's pixel size.
    static func displayLocalRect(globalRect: CGRect,
                                  displayFrameGlobal: CGRect,
                                  displayPixelSize: CGSize) -> CGRect {
        let scaleX = displayPixelSize.width / displayFrameGlobal.width
        let scaleY = displayPixelSize.height / displayFrameGlobal.height
        return CGRect(
            x: (globalRect.origin.x - displayFrameGlobal.origin.x) * scaleX,
            y: (globalRect.origin.y - displayFrameGlobal.origin.y) * scaleY,
            width: globalRect.width * scaleX,
            height: globalRect.height * scaleY
        ).integral
    }

    /// Clamp `rect` to the image's pixel bounds. Returns `nil` if the rect is fully outside
    /// the image or shrinks to zero after clamping.
    static func clampedCropRect(_ rect: CGRect, imagePixelSize: CGSize) -> CGRect? {
        let imageBounds = CGRect(origin: .zero, size: imagePixelSize)
        let inter = rect.intersection(imageBounds)
        guard !inter.isNull else { return nil }
        let integral = inter.integral
        guard integral.width >= 1, integral.height >= 1 else { return nil }
        return integral
    }
}
