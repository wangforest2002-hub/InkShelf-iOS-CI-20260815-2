import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import ZIPFoundation

enum BookImportError: LocalizedError, Sendable {
    case unsupportedFile(String)
    case accessDenied(String)
    case unreadablePDF(String)
    case emptyArchive(String)
    case archiveTooLarge
    case insufficientStorage(requiredBytes: Int64, availableBytes: Int64)
    case noImages

    var errorDescription: String? {
        switch self {
        case .unsupportedFile(let name): return "暂不支持“\(name)”的文件格式。"
        case .accessDenied(let name): return "无法取得“\(name)”的读取权限。请在系统“文件”中确认它已下载完成，然后重新选择。"
        case .unreadablePDF(let name): return "无法读取 PDF“\(name)”。文件可能已损坏。"
        case .emptyArchive(let name): return "压缩包“\(name)”中没有可读取的图片。"
        case .archiveTooLarge: return "压缩包展开后过大或页面过多，已停止导入以保护设备存储空间。"
        case .insufficientStorage(let requiredBytes, let availableBytes):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let required = formatter.string(fromByteCount: requiredBytes)
            let available = formatter.string(fromByteCount: availableBytes)
            return "本机空间不足：这次导入预计至少需要 \(required)，当前约可用 \(available)。请先在“本地存储管家”中整理空间后再试。"
        case .noImages: return "没有选择可读取的图片。"
        }
    }
}

