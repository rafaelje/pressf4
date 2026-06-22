#if SMOKE_TEST
import Foundation
import AppKit

// Minimal assertion helper.
private func check(_ cond: @autoclosure () -> Bool, _ msg: String,
                   file: StaticString = #file, line: UInt = #line) {
    if !cond() {
        FileHandle.standardError.write(Data("FAIL \(file):\(line)  \(msg)\n".utf8))
        exit(1)
    }
    print("  ok — \(msg)")
}

@main
struct SmokeTestMain {
    static func main() {
        print("PressF4 smoke tests")
        print("======================")

        testCaptureCodable()
        testAnnotationCodable()
        testAnnotationColors()
        testCaptureDisplay()
        testRectClamping()

        print("\nAll smoke tests passed ✅")
    }

    static func testCaptureCodable() {
        print("\n[1] Capture round-trip")
        let c = Capture(imageFileName: "x.png",
                        annotationsFileName: "x.json",
                        width: 800, height: 600, sizeBytes: 1234)
        let data = try! JSONEncoder().encode(c)
        let back = try! JSONDecoder().decode(Capture.self, from: data)
        check(back.id == c.id, "id preserved")
        check(back.width == 800, "width preserved")
        check(back.sizeBytes == 1234, "size preserved")
    }

    static func testAnnotationCodable() {
        print("\n[2] AnnotationLayer round-trip")
        let layer = AnnotationLayer(annotations: [
            Annotation(kind: .rectangle,
                       rect: CGRect(x: 10, y: 20, width: 100, height: 50),
                       color: .red, stroke: 3),
            Annotation(kind: .circle,
                       rect: CGRect(x: 200, y: 50, width: 80, height: 80),
                       color: .blue, stroke: 4),
            Annotation(kind: .text,
                       rect: CGRect(x: 0, y: 0, width: 100, height: 20),
                       color: .black, stroke: 1, text: "Hola")
        ])
        let data = try! JSONEncoder().encode(layer)
        let back = try! JSONDecoder().decode(AnnotationLayer.self, from: data)
        check(back.annotations.count == 3, "3 annotations preserved")
        check(back.annotations[0].kind == .rectangle, "kind preserved")
        check(back.annotations[2].text == "Hola", "text preserved")
        check(back.annotations[0].rect.width == 100, "rect dims preserved")
    }

    static func testAnnotationColors() {
        print("\n[3] AnnotationColor palette")
        check(AnnotationColor.palette.count == 6, "6 palette colors")
        let red = AnnotationColor.red
        check(red.r > 0.9 && red.g < 0.3, "red rgb correct")
        let encoded = try! JSONEncoder().encode(red)
        let back = try! JSONDecoder().decode(AnnotationColor.self, from: encoded)
        check(abs(back.r - red.r) < 0.001, "color round-trip stable")
    }

    static func testCaptureDisplay() {
        print("\n[4] Capture display formatting")
        let c = Capture(imageFileName: "x.png",
                        annotationsFileName: "x.json",
                        createdAt: Date(),
                        width: 1920, height: 1080, sizeBytes: 524_288)
        check(c.displayDims == "1920×1080", "dims format")
        check(c.displaySize.contains("KB") || c.displaySize.contains("MB"),
              "size format contains unit")
    }

    static func testRectClamping() {
        print("\n[5] CGRect math used by CaptureService")
        let image = CGRect(x: 0, y: 0, width: 2000, height: 1200)
        let crop = CGRect(x: -50, y: 100, width: 600, height: 400)
        let clamped = CGRect(
            x: max(0, min(crop.origin.x, image.maxX - 1)),
            y: max(0, min(crop.origin.y, image.maxY - 1)),
            width: min(crop.width, image.width - max(0, crop.origin.x)),
            height: min(crop.height, image.height - max(0, crop.origin.y))
        )
        check(clamped.origin.x == 0, "negative x clamped to 0")
        check(clamped.origin.y == 100, "valid y kept")
        check(clamped.maxX <= image.maxX, "doesn't exceed image bounds")
    }
}
#endif
