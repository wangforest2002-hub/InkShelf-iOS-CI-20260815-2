import Foundation

struct RemoteLibraryUser: Codable, Hashable, Sendable {
    let username: String
    let displayName: String?
    let role: String

    enum CodingKeys: String, CodingKey {
        case username, role
        case displayName = "display_name"
    }

    var title: String {
        let value = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? username : value
    }

    var isAdmin: Bool { role == "admin" }
}

struct RemoteReadingProgress: Codable, Hashable, Sendable {
    let progress: Double
    let position: Int
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case progress, position
        case updatedAt = "updated_at"
    }
}

struct RemoteBook: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let size: Int64
    let format: String
    let contentType: String?
    let importedAt: String
    let modifiedAt: String
    let downloadPath: String
    let coverPath: String
    let progress: RemoteReadingProgress?

    enum CodingKeys: String, CodingKey {
        case id, name, size, format, progress
        case contentType = "content_type"
        case importedAt = "imported_at"
        case modifiedAt = "modified_at"
        case downloadPath = "download_url"
        case coverPath = "cover_url"
    }

    var title: String {
        let value = (name as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? name : value
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
        case "fb2": "FB2"
        case "epub": "EPUB"
        case "txt": "TXT"
        case "rtf": "RTF"
        case "cbz": "CBZ"
        case "zip": "ZIP"
        case "pdf": "PDF"
        default: format.uppercased()
        }
    }
}

struct RemoteBooksEnvelope: Decodable, Sendable {
    let books: [RemoteBook]
}

struct RemoteLoginEnvelope: Decodable, Sendable {
    let user: RemoteLibraryUser?
}

struct RemoteUploadEnvelope: Decodable, Sendable {
    let book: RemoteBook
}
