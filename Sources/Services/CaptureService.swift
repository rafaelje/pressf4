import Foundation
import ScreenCaptureKit
import AppKit
import CoreGraphics

enum CaptureError: Error, LocalizedError {
    case noDisplay
    case permissionDenied
    case captureFailed(String)
    case emptyRect

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No available display was found."
        case .permissionDenied: return "Grant Screen Recording permission in System Settings."
        case .captureFailed(let s): return "Capture failed: \(s)"
        case .emptyRect: return "The selected area is too small."
        }
    }
}

@MainActor
final class CaptureService {
    static let shared = CaptureService()

    /// Captures the given rect (in CG global screen coordinates, origin top-left of primary display)
    /// from the display that contains its center, returning a cropped CGImage at the display's native pixel density.
    func capture(rectGlobal: CGRect) async throws -> CGImage {
        guard rectGlobal.width >= 4, rectGlobal.height >= 4 else { throw CaptureError.emptyRect }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                            onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.permissionDenied
        }

        guard let display = bestDisplay(for: rectGlobal, in: content.displays) else {
            throw CaptureError.noDisplay
        }

        let displayFrameGlobal = globalFrame(for: display)
        let scale = CGFloat(display.width) / displayFrameGlobal.width

        let localRect = CGRect(
            x: (rectGlobal.origin.x - displayFrameGlobal.origin.x) * scale,
            y: (rectGlobal.origin.y - displayFrameGlobal.origin.y) * scale,
            width: rectGlobal.width * scale,
            height: rectGlobal.height * scale
        ).integral

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.scalesToFit = false
        config.showsCursor = false
        config.captureResolution = .best
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let fullImage: CGImage
        do {
            fullImage = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                    configuration: config)
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }

        let clamped = CGRect(
            x: max(0, min(localRect.origin.x, CGFloat(fullImage.width - 1))),
            y: max(0, min(localRect.origin.y, CGFloat(fullImage.height - 1))),
            width: min(localRect.width, CGFloat(fullImage.width) - localRect.origin.x),
            height: min(localRect.height, CGFloat(fullImage.height) - localRect.origin.y)
        ).integral

        guard let cropped = fullImage.cropping(to: clamped) else {
            throw CaptureError.captureFailed("crop failed")
        }
        return cropped
    }

    /// Returns the global frame (top-left origin, points) for the SC display by matching to NSScreen.
    private func globalFrame(for display: SCDisplay) -> CGRect {
        if let screen = matchingScreen(for: display) {
            return convertToGlobalTopLeft(screen.frame)
        }
        return CGRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))
    }

    private func matchingScreen(for display: SCDisplay) -> NSScreen? {
        for screen in NSScreen.screens {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               num == display.displayID {
                return screen
            }
        }
        return NSScreen.main
    }

    private func bestDisplay(for rectGlobal: CGRect, in displays: [SCDisplay]) -> SCDisplay? {
        let center = CGPoint(x: rectGlobal.midX, y: rectGlobal.midY)
        for display in displays {
            let frame = globalFrame(for: display)
            if frame.contains(center) { return display }
        }
        return displays.first
    }

    /// Convert NSScreen frame (bottom-left, primary screen at 0,0) into CG global coords (top-left).
    private func convertToGlobalTopLeft(_ frame: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return frame }
        let primaryHeight = primary.frame.height
        let topY = primaryHeight - frame.origin.y - frame.height
        return CGRect(x: frame.origin.x, y: topY, width: frame.width, height: frame.height)
    }
}
