import Foundation
import ImageIO
import PDFKit
import UIKit
import Vision

enum AIPageSource: Sendable {
    case image(URL)
    case pdf(URL, password: String)
    case ebookText(String, format: String)
}

actor PageInsightService {
    static let shared = PageInsightService()

    func analyze(source: AIPageSource, page: Int, pageCount: Int) throws -> AIPageInsight {
        if case .ebookText(let text, let format) = source {
            return AIPageInsight(
                page: page,
                pageCount: pageCount,
                recognizedText: String(normalizedText(text).prefix(4_000)),
                visualLabels: [],
                faceCount: 0,
                sourceKind: "\(format) 电子书章节"
            )
        }
        let prepared = try prepareImage(source: source, page: page)
        let recognized = recognize(cgImage: prepared.cgImage)
        let combinedText = normalizedText([prepared.embeddedText, recognized.text]
            .filter { !$0.isEmpty }
            .joined(separator: "\n"))

        return AIPageInsight(
            page: page,
            pageCount: pageCount,
            recognizedText: String(combinedText.prefix(1_800)),
            visualLabels: recognized.labels,
            faceCount: recognized.faceCount,
            sourceKind: prepared.sourceKind
        )
    }

    private func prepareImage(source: AIPageSource, page: Int) throws -> PreparedPage {
        switch source {
        case .image(let url):
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                throw PageInsightError.unreadablePage
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_600,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                throw PageInsightError.unreadablePage
            }
            return PreparedPage(cgImage: cgImage, embeddedText: "", sourceKind: "图片/漫画页")

        case .pdf(let url, let password):
            guard let document = PDFDocument(url: url) else { throw PageInsightError.unreadablePDF }
            if document.isLocked, !password.isEmpty {
                _ = document.unlock(withPassword: password)
            }
            guard !document.isLocked,
                  page >= 0,
                  page < document.pageCount,
                  let pdfPage = document.page(at: page)
            else { throw PageInsightError.lockedPDF }

            let thumbnail = pdfPage.thumbnail(of: CGSize(width: 1_600, height: 1_600), for: .cropBox)
            guard let cgImage = thumbnail.cgImage else { throw PageInsightError.unreadablePage }
            return PreparedPage(
                cgImage: cgImage,
                embeddedText: pdfPage.string ?? "",
                sourceKind: "PDF 页面"
            )
        case .ebookText:
            throw PageInsightError.unreadablePage
        }
    }

    private func recognize(cgImage: CGImage) -> (text: String, labels: [String], faceCount: Int) {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.automaticallyDetectsLanguage = true
        textRequest.recognitionLanguages = ["zh-Hans", "zh-Hant", "ja-JP", "en-US"]
        try? handler.perform([textRequest])

        let faceRequest = VNDetectFaceRectanglesRequest()
        try? handler.perform([faceRequest])

        let classifyRequest = VNClassifyImageRequest()
        try? handler.perform([classifyRequest])

        let observations = (textRequest.results ?? []).sorted(by: readingOrder)
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let labels = (classifyRequest.results ?? [])
            .filter { $0.confidence >= 0.08 }
            .prefix(8)
            .map { "\($0.identifier) (\(Int($0.confidence * 100))%)" }

        return (lines.joined(separator: "\n"), labels, faceRequest.results?.count ?? 0)
    }

    /// Vision's result order is not guaranteed to match manga reading order.
    /// Vertical Japanese columns are read right-to-left; horizontal lines are
    /// read top-to-bottom and then left-to-right within the same row.
    private func readingOrder(_ left: VNRecognizedTextObservation, _ right: VNRecognizedTextObservation) -> Bool {
        let leftBox = left.boundingBox
        let rightBox = right.boundingBox
        let leftVertical = leftBox.height > leftBox.width * 1.2
        let rightVertical = rightBox.height > rightBox.width * 1.2
        if leftVertical && rightVertical {
            if abs(leftBox.midX - rightBox.midX) > 0.04 { return leftBox.midX > rightBox.midX }
            return leftBox.maxY > rightBox.maxY
        }
        if !leftVertical && !rightVertical {
            if abs(leftBox.midY - rightBox.midY) > 0.035 { return leftBox.midY > rightBox.midY }
            return leftBox.minX < rightBox.minX
        }
        if abs(leftBox.midY - rightBox.midY) > 0.05 { return leftBox.midY > rightBox.midY }
        return leftBox.midX > rightBox.midX
    }

    private func normalizedText(_ text: String) -> String {
        text
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

private struct PreparedPage {
    let cgImage: CGImage
    let embeddedText: String
    let sourceKind: String
}

private enum PageInsightError: LocalizedError {
    case unreadablePage
    case unreadablePDF
    case lockedPDF

    var errorDescription: String? {
        switch self {
        case .unreadablePage: return "无法读取这一页的画面。"
        case .unreadablePDF: return "无法打开 PDF。"
        case .lockedPDF: return "请先解锁 PDF，再让 AI 阅读。"
        }
    }
}
