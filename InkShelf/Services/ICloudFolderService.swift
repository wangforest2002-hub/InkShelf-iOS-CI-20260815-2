import Foundation

enum ICloudFolderError: LocalizedError, Sendable {
    case bookmarkFailed
    case folderUnavailable
    case fileUnavailable
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .bookmarkFailed: return "无法保存这个 iCloud 文件夹的访问权限。"
        case .folderUnavailable: return "iCloud 文件夹暂时不可用，请在“文件”App 中确认它仍然存在。"
        case .fileUnavailable: return "这本书已从 iCloud 移动或删除。"
        case .downloadFailed: return "无法从 iCloud 下载这本书，请检查网络和 iCloud 空间。"
        }
    }
}

enum ICloudFolderService {
    static let supportedExtensions: Set<String> = [
        "pdf", "cbz", "zip", "jpg", "jpeg", "png", "heic", "heif", "webp", "gif",
        "tif", "tiff", "bmp", "avif", "epub", "txt", "html", "htm", "md", "markdown",
        "rtf", "fb2",
    ]

    static func bookmark(for folderURL: URL) throws -> Data {
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }
        do {
            return try folderURL.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: [.nameKey, .isDirectoryKey],
                relativeTo: nil
            )
        } catch {
            throw ICloudFolderError.bookmarkFailed
        }
    }

    static func resolve(_ link: ICloudFolderLink) throws -> (url: URL, stale: Bool) {
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: link.bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            return (url, stale)
        } catch {
            throw ICloudFolderError.folderUnavailable
        }
    }

    static func scan(link: ICloudFolderLink, rootURL: URL) throws -> [ICloudBook] {
        let accessed = rootURL.startAccessingSecurityScopedResource()
        defer { if accessed { rootURL.stopAccessingSecurityScopedResource() } }

        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .contentModificationDateKey,
            .nameKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { throw ICloudFolderError.folderUnavailable }

        let rootPath = rootURL.standardizedFileURL.path
        var books: [ICloudBook] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile != false else { continue }

            let standardizedPath = fileURL.standardizedFileURL.path
            let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            guard standardizedPath.hasPrefix(prefix) else { continue }
            let relativePath = String(standardizedPath.dropFirst(prefix.count))
            let components = relativePath.split(separator: "/").map(String.init)
            let collection = components.count > 1 ? components[0] : link.name
            let size = Int64(values?.fileSize ?? values?.fileAllocatedSize ?? 0)

            books.append(ICloudBook(
                id: ICloudBook.stableID(folderID: link.id, relativePath: relativePath),
                folderID: link.id,
                relativePath: relativePath,
                name: values?.name ?? fileURL.lastPathComponent,
                collection: collection,
                size: size,
                modifiedAt: values?.contentModificationDate,
                format: ext
            ))
        }
        return books.sorted {
            let collectionOrder = $0.collection.localizedStandardCompare($1.collection)
            if collectionOrder != .orderedSame { return collectionOrder == .orderedAscending }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func materialize(
        book: ICloudBook,
        rootURL: URL,
        destination: URL,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let accessed = rootURL.startAccessingSecurityScopedResource()
            defer { if accessed { rootURL.stopAccessingSecurityScopedResource() } }

            let sourceURL = rootURL.appendingPathComponent(book.relativePath)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw ICloudFolderError.fileUnavailable
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: destination)

            let ubiquitous = (try? sourceURL.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) ?? false
            if ubiquitous {
                try? FileManager.default.startDownloadingUbiquitousItem(at: sourceURL)
                for _ in 0..<7_200 {
                    try Task.checkCancellation()
                    let values = try? sourceURL.resourceValues(forKeys: [
                        .ubiquitousItemDownloadingStatusKey,
                        .ubiquitousItemPercentDownloadedKey,
                    ])
                    let percentNumber = values?.allValues[.ubiquitousItemPercentDownloadedKey] as? NSNumber
                    let percent = min(max((percentNumber?.doubleValue ?? 0) / 100, 0), 1)
                    await progress(percent * 0.88)
                    if values?.ubiquitousItemDownloadingStatus == .current ||
                        values?.ubiquitousItemDownloadingStatus == .downloaded {
                        break
                    }
                    try await Task.sleep(for: .milliseconds(250))
                }
            }

            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var copyError: Error?
            coordinator.coordinate(
                readingItemAt: sourceURL,
                options: .withoutChanges,
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    try streamCopy(
                        from: coordinatedURL,
                        to: destination,
                        expectedSize: max(book.size, 1),
                        baseProgress: ubiquitous ? 0.88 : 0,
                        progress: progress
                    )
                } catch {
                    copyError = error
                }
            }
            if let copyError { throw copyError }
            if let coordinationError { throw coordinationError }
            guard FileManager.default.fileExists(atPath: destination.path) else {
                throw ICloudFolderError.downloadFailed
            }
            await progress(1)
            return destination
        }.value
    }

    private static func streamCopy(
        from source: URL,
        to destination: URL,
        expectedSize: Int64,
        baseProgress: Double,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }

        var copied: Int64 = 0
        while let data = try input.read(upToCount: 1_024 * 1_024), !data.isEmpty {
            try Task.checkCancellation()
            try output.write(contentsOf: data)
            copied += Int64(data.count)
            let fraction = min(max(Double(copied) / Double(expectedSize), 0), 1)
            let value = baseProgress + fraction * (1 - baseProgress)
            Task { @MainActor in progress(value) }
        }
        try output.synchronize()
    }
}
