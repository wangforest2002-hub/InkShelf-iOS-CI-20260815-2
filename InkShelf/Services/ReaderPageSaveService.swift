import PDFKit
import Photos
import UIKit

enum ReaderPageSaveError: LocalizedError {
    case unsupported
    case missingPage
    case lockedPDF
    case renderFailed
    case photoAccessDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .unsupported: "电子书正文暂不支持保存为图片。"
        case .missingPage: "找不到当前页面，请重新打开读物后再试。"
        case .lockedPDF: "请先解锁 PDF，再保存当前页。"
        case .renderFailed: "当前 PDF 页面无法生成高清图片。"
        case .photoAccessDenied: "没有添加照片的权限，请到系统设置中允许“二次元小家”添加照片。"
        case .saveFailed: "保存到照片时出现问题，请稍后再试。"
        }
    }
}

enum ReaderPageSaveService {
    static func save(
        book: Book,
        page: Int,
        imageURLs: [URL],
        pdfURL: URL?,
        pdfPassword: String
    ) async throws {
        let sourceURL: URL
        var temporaryURL: URL?

        switch book.kind {
        case .archive, .imageCollection:
            guard imageURLs.indices.contains(page) else { throw ReaderPageSaveError.missingPage }
            sourceURL = imageURLs[page]
        case .pdf:
            guard let pdfURL else { throw ReaderPageSaveError.missingPage }
            let data = try await Task.detached(priority: .userInitiated) {
                try renderedPDFPageData(url: pdfURL, page: page, password: pdfPassword)
            }.value
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("二次元小家-\(UUID().uuidString).png")
            try data.write(to: url, options: .atomic)
            sourceURL = url
            temporaryURL = url
        case .ebook:
            throw ReaderPageSaveError.unsupported
        }

        defer {
            if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ReaderPageSaveError.photoAccessDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: sourceURL)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? ReaderPageSaveError.saveFailed)
                }
            }
        }
    }

    static func renderedPDFPageData(url: URL, page: Int, password: String) throws -> Data {
        guard let document = PDFDocument(url: url) else { throw ReaderPageSaveError.renderFailed }
        if document.isLocked, !password.isEmpty { _ = document.unlock(withPassword: password) }
        guard !document.isLocked else { throw ReaderPageSaveError.lockedPDF }
        guard let pdfPage = document.page(at: page) else { throw ReaderPageSaveError.missingPage }

        let bounds = pdfPage.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { throw ReaderPageSaveError.renderFailed }
        let scale = min(4_096 / max(bounds.width, bounds.height), 4)
        let size = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(origin: .zero, size: size))
            let context = renderer.cgContext
            context.saveGState()
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: scale, y: -scale)
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            pdfPage.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }
        guard let data = image.pngData() else { throw ReaderPageSaveError.renderFailed }
        return data
    }
}
