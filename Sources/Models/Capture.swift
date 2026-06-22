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

    var displayTime: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(createdAt) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: createdAt) + " · hoy"
        } else if calendar.isDateInYesterday(createdAt) {
            formatter.dateFormat = "HH:mm"
            return "ayer · " + formatter.string(from: createdAt)
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
