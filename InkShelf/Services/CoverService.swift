import Foundation
import ImageIO
import PDFKit
import UIKit

enum CoverService {
    private static let coverFileName = "cover.jpg"

    static func createPDFCover(document: PDFDocument, in folder: URL) -> String? {
        guard !document.isLocked, let page = document.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let targetWidth: CGFloat = 900
        let targetSize = CGSize(width: targetWidth, height: targetWidth * bounds.height / bounds.width)
        let image = page.thumbnail(of: targetSize, for: .cropBox)
        return writeJPEG(image, to: folder)
    }

    static func createImageCover(sourceURL: URL, in folder: URL) -> String? {
        createImagePreviews(sourceURLs: [sourceURL], in: folder).first
    }

    static func createImagePreviews(sourceURLs: [URL], in folder: URL) -> [String] {
        var names: [String] = []
        for (index, sourceURL) in sourceURLs.prefix(4).enumerated() {
            let fileName = index == 0 ? coverFileName : "preview-\(index + 1).jpg"
            let pixelSize = index == 0 ? 720 : 420
            guard let image = downsampledImage(from: sourceURL, maxPixelSize: pixelSize),
                  writeJPEG(image, to: folder, fileName: fileName) != nil
            else { continue }
            names.append(fileName)
        }
        return names
    }

    private static func downsampledImage(from sourceURL: URL, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func writeJPEG(_ image: UIImage, to folder: URL, fileName: String = coverFileName) -> String? {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let flattened = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: image.size))
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        guard let data = flattened.jpegData(compressionQuality: 0.86) else { return nil }
        let destination = folder.appendingPathComponent(fileName)
        do {
            try data.write(to: destination, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }
}
