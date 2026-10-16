import XCTest
import AppKit
@testable import PressF4Core

final class CaptureRendererTests: XCTestCase {
    private func image(width: Int = 120, height: Int = 100) throws -> NSImage {
        try XCTUnwrap(CaptureRenderer.bitmap(size: CGSize(width: width, height: height)) {
            NSColor.red.setFill()
            CGRect(x: 0, y: 0, width: width, height: height / 2).fill()
            NSColor.blue.setFill()
            CGRect(x: 0, y: height / 2, width: width, height: height - height / 2).fill()
        })
    }

    private func color(_ image: NSImage, x: Int, y: Int) throws -> NSColor {
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return try XCTUnwrap(NSBitmapImageRep(cgImage: cg).colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
    }

    func testRenderingPreservesOrientationAndExactPixelDimensions() throws {
        let output = try XCTUnwrap(CaptureRenderer.render(base: image(), layer: AnnotationLayer()))
        let cg = try XCTUnwrap(output.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(cg.width, 120)
        XCTAssertEqual(cg.height, 100)
        XCTAssertGreaterThan(try color(output, x: 10, y: 10).redComponent, 0.9)
        XCTAssertGreaterThan(try color(output, x: 10, y: 90).blueComponent, 0.9)
    }

    func testCropUsesTopLeftCoordinates() throws {
        var layer = AnnotationLayer()
        layer.cropRect = CGRect(x: 10, y: 0, width: 40, height: 20)
        let output = try XCTUnwrap(CaptureRenderer.render(base: image(), layer: layer))
        XCTAssertEqual(output.size, CGSize(width: 40, height: 20))
        XCTAssertGreaterThan(try color(output, x: 5, y: 5).redComponent, 0.9)
    }

    func testSolidRedactionCannotBeRevealedByLaterAnnotations() throws {
        let rect = CGRect(x: 0, y: 0, width: 40, height: 40)
        let layer = AnnotationLayer(annotations: [
            Annotation(kind: .redact, rect: rect, color: .red),
            Annotation(kind: .filledRectangle, rect: rect, color: .yellow),
            Annotation(kind: .pixelate, rect: rect, color: .red)
        ])
        let output = try XCTUnwrap(CaptureRenderer.render(base: image(), layer: layer))
        let pixel = try color(output, x: 20, y: 20)
        XCTAssertLessThan(pixel.redComponent, 0.02)
        XCTAssertLessThan(pixel.greenComponent, 0.02)
        XCTAssertLessThan(pixel.blueComponent, 0.02)
        XCTAssertEqual(pixel.alphaComponent, 1, accuracy: 0.01)
    }

    func testBlurAndPixelateUseSelectedRegionAtTopLeft() throws {
        for tool in [AnnotationTool.blur, .pixelate] {
            let layer = AnnotationLayer(annotations: [Annotation(kind: tool,
                rect: CGRect(x: 0, y: 0, width: 40, height: 40), color: .red)])
            let output = try XCTUnwrap(CaptureRenderer.render(base: image(), layer: layer))
            XCTAssertGreaterThan(try color(output, x: 20, y: 20).redComponent, 0.9)
            XCTAssertGreaterThan(try color(output, x: 20, y: 80).blueComponent, 0.9)
        }
    }

    func testBackgroundAndResizePreserveAspectRatio() throws {
        var layer = AnnotationLayer()
        layer.presentation = PresentationOptions(background: .white, padding: 10, cornerRadius: 0, shadow: false, outputWidth: 280)
        let output = try XCTUnwrap(CaptureRenderer.render(base: image(), layer: layer))
        XCTAssertEqual(output.size, CGSize(width: 280, height: 240))
        let pixel = try color(output, x: 2, y: 2)
        XCTAssertGreaterThan(pixel.redComponent, 0.9)
        XCTAssertGreaterThan(pixel.greenComponent, 0.9)
    }

    func testShadowFollowsRoundedCornersWithoutWhiteBackingWedges() throws {
        var layer = AnnotationLayer()
        layer.presentation = PresentationOptions(background: .charcoal, padding: 20, cornerRadius: 20, shadow: true)
        let output = try XCTUnwrap(CaptureRenderer.render(base: image(), layer: layer))
        if let path = ProcessInfo.processInfo.environment["PRESSF4_QA_SHADOW_OUTPUT"],
           let tiff = output.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: path))
        }
        let corner = try color(output, x: 20, y: 20)
        XCTAssertLessThan(corner.redComponent, 0.4)
        XCTAssertLessThan(corner.greenComponent, 0.4)
        XCTAssertLessThan(corner.blueComponent, 0.4)
        XCTAssertGreaterThan(try color(output, x: 60, y: 30).redComponent, 0.9)
    }

    func testLegacyLayersDecodeWithoutPresentationFields() throws {
        let old = Data("{\"annotations\":[]}".utf8)
        let layer = try JSONDecoder().decode(AnnotationLayer.self, from: old)
        XCTAssertNil(layer.cropRect)
        XCTAssertNil(layer.presentation)
    }

    func testUndoRestoresCropAndPresentationTogether() throws {
        let original = AnnotationLayer()
        var edited = original
        edited.cropRect = CGRect(x: 10, y: 20, width: 30, height: 40)
        edited.presentation = PresentationOptions(background: .ocean)
        var history = LayerHistory<AnnotationLayer>()
        history.snapshot(original)
        XCTAssertEqual(history.undo(current: edited), original)
        XCTAssertEqual(history.redo(current: original), edited)
        XCTAssertEqual(try JSONDecoder().decode(AnnotationLayer.self, from: JSONEncoder().encode(edited)), edited)
    }

    func testOversizedRenderFailsWithoutAllocatingHugeBitmap() {
        XCTAssertNil(CaptureRenderer.bitmap(size: CGSize(width: 32768, height: 32768)) {})
    }
}

final class EditableCaptureDocumentTests: XCTestCase {
    func testProjectRoundTripPreservesSourceAndNewTools() throws {
        let layer = AnnotationLayer(annotations: [
            Annotation(kind: .counter, rect: CGRect(x: 1, y: 2, width: 36, height: 36), color: .red, text: "3"),
            Annotation(kind: .redact, rect: CGRect(x: 0, y: 0, width: 20, height: 10), color: .black),
            Annotation(kind: .highlight, rect: CGRect(x: 0, y: 20, width: 20, height: 10), color: .yellow)
        ], cropRect: CGRect(x: 1, y: 2, width: 40, height: 50), presentation: PresentationOptions(background: .lavender))
        let project = EditableCaptureDocument(imagePNG: Data([1, 2, 3]), layer: layer)
        let restored = try JSONDecoder().decode(EditableCaptureDocument.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(restored.version, 1)
        XCTAssertEqual(restored.imagePNG, project.imagePNG)
        XCTAssertEqual(restored.layer, layer)
    }
}
