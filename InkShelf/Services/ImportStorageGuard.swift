import Foundation
import ZIPFoundation

struct ImportStorageEstimate: Equatable, Sendable {
    let requiredBytes: Int64
    let availableBytes: Int64?
    let safetyReserveBytes: Int64

    var hasEnoughSpace: Bool {
        guard let availableBytes else { return true }
        return availableBytes >= requiredBytes + safetyReserveBytes
    }

    var shortfallBytes: Int64 {
        guard let availableBytes else { return 0 }
        return max(0, requiredBytes + safetyReserveBytes - availableBytes)
    }
}

/// Estimates the peak disk space needed before an import starts. The estimate
/// intentionally includes the short-lived overlap while an archive is copied
/// and expanded, even though its redundant container is removed afterward.
enum ImportStorageGuard {
    static let safetyReserveBytes: Int64 = 512 * 1_024 * 1_024

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tif", "tiff", "bmp", "avif", "dng", "jp2"
    ]
    private static let archiveExtensions: Set<String> = ["cbz", "zip"]
    private static let ebookExtensions = EBookImporter.supportedExtensions

    static func estimate(for urls: [URL], destinationRoot: URL) -> ImportStorageEstimate {
        var required: Int64 = 32 * 1_024 * 1_024
        for url in urls {
            required = addingWithoutOverflow(required, estimatedWriteBytes(for: url))
        }
        return ImportStorageEstimate(
            requiredBytes: required,
            availableBytes: availableCapacity(at: destinationRoot),
            safetyReserveBytes: safetyReserveBytes
        )
    }

    static func ensureSufficientCapacity(for urls: [URL], destinationRoot: URL) throws {
        let estimate = estimate(for: urls, destinationRoot: destinationRoot)
        guard estimate.hasEnoughSpace else {
            throw BookImportError.insufficientStorage(
                requiredBytes: estimate.requiredBytes + estimate.safetyReserveBytes,
                availableBytes: estimate.availableBytes ?? 0
            )
        }
    }

    static func ensureSufficientCapacity(
        additionalBytes: Int64,
        destinationRoot: URL,
        safetyReserve: Int64 = safetyReserveBytes
    ) throws {
        guard let available = availableCapacity(at: destinationRoot),
              available < additionalBytes + safetyReserve
        else { return }
        throw BookImportError.insufficientStorage(
            requiredBytes: additionalBytes + safetyReserve,
            availableBytes: available
        )
    }

    static func availableCapacity(at url: URL) -> Int64? {
        if let value = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage {
            return value
        }
        let path = url.path.isEmpty ? NSHomeDirectory() : url.path
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path)
        return (attributes?[.systemFreeSize] as? NSNumber)?.int64Value
    }

    static func isOutOfSpace(_ error: Error) -> Bool {
        if case BookImportError.insufficientStorage = error { return true }
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == 28 { return true }
        if nsError.domain == NSCocoaErrorDomain
            && nsError.code == CocoaError.Code.fileWriteOutOfSpace.rawValue { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isOutOfSpace(underlying)
        }
        return false
    }

    private static func estimatedWriteBytes(for url: URL) -> Int64 {
        if isDirectory(url) {
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return 0 }
            var total: Int64 = 0
            for case let child as URL in enumerator {
                guard (try? child.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                total = addingWithoutOverflow(total, estimatedFileWriteBytes(for: child))
            }
            return total
        }
        return estimatedFileWriteBytes(for: url)
    }

    private static func estimatedFileWriteBytes(for url: URL) -> Int64 {
        let ext = url.pathExtension.lowercased()
        let sourceBytes = allocatedOrLogicalSize(of: url)
        if archiveExtensions.contains(ext) {
            return addingWithoutOverflow(sourceBytes, estimatedArchiveExpansion(of: url, fallbackSourceBytes: sourceBytes))
        }
        if ext == "epub" {
            return addingWithoutOverflow(sourceBytes, estimatedArchiveExpansion(of: url, fallbackSourceBytes: sourceBytes))
        }
        if imageExtensions.contains(ext) || ext == "pdf" {
            return sourceBytes
        }
        if ebookExtensions.contains(ext) {
            return max(sourceBytes, multipliedWithoutOverflow(sourceBytes, by: 2))
        }
        return 0
    }

    private static func estimatedArchiveExpansion(of url: URL, fallbackSourceBytes: Int64) -> Int64 {
        guard let archive = try? Archive(url: url, accessMode: .read) else {
            return multipliedWithoutOverflow(max(fallbackSourceBytes, 1), by: 4)
        }
        var total: Int64 = 0
        for entry in archive where entry.type == .file {
            total = addingWithoutOverflow(total, Int64(clamping: entry.uncompressedSize))
        }
        return max(total, fallbackSourceBytes)
    }

    private static func allocatedOrLogicalSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .totalFileSizeKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.totalFileSize ?? values.fileSize ?? 0)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        if url.hasDirectoryPath { return true }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static func addingWithoutOverflow(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : value
    }

    private static func multipliedWithoutOverflow(_ value: Int64, by multiplier: Int64) -> Int64 {
        let (result, overflow) = value.multipliedReportingOverflow(by: multiplier)
        return overflow ? Int64.max : result
    }
}
