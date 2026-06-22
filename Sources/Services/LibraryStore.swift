import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var captures: [Capture] = []
    @Published var selectedID: UUID?

    private let fileManager = FileManager.default
    private let indexFileName = "index.json"

    private var storageURL: URL {
        let support = try! fileManager.url(for: .applicationSupportDirectory,
                                           in: .userDomainMask,
                                           appropriateFor: nil,
                                           create: true)
        let dir = support.appendingPathComponent("PressF4", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var indexURL: URL { storageURL.appendingPathComponent(indexFileName) }

    init() { load() }

    func imageURL(for capture: Capture) -> URL {
        storageURL.appendingPathComponent(capture.imageFileName)
    }

    func annotationsURL(for capture: Capture) -> URL {
        storageURL.appendingPathComponent(capture.annotationsFileName)
    }

    func loadImage(for capture: Capture) -> NSImage? {
        NSImage(contentsOf: imageURL(for: capture))
    }

    func loadAnnotations(for capture: Capture) -> AnnotationLayer {
        let url = annotationsURL(for: capture)
        guard let data = try? Data(contentsOf: url),
              let layer = try? JSONDecoder().decode(AnnotationLayer.self, from: data) else {
            return AnnotationLayer()
        }
        return layer
    }

    func saveAnnotations(_ layer: AnnotationLayer, for capture: Capture) {
        let url = annotationsURL(for: capture)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(layer) {
            try? data.write(to: url, options: .atomic)
        }
    }

    @discardableResult
    func add(image: CGImage) -> Capture? {
        let id = UUID()
        let imageName = "\(id.uuidString).png"
        let annoName = "\(id.uuidString).json"
        let imgURL = storageURL.appendingPathComponent(imageName)

        guard writePNG(image, to: imgURL) else {
            return nil
        }

        let attrs = try? fileManager.attributesOfItem(atPath: imgURL.path)
        let size = (attrs?[.size] as? Int) ?? 0

        let capture = Capture(
            id: id,
            imageFileName: imageName,
            annotationsFileName: annoName,
            createdAt: Date(),
            width: image.width,
            height: image.height,
            sizeBytes: size
        )
        saveAnnotations(AnnotationLayer(), for: capture)
        captures.insert(capture, at: 0)
        selectedID = capture.id
        persistIndex()
        return capture
    }

    func update(_ capture: Capture) {
        if let idx = captures.firstIndex(where: { $0.id == capture.id }) {
            captures[idx] = capture
            persistIndex()
        }
    }

    func delete(_ capture: Capture) {
        let imgURL = imageURL(for: capture)
        let annoURL = annotationsURL(for: capture)
        try? fileManager.removeItem(at: imgURL)
        try? fileManager.removeItem(at: annoURL)
        captures.removeAll { $0.id == capture.id }
        if selectedID == capture.id { selectedID = captures.first?.id }
        persistIndex()
    }

    func revealInFinder(_ capture: Capture) {
        NSWorkspace.shared.activateFileViewerSelecting([imageURL(for: capture)])
    }

    var selected: Capture? {
        captures.first { $0.id == selectedID }
    }

    var latest: Capture? { captures.first }

    private func writePNG(_ image: CGImage, to url: URL) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("PressF4: failed to write PNG: \(error)")
            return false
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([Capture].self, from: data) else {
            return
        }
        captures = list.sorted { $0.createdAt > $1.createdAt }
        selectedID = captures.first?.id
    }

    private func persistIndex() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(captures) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}
