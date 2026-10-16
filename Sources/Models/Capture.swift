import Foundation
import AppKit

struct Capture: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var imageFileName: String
    var annotationsFileName: String
    var createdAt: Date
    var width: Int
    var height: Int
    var sizeBytes: Int

    init(id: UUID = UUID(),
         imageFileName: String,
         annotationsFileName: String,
         createdAt: Date = Date(),
         width: Int,
         height: Int,
         sizeBytes: Int) {
        self.id = id
        self.imageFileName = imageFileName
        self.annotationsFileName = annotationsFileName
        self.createdAt = createdAt
        self.width = width
        self.height = height
        self.sizeBytes = sizeBytes
    }

    /// Rebuilds the entry for a `<uuid>.png` left in the storage folder without an
    /// index entry, following the naming `LibraryStore.add` uses. Returns nil for
    /// any other file name.
    static func recovered(imageFileName: String,
                          createdAt: Date,
                          width: Int,
                          height: Int,
                          sizeBytes: Int) -> Capture? {
        let name = imageFileName as NSString
        let stem = name.deletingPathExtension
        guard name.pathExtension.lowercased() == "png",
              let id = UUID(uuidString: stem) else { return nil }
        return Capture(id: id,
                       imageFileName: imageFileName,
                       annotationsFileName: "\(stem).json",
                       createdAt: createdAt,
                       width: width,
                       height: height,
                       sizeBytes: sizeBytes)
    }

    var displayTime: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(createdAt) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: createdAt) + " · today"
        } else if calendar.isDateInYesterday(createdAt) {
            formatter.dateFormat = "HH:mm"
            return "yesterday · " + formatter.string(from: createdAt)
        } else {
            formatter.dateFormat = "d MMM HH:mm"
            return formatter.string(from: createdAt)
        }
    }

    var displaySize: String {
        let kb = Double(sizeBytes) / 1024.0
        if kb > 1024 {
            return String(format: "%.1f MB", kb / 1024.0)
        }
        return String(format: "%.0f KB", kb)
    }

    var displayDims: String { "\(width)×\(height)" }
}
