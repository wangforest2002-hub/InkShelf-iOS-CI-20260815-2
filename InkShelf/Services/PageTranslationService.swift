import CryptoKit
import Foundation
import ImageIO
import PDFKit
import UIKit
import Vision

struct PreparedTranslationPage: @unchecked Sendable {
    let image: UIImage
    let key: String
}

/// Separate from the companion: no face detection, classification or page summaries.
actor PageTranslationService {
    static let shared = PageTranslationService()
    private var deletedBookIDs: Set<String> = []

    func prepare(source: AIPageSource, page: Int, bookID: UUID) throws -> PreparedTranslationPage {
        try Task.checkCancellation()
        let image: UIImage
        switch source {
        case .image(let url):
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2_800,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw TranslationFailure.unreadable }
            image = UIImage(cgImage: cg)
        case .pdf(let url, let password):
            guard let document = PDFDocument(url: url) else { throw TranslationFailure.unreadable }
            if document.isLocked { _ = document.unlock(withPassword: password) }
            guard !document.isLocked, let pdfPage = document.page(at: page) else { throw TranslationFailure.unreadable }
            image = pdfPage.thumbnail(of: CGSize(width: 2_800, height: 2_800), for: .cropBox)
        case .ebookText:
            throw TranslationFailure.unreadable
        }
        try Task.checkCancellation()
        guard let data = image.pngData() else { throw TranslationFailure.unreadable }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return PreparedTranslationPage(image: image, key: "\(bookID.uuidString)-\(page)-ja-zh-v1-\(hash)")
    }

    func recognize(image: UIImage, selection: TranslationBox? = nil) throws -> [TranslationRegion] {
        try Task.checkCancellation()
        guard let fullImage = image.cgImage else { throw TranslationFailure.unreadable }
        let bounds = selection?.rect ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let pixelRect = TranslationBox(bounds).pixels(in: CGSize(width: fullImage.width, height: fullImage.height)).integral
        guard let cropped = fullImage.cropping(to: pixelRect), cropped.width > 2, cropped.height > 2 else {
            throw TranslationFailure.emptySelection
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.004
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["ja-JP", "en-US"].filter { supported.contains($0) }
        guard request.recognitionLanguages.contains("ja-JP") else { throw TranslationFailure.unsupported }
        try VNImageRequestHandler(cgImage: cropped, orientation: .up).perform([request])
        try Task.checkCancellation()
        let regions = (request.results ?? []).compactMap { observation -> TranslationRegion? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let r = observation.boundingBox
            let mapped = CGRect(x: bounds.minX + r.minX * bounds.width,
                                y: bounds.minY + (1 - r.maxY) * bounds.height,
                                width: r.width * bounds.width, height: r.height * bounds.height)
            return TranslationRegion(id: UUID().uuidString, box: TranslationBox(mapped), source: text,
                                     confidence: candidate.confidence,
                                     isVertical: mapped.height * image.size.height > mapped.width * image.size.width * 1.2)
        }
        return TranslationParagraphs.group(regions, imageSize: image.size)
    }

    func load(key: String) -> PageTranslationDocument? {
        guard let url = try? fileURL(key: key), let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(PageTranslationDocument.self, from: data),
              (1...2).contains(document.schema) else { return nil }
        return document
    }

    func save(_ document: PageTranslationDocument, key: String) throws {
        guard !deletedBookIDs.contains(String(key.prefix(36))) else { return }
        let data = try JSONEncoder().encode(document)
        try data.write(to: fileURL(key: key), options: .atomic)
    }

    func removeRecords(bookID: UUID) throws {
        let prefix = bookID.uuidString + "-"
        deletedBookIDs.insert(bookID.uuidString)
        let folder = try fileURL(key: "placeholder").deletingLastPathComponent()
        for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            if url.pathExtension == "json", url.lastPathComponent.hasPrefix(prefix) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func fileURL(key: String) throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
            .appendingPathComponent("InkShelfTranslations", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(key).appendingPathExtension("json")
    }
}

enum TranslationFailure: LocalizedError {
    case unreadable, emptySelection, unsupported
    var errorDescription: String? {
        switch self {
        case .unreadable: "暂时无法读取这一页，请返回阅读器重新打开。"
        case .emptySelection: "框选范围太小，请圈住完整的日文对白。"
        case .unsupported: "当前系统的文字识别不支持日语，请更新系统后重试。"
        }
    }
}
