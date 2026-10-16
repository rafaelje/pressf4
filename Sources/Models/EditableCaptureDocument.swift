import Foundation

/// Portable local project; includes the unredacted original so edits stay reversible.
struct EditableCaptureDocument: Codable {
    var version = 1
    var imagePNG: Data
    var layer: AnnotationLayer
}
