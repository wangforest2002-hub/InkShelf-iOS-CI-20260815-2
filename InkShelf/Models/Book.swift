import Foundation
import UniformTypeIdentifiers

enum BookKind: String, Codable, CaseIterable, Sendable {
    case pdf
    case archive
    case imageCollection

    var label: String {
        switch self {
        case .pdf: "PDF"
        case .archive: "CBZ"
        case .imageCollection: "画集"
        }
    }

    var systemImage: String {
        switch self {
        case .pdf: "doc.richtext.fill"
        case .archive: "books.vertical.fill"
        case .imageCollection: "photo.stack.fill"
        }
    }
}

struct Book: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var kind: BookKind
    var sourceFileName: String
    var contentRelativePath: String
    var sourceRelativePath: String?
    var coverRelativePath: String?
    var previewRelativePaths: [String]?
    var pageCount: Int
    var currentPage: Int
    var importedAt: Date
    var lastOpenedAt: Date?
    var fileSize: Int64
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        title: String,
        kind: BookKind,
        sourceFileName: String,
        contentRelativePath: String,
        sourceRelativePath: String? = nil,
        coverRelativePath: String? = nil,
        previewRelativePaths: [String]? = nil,
        pageCount: Int,
        currentPage: Int = 0,
        importedAt: Date = .now,
        lastOpenedAt: Date? = nil,
        fileSize: Int64,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.sourceFileName = sourceFileName
        self.contentRelativePath = contentRelativePath
        self.sourceRelativePath = sourceRelativePath
        self.coverRelativePath = coverRelativePath
        self.previewRelativePaths = previewRelativePaths
        self.pageCount = pageCount
        self.currentPage = min(max(0, currentPage), max(0, pageCount - 1))
        self.importedAt = importedAt
        self.lastOpenedAt = lastOpenedAt
        self.fileSize = fileSize
        self.isFavorite = isFavorite
    }

    var progress: Double {
        guard pageCount > 1 else { return pageCount == 1 && lastOpenedAt != nil ? 1 : 0 }
        return Double(currentPage) / Double(pageCount - 1)
    }

    var progressLabel: String {
        guard pageCount > 0 else { return "暂无页面" }
        if currentPage == 0, lastOpenedAt == nil { return "未开始 · \(pageCount) 页" }
        if pageCount == 1 { return "已读完 · 1 页" }
        if currentPage >= pageCount - 1 { return "已读完 · \(pageCount) 页" }
        return "第 \(currentPage + 1) / \(pageCount) 页"
    }

    var folderName: String { id.uuidString.lowercased() }
}

extension UTType {
    static let comicBookArchive = UTType(importedAs: "com.inkshelf.cbz", conformingTo: .zip)

    static var inkShelfImportableTypes: [UTType] {
        [.pdf, .comicBookArchive, .zip, .image, .folder]
    }

    static var inkShelfFileTypes: [UTType] {
        [.pdf, .comicBookArchive, .zip, .image]
    }
}
