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
        for sourceURL in sourceURLs.prefix(1) {
            let fileName = coverFileName
            let pixelSize = 720
            guard let image = downsampledImage(from: sourceURL, maxPixelSize: pixelSize),
                  writeJPEG(image, to: folder, fileName: fileName) != nil
            else { continue }
            names.append(fileName)
        }
        return names
    }

    /// Reads only the image header. This is cheap enough for import metadata
    /// and avoids decoding a full cover merely to decide its shelf shape.
    static func aspectRatio(at url: URL) -> Double? {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
           let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
           width.doubleValue > 0,
           height.doubleValue > 0
        else { return nil }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(orientation)
        let displayWidth = rotated ? height.doubleValue : width.doubleValue
        let displayHeight = rotated ? width.doubleValue : height.doubleValue
        let ratio = displayWidth / displayHeight
        return ratio.isFinite && ratio >= 0.2 && ratio <= 5 ? ratio : nil
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
