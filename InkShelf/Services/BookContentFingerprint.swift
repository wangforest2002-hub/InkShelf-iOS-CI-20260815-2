import CryptoKit
import Foundation

/// Produces a stable identity from the bytes the reader actually consumes.
/// PDFs and ebooks use their source bytes; archives and image collections use
/// the ordered page bytes so a renamed or repacked copy is still recognized.
enum BookContentFingerprint {
    static func fingerprint(for book: Book, libraryURL: URL) throws -> String? {
        switch book.kind {
        case .archive, .imageCollection:
            let pagesURL = libraryURL.appendingPathComponent(book.contentRelativePath)
            return try fingerprint(ofOrderedFilesIn: pagesURL)
        case .pdf, .ebook:
            if let sourceRelativePath = book.sourceRelativePath {
                let sourceURL = libraryURL.appendingPathComponent(sourceRelativePath)
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    return try fingerprint(ofFile: sourceURL)
                }
            }
            if book.kind == .ebook {
                let publicationURL = libraryURL
                    .appendingPathComponent(book.folderName, isDirectory: true)
                    .appendingPathComponent("publication", isDirectory: true)
                if let publicationFingerprint = try fingerprint(ofOrderedFilesIn: publicationURL) {
                    return publicationFingerprint
                }
            }
            let contentURL = libraryURL.appendingPathComponent(book.contentRelativePath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: contentURL.path, isDirectory: &isDirectory) else {
                return nil
            }
            return isDirectory.boolValue
                ? try fingerprint(ofOrderedFilesIn: contentURL)
                : try fingerprint(ofFile: contentURL)
        }
    }

    static func fingerprint(ofFile url: URL) throws -> String {
        var hasher = SHA256()
        try update(&hasher, withFileAt: url)
        return hex(hasher.finalize())
    }

    static func fingerprint(ofOrderedFilesIn folder: URL) throws -> String? {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        let files = NaturalSort.urls(enumerator.compactMap { item in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: keys).isRegularFile) == true
            else { return nil }
            return url
        })
        guard !files.isEmpty else { return nil }

        var hasher = SHA256()
        hasher.update(data: Data("inkshelf-ordered-pages-v1:\(files.count)\n".utf8))
        for url in files {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            hasher.update(data: Data("page:\(size)\n".utf8))
            try update(&hasher, withFileAt: url)
        }
        return hex(hasher.finalize())
    }

    private static func update(_ hasher: inout SHA256, withFileAt url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