enum BookImporter {
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tif", "tiff", "bmp", "avif", "dng", "jp2"
    ]
    private static let maxArchiveEntries = 20_000
    private static let maxExpandedArchiveBytes: UInt64 = 8 * 1_024 * 1_024 * 1_024
    private static var documentExtensions: Set<String> {
        var extensions: Set<String> = ["pdf", "cbz", "zip"]
        extensions.formUnion(EBookImporter.supportedExtensions)
        return extensions
    }

    static func importBooks(from urls: [URL], into libraryURL: URL) async throws -> [Book] {
        try await Task.detached(priority: .userInitiated) {
            try importSynchronously(from: urls, into: libraryURL)
        }.value
    }

    private static func importSynchronously(from urls: [URL], into libraryURL: URL) throws -> [Book] {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: libraryURL, withIntermediateDirectories: true)

        try ImportStorageGuard.ensureSufficientCapacity(for: urls, destinationRoot: libraryURL)

        let sortedURLs = NaturalSort.urls(urls)
        let folderURLs = sortedURLs.filter { isDirectory($0) }
        let fileURLs = sortedURLs.filter { !isDirectory($0) }
        let imageURLs = fileURLs.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
        let documentURLs = fileURLs.filter { !imageExtensions.contains($0.pathExtension.lowercased()) }
        var createdFolders: [URL] = []
        var imported: [Book] = []

        do {
            for folderURL in folderURLs {
                let results = try withSecurityScopedAccess(to: folderURL) {
                    try importFolder(folderURL, into: libraryURL)
                }
                imported.append(contentsOf: results.map(\.0))
                createdFolders.append(contentsOf: results.map(\.1))
            }

            for url in documentURLs {
                let result = try withSecurityScopedAccess(to: url) {
                    try importDocument(url, into: libraryURL)
                }
                imported.append(result.0)
                createdFolders.append(result.1)
            }

            if !imageURLs.isEmpty {
                let result = try importImageCollection(imageURLs, into: libraryURL)
                imported.append(result.0)
                createdFolders.append(result.1)
            }

            guard !imported.isEmpty else { throw BookImportError.noImages }
            for index in imported.indices {
                imported[index].contentFingerprint = try? BookContentFingerprint.fingerprint(
                    for: imported[index],
                    libraryURL: libraryURL
                )
            }
            return imported
        } catch {
            for folder in createdFolders {
                try? fileManager.removeItem(at: folder)
            }
            if let importError = error as? BookImportError,
               case .insufficientStorage = importError {
                throw importError
            }
            if ImportStorageGuard.isOutOfSpace(error) {
                throw BookImportError.insufficientStorage(
                    requiredBytes: ImportStorageGuard.safetyReserveBytes,
                    availableBytes: ImportStorageGuard.availableCapacity(at: libraryURL) ?? 0
                )
            }
            throw error
        }
    }

    private static func importDocument(_ url: URL, into libraryURL: URL) throws -> (Book, URL) {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return try importPDF(url, into: libraryURL)
        case "cbz", "zip":
            return try importArchive(url, into: libraryURL)
        default:
            if EBookImporter.supportedExtensions.contains(ext) {
                return try EBookImporter.importBook(url, into: libraryURL)
            }
            throw BookImportError.unsupportedFile(url.lastPathComponent)
        }
    }

    private static func importPDF(_ sourceURL: URL, into libraryURL: URL) throws -> (Book, URL) {
        let fileManager = FileManager.default
        let id = UUID()
        let folder = libraryURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        do {
            let destination = folder.appendingPathComponent("source.pdf")
            try ExternalFileAccess.copyItem(from: sourceURL, to: destination)
            guard let document = PDFDocument(url: destination) else {
                throw BookImportError.unreadablePDF(sourceURL.lastPathComponent)
            }

            let coverName = CoverService.createPDFCover(document: document, in: folder)
            let coverPath = coverName.map { relativePath(id: id, component: $0) }
            let coverAspectRatio = coverName.flatMap {
                CoverService.aspectRatio(at: folder.appendingPathComponent($0))
            }
            let pageCount = max(document.pageCount, 1)
            let book = Book(
                id: id,
                title: cleanTitle(sourceURL.deletingPathExtension().lastPathComponent),
                kind: .pdf,
                sourceFileName: sourceURL.lastPathComponent,
                contentRelativePath: relativePath(id: id, component: "source.pdf"),
                sourceRelativePath: relativePath(id: id, component: "source.pdf"),
                coverRelativePath: coverPath,
                coverAspectRatio: coverAspectRatio,
                previewRelativePaths: coverPath.map { [$0] },
                pageCount: pageCount,
                fileSize: fileSize(of: destination)
            )
            return (book, folder)
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
    }

    private static func importArchive(_ sourceURL: URL, into libraryURL: URL) throws -> (Book, URL) {
        let fileManager = FileManager.default
        let id = UUID()
        let folder = libraryURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        let pagesFolder = folder.appendingPathComponent("pages", isDirectory: true)
        try fileManager.createDirectory(at: pagesFolder, withIntermediateDirectories: true)

        do {
            let sourceExtension = sourceURL.pathExtension.lowercased() == "cbz" ? "cbz" : "zip"
            let copiedArchive = folder.appendingPathComponent("source.\(sourceExtension)")
            try ExternalFileAccess.copyItem(from: sourceURL, to: copiedArchive)

            let archive = try Archive(url: copiedArchive, accessMode: .read)
            let entries = archive.filter { entry in
                guard entry.type == .file else { return false }
                guard !entry.path.contains("__MACOSX") else { return false }
                return imageExtensions.contains((entry.path as NSString).pathExtension.lowercased())
            }.sorted {
                $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }

            guard !entries.isEmpty else { throw BookImportError.emptyArchive(sourceURL.lastPathComponent) }
            guard entries.count <= maxArchiveEntries else { throw BookImportError.archiveTooLarge }

            let expectedExpandedBytes = entries.reduce(into: UInt64(0)) { total, entry in
                let (value, overflow) = total.addingReportingOverflow(UInt64(entry.uncompressedSize))
                total = overflow ? UInt64.max : value
            }
            guard expectedExpandedBytes <= maxExpandedArchiveBytes else { throw BookImportError.archiveTooLarge }
            try ImportStorageGuard.ensureSufficientCapacity(
                additionalBytes: Int64(clamping: expectedExpandedBytes),
                destinationRoot: libraryURL
            )

            var expandedBytes: UInt64 = 0
            var pageURLs: [URL] = []
            for (index, entry) in entries.enumerated() {
                expandedBytes += UInt64(entry.uncompressedSize)
                guard expandedBytes <= maxExpandedArchiveBytes else { throw BookImportError.archiveTooLarge }

                let ext = (entry.path as NSString).pathExtension.lowercased()
                let pageName = String(format: "%06d.%@", index + 1, ext)
                let pageURL = pagesFolder.appendingPathComponent(pageName)
                try archive.extract(entry, to: pageURL)
                if isReadableImage(pageURL) {
                    pageURLs.append(pageURL)
                } else {
                    try? fileManager.removeItem(at: pageURL)
                }
            }

            guard !pageURLs.isEmpty else { throw BookImportError.emptyArchive(sourceURL.lastPathComponent) }

            let previewNames = CoverService.createImagePreviews(sourceURLs: Array(pageURLs.prefix(1)), in: folder)
            let previewPaths = previewNames.map { relativePath(id: id, component: $0) }
            let coverAspectRatio = previewNames.first.flatMap {
                CoverService.aspectRatio(at: folder.appendingPathComponent($0))
            }
            // The extracted pages are already the complete, original-quality
            // reading source. Keeping the archive beside them nearly doubles
            // local usage without improving image quality.
            try fileManager.removeItem(at: copiedArchive)
            let book = Book(
                id: id,
                title: cleanTitle(sourceURL.deletingPathExtension().lastPathComponent),
                kind: .archive,
                sourceFileName: sourceURL.lastPathComponent,
                contentRelativePath: relativePath(id: id, component: "pages"),
                sourceRelativePath: nil,
                coverRelativePath: previewPaths.first,
                coverAspectRatio: coverAspectRatio,
                previewRelativePaths: previewPaths,
                pageCount: pageURLs.count,
                fileSize: folderSize(of: folder)
            )
            return (book, folder)
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
    }

    private static func importImageCollection(
        _ sourceURLs: [URL],
        titleOverride: String? = nil,
        sourceLabel: String? = nil,
        into libraryURL: URL
    ) throws -> (Book, URL) {
        guard !sourceURLs.isEmpty else { throw BookImportError.noImages }
        let fileManager = FileManager.default
        let id = UUID()
        let folder = libraryURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        let pagesFolder = folder.appendingPathComponent("pages", isDirectory: true)
        try fileManager.createDirectory(at: pagesFolder, withIntermediateDirectories: true)

        do {
            var copiedURLs: [URL] = []
            var totalSize: Int64 = 0
            for (index, sourceURL) in NaturalSort.urls(sourceURLs).enumerated() {
                try withSecurityScopedAccess(to: sourceURL) {
                    let ext = sourceURL.pathExtension.lowercased()
                    let destination = pagesFolder.appendingPathComponent(String(format: "%06d.%@", index + 1, ext))
                    try ExternalFileAccess.copyItem(from: sourceURL, to: destination)
                    guard isReadableImage(destination) else {
                        throw BookImportError.unsupportedFile(sourceURL.lastPathComponent)
                    }
                    copiedURLs.append(destination)
                    totalSize += fileSize(of: destination)
                    guard totalSize <= Int64(maxExpandedArchiveBytes) else {
                        throw BookImportError.archiveTooLarge
                    }
                }
            }

            let parentNames = Set(sourceURLs.map { $0.deletingLastPathComponent().lastPathComponent })
            let title: String
            if let titleOverride, !titleOverride.isEmpty {
                title = cleanTitle(titleOverride)
            } else if sourceURLs.count == 1 {
                title = cleanTitle(sourceURLs[0].deletingPathExtension().lastPathComponent)
            } else if parentNames.count == 1, let parent = parentNames.first, !parent.isEmpty {
                title = cleanTitle(parent)
            } else {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "zh_Hans_CN")
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                title = "画集 \(formatter.string(from: .now))"
            }

            let previewNames = CoverService.createImagePreviews(sourceURLs: Array(copiedURLs.prefix(1)), in: folder)
            let previewPaths = previewNames.map { relativePath(id: id, component: $0) }
            let coverAspectRatio = previewNames.first.flatMap {
                CoverService.aspectRatio(at: folder.appendingPathComponent($0))
            }
            let book = Book(
                id: id,
                title: title,
                kind: .imageCollection,
                sourceFileName: sourceLabel ?? (sourceURLs.count == 1 ? sourceURLs[0].lastPathComponent : "\(sourceURLs.count) 张图片"),
                contentRelativePath: relativePath(id: id, component: "pages"),
                coverRelativePath: previewPaths.first,
                coverAspectRatio: coverAspectRatio,
                previewRelativePaths: previewPaths,
                pageCount: copiedURLs.count,
                fileSize: totalSize
            )
            return (book, folder)
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
    }

    private static func importFolder(_ sourceFolder: URL, into libraryURL: URL) throws -> [(Book, URL)] {
        // Keep file-provider coordination limited to enumeration. Copying a
        // child while the parent coordination is open can deadlock iCloud.
        let inventory = try ExternalFileAccess.coordinateReading(at: sourceFolder) { coordinatedFolder in
            try collectFolderInventory(in: coordinatedFolder)
        }
        let imageCount = inventory.imageRelativePathsByParent.values.reduce(0) { $0 + $1.count }
        guard inventory.documentRelativePaths.count + imageCount <= maxArchiveEntries else {
            throw BookImportError.archiveTooLarge
        }

        var results: [(Book, URL)] = []
        var firstError: Error?

        for relativePath in inventory.documentRelativePaths {
            let sourceURL = sourceFolder.appendingPathComponent(relativePath)
            do {
                results.append(try importDocument(sourceURL, into: libraryURL))
            } catch {
                if ImportStorageGuard.isOutOfSpace(error) { throw error }
                if firstError == nil { firstError = error }
            }
        }

        if inventory.documentRelativePaths.isEmpty {
            let allImages = inventory.imageRelativePathsByParent.values
                .flatMap { $0 }
                .map { sourceFolder.appendingPathComponent($0) }
            if !allImages.isEmpty {
                do {
                    results.append(try importImageCollection(
                        allImages,
                        titleOverride: sourceFolder.lastPathComponent,
                        sourceLabel: "文件夹 · \(allImages.count) 张图片",
                        into: libraryURL
                    ))
                } catch {
                    if ImportStorageGuard.isOutOfSpace(error) { throw error }
                    if firstError == nil { firstError = error }
                }
            }
        } else {
            for parent in inventory.imageRelativePathsByParent.keys.sorted(by: {
                $0.localizedStandardCompare($1) == .orderedAscending
            }) {
                let relativePaths = inventory.imageRelativePathsByParent[parent] ?? []
                let imageURLs = relativePaths.map { sourceFolder.appendingPathComponent($0) }
                guard !imageURLs.isEmpty else { continue }
                let folderName = parent.isEmpty
                    ? sourceFolder.lastPathComponent
                    : (parent as NSString).lastPathComponent
                do {
                    results.append(try importImageCollection(
                        imageURLs,
                        titleOverride: folderName,
                        sourceLabel: "文件夹 · \(imageURLs.count) 张图片",
                        into: libraryURL
                    ))
                } catch {
                    if ImportStorageGuard.isOutOfSpace(error) { throw error }
                    if firstError == nil { firstError = error }
                }
            }
        }

        if results.isEmpty { throw firstError ?? BookImportError.noImages }
        return results
    }

    private struct FolderInventory {
        var documentRelativePaths: [String] = []
        var imageRelativePathsByParent: [String: [String]] = [:]
    }

    private static func collectFolderInventory(in sourceFolder: URL) throws -> FolderInventory {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
        guard let enumerator = fileManager.enumerator(
            at: sourceFolder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw BookImportError.noImages
        }

        let basePath = sourceFolder.standardizedFileURL.path
        let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
        var inventory = FolderInventory()
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true, values?.isHidden != true else { continue }
            let standardizedPath = url.standardizedFileURL.path
            guard standardizedPath.hasPrefix(prefix) else { continue }
            let relativePath = String(standardizedPath.dropFirst(prefix.count))
            let ext = url.pathExtension.lowercased()
            if imageExtensions.contains(ext) {
                let parent = (relativePath as NSString).deletingLastPathComponent
                inventory.imageRelativePathsByParent[parent, default: []].append(relativePath)
            } else if documentExtensions.contains(ext) {
                inventory.documentRelativePaths.append(relativePath)
            }
        }

        inventory.documentRelativePaths.sort {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        for parent in inventory.imageRelativePathsByParent.keys {
            inventory.imageRelativePathsByParent[parent]?.sort {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
        }
        return inventory
    }

    private static func withSecurityScopedAccess<T>(to url: URL, operation: () throws -> T) rethrows -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        return try operation()
    }

    private static func relativePath(id: UUID, component: String) -> String {
        "\(id.uuidString.lowercased())/\(component)"
    }

    private static func cleanTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名读物" : trimmed
    }

    private static func fileSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private static func folderSize(of folder: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    private static func isDirectory(_ url: URL) -> Bool {
        if url.hasDirectoryPath { return true }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static func isReadableImage(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }
}
