import Foundation
import UniformTypeIdentifiers

enum BookKind: String, Codable, CaseIterable, Sendable {
    case pdf
    case archive
    case imageCollection
    case ebook

    var label: String {
        switch self {
        case .pdf: "PDF"
        case .archive: "CBZ"
        case .imageCollection: "画集"
        case .ebook: "电子书"
        }
    }

    var systemImage: String {
        switch self {
        case .pdf: "doc.richtext.fill"
        case .archive: "books.vertical.fill"
        case .imageCollection: "photo.stack.fill"
        case .ebook: "text.book.closed.fill"
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
    var favoritePages: [Int]?
    var ebookChapterProgress: Double?
    var remoteSourceID: String?
    var remoteModifiedAt: String?

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
        isFavorite: Bool = false,
        favoritePages: [Int]? = nil,
        ebookChapterProgress: Double? = nil,
        remoteSourceID: String? = nil,
        remoteModifiedAt: String? = nil
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
        self.favoritePages = favoritePages
        self.ebookChapterProgress = ebookChapterProgress
        self.remoteSourceID = remoteSourceID
        self.remoteModifiedAt = remoteModifiedAt
    }

    var progress: Double {
        if kind == .ebook, pageCount > 0 {
            let chapterProgress = min(max(ebookChapterProgress ?? 0, 0), 1)
            return min(max((Double(currentPage) + chapterProgress) / Double(pageCount), 0), 1)
        }
        guard pageCount > 1 else { return pageCount == 1 && lastOpenedAt != nil ? 1 : 0 }
        return Double(currentPage) / Double(pageCount - 1)
    }

    var progressLabel: String {
        guard pageCount > 0 else { return "暂无页面" }
        if kind == .ebook {
            let percentage = Int((progress * 100).rounded())
            if currentPage == 0, lastOpenedAt == nil { return "未开始 · \(pageCount) 章" }
            if progress >= 0.999 { return "已读完 · \(pageCount) 章" }
            return "第 \(currentPage + 1) / \(pageCount) 章 · \(percentage)%"
        }
        if currentPage == 0, lastOpenedAt == nil { return "未开始 · \(pageCount) 页" }
        if pageCount == 1 { return "已读完 · 1 页" }
        if currentPage >= pageCount - 1 { return "已读完 · \(pageCount) 页" }
        return "第 \(currentPage + 1) / \(pageCount) 页"
    }

    var folderName: String { id.uuidString.lowercased() }
}

extension UTType {
    static let comicBookArchive = UTType(importedAs: "com.inkshelf.cbz", conformingTo: .zip)
    static let epubBook = UTType(importedAs: "org.idpf.epub-container", conformingTo: .zip)
    static let fictionBook = UTType(importedAs: "org.fictionbook.fb2", conformingTo: .xml)
    static let markdownDocument = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)

    static var inkShelfImportableTypes: [UTType] {
        inkShelfFileTypes
    }

    static var inkShelfFileTypes: [UTType] {
        // `.data` is an intentional fallback. Some third-party File Providers
        // expose CBZ/EPUB files only as generic data even when their filename
        // extension is correct; the importer still validates the extension.
        [.pdf, .epubBook, .comicBookArchive, .zip, .image, .plainText, .html, .rtf, .markdownDocument, .fictionBook, .data]
    }
}
