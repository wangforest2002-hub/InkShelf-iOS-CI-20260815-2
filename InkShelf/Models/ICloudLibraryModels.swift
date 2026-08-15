import CryptoKit
import Foundation

struct ICloudFolderLink: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var bookmark: Data
    let linkedAt: Date
}

struct ICloudBook: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let folderID: UUID
    let relativePath: String
    let name: String
    let collection: String
    let size: Int64
    let modifiedAt: Date?
    let format: String

    var title: String {
        let value = (name as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? name : value
    }

    var sourceID: String { "icloud:\(id)" }

    var revision: String {
        let timestamp = Int64((modifiedAt ?? .distantPast).timeIntervalSince1970)
        return "\(size)-\(timestamp)"
    }

    var kind: BookKind {
        switch format.lowercased() {
        case "pdf": .pdf
        case "cbz", "zip": .archive
        case "jpg", "jpeg", "png", "webp", "gif", "tif", "tiff", "bmp", "heic", "avif": .imageCollection
        default: .ebook
        }
    }

    var formatLabel: String {
        switch format.lowercased() {
        case "md", "markdown": "Markdown"
        case "htm", "html": "HTML"
        default: format.uppercased()
        }
    }

    static func stableID(folderID: UUID, relativePath: String) -> String {
        let value = "\(folderID.uuidString.lowercased())|\(relativePath.precomposedStringWithCanonicalMapping.lowercased())"
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

enum CloudLibraryMode: String, CaseIterable, Identifiable {
    case iCloud
    case server

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iCloud: "iCloud"
        case .server: "服务器"
        }
    }
}
