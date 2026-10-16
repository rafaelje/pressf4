import Foundation
import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

enum LibraryError: Error, LocalizedError {
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .pngEncodingFailed: return "The capture could not be encoded as PNG."
        }
    }
}

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

    func saveAnnotations(_ layer: AnnotationLayer, for capture: Capture) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try encoder.encode(layer).write(to: annotationsURL(for: capture), options: .atomic)
    }

    func add(image: CGImage) throws -> Capture {
        let id = UUID()
        let imageName = "\(id.uuidString).png"
        let annoName = "\(id.uuidString).json"
        let imgURL = storageURL.appendingPathComponent(imageName)

        try writePNG(image, to: imgURL)

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
        let updated = [capture] + captures
        do {
            try saveAnnotations(AnnotationLayer(), for: capture)
            try writeIndex(updated)
        } catch {
            // Leave nothing behind, or load() would resurrect a capture the user was told failed.
            try? fileManager.removeItem(at: imgURL)
            try? fileManager.removeItem(at: annotationsURL(for: capture))
            throw error
        }
        captures = updated
        selectedID = capture.id
        return capture
    }

    func update(_ capture: Capture) throws {
        guard let idx = captures.firstIndex(where: { $0.id == capture.id }) else { return }
        var updated = captures
        updated[idx] = capture
        try writeIndex(updated)
        captures = updated
    }

    func delete(_ capture: Capture) throws {
        let remaining = captures.filter { $0.id != capture.id }
        try writeIndex(remaining)
        do {
            try removeIfPresent(imageURL(for: capture))
        } catch {
            // Keep the capture visible when its image could not be deleted.
            // If restoring the index fails, load() can recover the remaining PNG.
            do {
                try writeIndex(captures)
            } catch {
                NSLog("PressF4: failed to restore index after deletion failure: \(error)")
            }
            throw error
        }
        captures = remaining
        if selectedID == capture.id { selectedID = captures.first?.id }
        do {
            try removeIfPresent(annotationsURL(for: capture))
        } catch {
            NSLog("PressF4: failed to remove annotations for deleted capture: \(error)")
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        do {
            try fileManager.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Already absent is a successful deletion.
        }
    }

    func revealInFinder(_ capture: Capture) {
        NSWorkspace.shared.activateFileViewerSelecting([imageURL(for: capture)])
    }

    var selected: Capture? {
        captures.first { $0.id == selectedID }
    }

    var latest: Capture? { captures.first }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw LibraryError.pngEncodingFailed
        }
        try data.write(to: url, options: .atomic)
    }

    private func load() {
        var list: [Capture] = []
        if fileManager.fileExists(atPath: indexURL.path) {
            do {
                list = try JSONDecoder().decode([Capture].self, from: Data(contentsOf: indexURL))
            } catch {
                NSLog("PressF4: index.json is unreadable, rebuilding it from disk: \(error)")
                backUpUnreadableIndex()
            }
        }

        let recovered = recoverUnindexedCaptures(excluding: Set(list.map(\.imageFileName)))
        captures = (list + recovered).sorted { $0.createdAt > $1.createdAt }
        selectedID = captures.first?.id

        guard !recovered.isEmpty else { return }
        NSLog("PressF4: recovered \(recovered.count) capture(s) missing from index.json")
        do {
            try writeIndex(captures)
        } catch {
            NSLog("PressF4: failed to rewrite index.json: \(error)")
        }
    }

    /// Keeps a copy of an index that failed to decode before the next write replaces it.
    private func backUpUnreadableIndex() {
        let name = "index.unreadable-\(Int(Date().timeIntervalSince1970)).json"
        do {
            try fileManager.copyItem(at: indexURL, to: storageURL.appendingPathComponent(name))
        } catch {
            NSLog("PressF4: failed to back up unreadable index.json: \(error)")
        }
    }

    /// Entries for `<uuid>.png` files in the storage folder that the index doesn't list.
    private func recoverUnindexedCaptures(excluding indexed: Set<String>) -> [Capture] {
        let keys: Set<URLResourceKey> = [.creationDateKey, .fileSizeKey]
        guard let files = try? fileManager.contentsOfDirectory(at: storageURL,
                                                                includingPropertiesForKeys: Array(keys)) else {
            return []
        }
        return files.compactMap { url in
            guard url.pathExtension.lowercased() == "png",
                  !indexed.contains(url.lastPathComponent),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int,
                  let height = props[kCGImagePropertyPixelHeight] as? Int else {
                return nil
            }
            let values = try? url.resourceValues(forKeys: keys)
            return Capture.recovered(imageFileName: url.lastPathComponent,
                                     createdAt: values?.creationDate ?? Date(),
                                     width: width,
                                     height: height,
                                     sizeBytes: values?.fileSize ?? 0)
        }
    }

    private func writeIndex(_ list: [Capture]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try encoder.encode(list).write(to: indexURL, options: .atomic)
    }
}
