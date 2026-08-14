import ImageIO
import PDFKit
import UIKit

enum StorageRetentionMode: String, Identifiable {
    case previewOnly
    case coverOnly

    var id: String { rawValue }
}

enum StorageOptimizationError: LocalizedError {
    case missingContent
    case noPages
    case unsupportedPreview
    case failedToCreatePreview

    var errorDescription: String? {
        switch self {
        case .missingContent: "找不到这本读物的本地原稿。"
        case .noPages: "这本读物没有可以生成预览的页面。"
        case .unsupportedPreview: "电子书不适合转换为图片预览，可以选择仅保留封面。"
        case .failedToCreatePreview: "生成低清预览时出现问题，原稿没有被删除。"
        }
    }
}

enum StorageOptimizationService {
    static func optimize(
        book: Book,
        libraryURL: URL,
        mode: StorageRetentionMode,
        progress: @Sendable (Double) -> Void = { _ in }
    ) throws -> Book {
        switch mode {
        case .previewOnly:
            return try makePreviewOnly(book: book, libraryURL: libraryURL, progress: progress)
        case .coverOnly:
            progress(0.15)
            let result = try keepCoverOnly(book: book, libraryURL: libraryURL)
            progress(1)
            return result
        }
    }

    private static func makePreviewOnly(
        book: Book,
        libraryURL: URL,
        progress: @Sendable (Double) -> Void
    ) throws -> Book {
        guard book.kind != .ebook else { throw StorageOptimizationError.unsupportedPreview }
        let fileManager = FileManager.default
        let bookFolder = libraryURL.appendingPathComponent(book.folderName, isDirectory: true)
        let staging = bookFolder.appendingPathComponent(".preview-\(UUID().uuidString)", isDirectory: true)
        let final = bookFolder.appendingPathComponent("preview-pages", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        var succeeded = false
        defer { if !succeeded { try? fileManager.removeItem(at: staging) } }

        let pageCount: Int
        switch book.kind {
        case .pdf:
            let source = libraryURL.appendingPathComponent(book.contentRelativePath)
            guard let document = PDFDocument(url: source), !document.isLocked else {
                throw StorageOptimizationError.missingContent
            }
            pageCount = document.pageCount
            guard pageCount > 0 else { throw StorageOptimizationError.noPages }
            for index in 0..<pageCount {
                guard let page = document.page(at: index) else { throw StorageOptimizationError.failedToCreatePreview }
                let thumbnail = page.thumbnail(of: CGSize(width: 1_400, height: 1_400), for: .mediaBox)
                guard let data = thumbnail.jpegData(compressionQuality: 0.72) else {
                    throw StorageOptimizationError.failedToCreatePreview
                }
                try data.write(to: staging.appendingPathComponent(String(format: "%06d.jpg", index + 1)), options: .atomic)
                progress(Double(index + 1) / Double(pageCount) * 0.9)
            }
        case .archive, .imageCollection:
            let sourceFolder = libraryURL.appendingPathComponent(book.contentRelativePath)
            guard fileManager.fileExists(atPath: sourceFolder.path) else { throw StorageOptimizationError.missingContent }
            let pages = NaturalSort.urls((try fileManager.contentsOfDirectory(
                at: sourceFolder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )).filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true })
            guard !pages.isEmpty else { throw StorageOptimizationError.noPages }
            pageCount = pages.count
            for (index, url) in pages.enumerated() {
                guard let data = previewJPEG(from: url, maxPixelSize: 1_400) else {
                    throw StorageOptimizationError.failedToCreatePreview
                }
                try data.write(to: staging.appendingPathComponent(String(format: "%06d.jpg", index + 1)), options: .atomic)
                progress(Double(index + 1) / Double(pageCount) * 0.9)
            }
        case .ebook:
            throw StorageOptimizationError.unsupportedPreview
        }

        let protectedCover = book.coverRelativePath.map { libraryURL.appendingPathComponent($0).standardizedFileURL }
        var removalURLs = [libraryURL.appendingPathComponent(book.contentRelativePath)]
        if let source = book.sourceRelativePath { removalURLs.append(libraryURL.appendingPathComponent(source)) }
        for url in Set(removalURLs.map(\.standardizedFileURL)) where url != protectedCover && url != staging {
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        }
        if fileManager.fileExists(atPath: final.path) { try fileManager.removeItem(at: final) }
        try fileManager.moveItem(at: staging, to: final)
        succeeded = true

        var updated = book
        updated.kind = .imageCollection
        updated.contentRelativePath = "\(book.folderName)/preview-pages"
        updated.sourceRelativePath = nil
        updated.pageCount = pageCount
        updated.currentPage = min(updated.currentPage, max(0, pageCount - 1))
        updated.localStorageState = .previewOnly
        updated.fileSize = folderSize(bookFolder)
        progress(1)
        return updated
    }

    private static func keepCoverOnly(book: Book, libraryURL: URL) throws -> Book {
        let fileManager = FileManager.default
        let bookFolder = libraryURL.appendingPathComponent(book.folderName, isDirectory: true)
        guard fileManager.fileExists(atPath: bookFolder.path) else { throw StorageOptimizationError.missingContent }
        let cover = book.coverRelativePath.map { libraryURL.appendingPathComponent($0).standardizedFileURL }
        for item in try fileManager.contentsOfDirectory(at: bookFolder, includingPropertiesForKeys: nil) {
            if item.standardizedFileURL != cover { try fileManager.removeItem(at: item) }
        }
        var updated = book
        updated.contentRelativePath = "\(book.folderName)/content-removed"
        updated.sourceRelativePath = nil
        updated.previewRelativePaths = book.coverRelativePath.map { [$0] }
        updated.localStorageState = .coverOnly
        updated.fileSize = folderSize(bookFolder)
        return updated
    }

    private static func previewJPEG(from url: URL, maxPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
              ] as CFDictionary)
        else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.72)
    }

    private static func folderSize(_ folder: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys))
        var total: Int64 = 0
        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }
}
