import CoreImage
import CoreML
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct OnDeviceSharpStatus: Sendable {
    let model: String
    let tileSize: Int
    let upscale: Int
    let finalScale: Int
}

actor OnDeviceSharpProcessor {
    static let shared = OnDeviceSharpProcessor()

    private let tileSize = 128
    private let tilePadding = 16
    private let coreSize = 96
    private let maximumOutputPixels = 48_000_000
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let context = CIContext(options: [
        .cacheIntermediates: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
    ])
    private var cachedModel: MLModel?

    func status() throws -> OnDeviceSharpStatus {
        _ = try model()
        return OnDeviceSharpStatus(
            model: "realesrgan-x4plus-anime",
            tileSize: tileSize,
            upscale: 4,
            finalScale: 2
        )
    }

    func enhance(source: SharpPageSource, outputName: String) async throws -> SharpEnhancementResult {
        let model = try model()
        let sourceImage = try normalizedImage(for: source)
        let width = Int(sourceImage.extent.width.rounded(.down))
        let height = Int(sourceImage.extent.height.rounded(.down))
        guard width > 0, height > 0 else { throw OnDeviceSharpError.unreadablePage }

        let outputWidth = try multiplied(width, by: 2)
        let outputHeight = try multiplied(height, by: 2)
        guard outputWidth * outputHeight <= maximumOutputPixels else {
            throw OnDeviceSharpError.imageTooLarge
        }

        let rowBytes = try multiplied(outputWidth, by: 4)
        let byteCount = try multiplied(rowBytes, by: outputHeight)
        guard let storage = NSMutableData(length: byteCount),
              let bitmap = CGContext(
                data: storage.mutableBytes,
                width: outputWidth,
                height: outputHeight,
                bitsPerComponent: 8,
                bytesPerRow: rowBytes,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw OnDeviceSharpError.outOfMemory }
        bitmap.interpolationQuality = .none

        var y = 0
        while y < height {
            var x = 0
            while x < width {
                try Task.checkCancellation()
                let coreWidth = min(coreSize, width - x)
                let coreHeight = min(coreSize, height - y)
                let tileRect = CGRect(
                    x: x - tilePadding,
                    y: y - tilePadding,
                    width: tileSize,
                    height: tileSize
                )
                let inputBuffer = try makePixelBuffer(width: tileSize, height: tileSize)
                let tile = sourceImage
                    .clampedToExtent()
                    .cropped(to: tileRect)
                    .transformed(by: CGAffineTransform(
                        translationX: -tileRect.minX,
                        y: -tileRect.minY
                    ))
                context.render(
                    tile,
                    to: inputBuffer,
                    bounds: CGRect(x: 0, y: 0, width: tileSize, height: tileSize),
                    colorSpace: colorSpace
                )

                let provider = try MLDictionaryFeatureProvider(dictionary: [
                    "input": MLFeatureValue(pixelBuffer: inputBuffer)
                ])
                let prediction = try await model.prediction(from: provider)
                guard let fourXBuffer = prediction.featureValue(for: "output")?.imageBufferValue else {
                    throw OnDeviceSharpError.invalidModelOutput
                }

                let twoX = CIImage(cvPixelBuffer: fourXBuffer).applyingFilter(
                    "CILanczosScaleTransform",
                    parameters: [
                        kCIInputScaleKey: 0.5,
                        kCIInputAspectRatioKey: 1.0
                    ]
                )
                let crop = CGRect(
                    x: tilePadding * 2,
                    y: tilePadding * 2,
                    width: coreWidth * 2,
                    height: coreHeight * 2
                )
                guard let tileImage = context.createCGImage(twoX, from: crop) else {
                    throw OnDeviceSharpError.invalidModelOutput
                }
                bitmap.draw(
                    tileImage,
                    in: CGRect(x: x * 2, y: y * 2, width: coreWidth * 2, height: coreHeight * 2)
                )
                x += coreSize
            }
            y += coreSize
        }

        try Task.checkCancellation()
        guard let completed = bitmap.makeImage() else { throw OnDeviceSharpError.invalidModelOutput }
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("InkShelfSharpResult", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let outputURL = temporaryRoot.appendingPathComponent(safeFilename(outputName))
        do {
            guard let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else { throw OnDeviceSharpError.cannotWritePNG }
            CGImageDestinationAddImage(destination, completed, [
                kCGImagePropertyPNGCompressionFilter: 5
            ] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw OnDeviceSharpError.cannotWritePNG
            }
            return SharpEnhancementResult(
                temporaryRoot: temporaryRoot,
                outputURL: outputURL,
                executionLocation: .device
            )
        } catch {
            try? FileManager.default.removeItem(at: temporaryRoot)
            throw error
        }
    }

    private func model() throws -> MLModel {
        if let cachedModel { return cachedModel }
        guard let url = Bundle.main.url(forResource: "RealESRGANAnimeSharp", withExtension: "mlmodelc") else {
            throw OnDeviceSharpError.modelUnavailable
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let loaded = try MLModel(contentsOf: url, configuration: configuration)
        let metadata = loaded.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
        guard metadata?["com.inkshelf.profile"] == "sharp",
              metadata?["com.inkshelf.model"] == "realesrgan-x4plus-anime",
              metadata?["com.inkshelf.upscale"] == "4",
              loaded.modelDescription.inputDescriptionsByName["input"]?.imageConstraint?.pixelsWide == tileSize,
              loaded.modelDescription.inputDescriptionsByName["input"]?.imageConstraint?.pixelsHigh == tileSize,
              loaded.modelDescription.outputDescriptionsByName["output"]?.imageConstraint?.pixelsWide == tileSize * 4,
              loaded.modelDescription.outputDescriptionsByName["output"]?.imageConstraint?.pixelsHigh == tileSize * 4
        else { throw OnDeviceSharpError.wrongModel }
        cachedModel = loaded
        return loaded
    }

    private func normalizedImage(for source: SharpPageSource) throws -> CIImage {
        let image: CIImage?
        switch source {
        case .image(let url):
            image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
        case .pdf(let url, let page, let password):
            guard let document = PDFDocument(url: url) else { throw OnDeviceSharpError.unreadablePage }
            if document.isLocked, !password.isEmpty { _ = document.unlock(withPassword: password) }
            guard !document.isLocked,
                  page >= 0,
                  page < document.pageCount,
                  let pdfPage = document.page(at: page)
            else { throw OnDeviceSharpError.unreadablePage }
            let bounds = pdfPage.bounds(for: .cropBox)
            let longest = max(bounds.width, bounds.height)
            let scale = min(1, 2_048 / max(longest, 1))
            image = CIImage(image: pdfPage.thumbnail(
                of: CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale)),
                for: .cropBox
            ))
        }
        guard let image else { throw OnDeviceSharpError.unreadablePage }
        let extent = image.extent.integral
        return image
            .cropped(to: extent)
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
    }

    private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { throw OnDeviceSharpError.outOfMemory }
        return buffer
    }

    private func multiplied(_ lhs: Int, by rhs: Int) throws -> Int {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard !result.overflow else { throw OnDeviceSharpError.imageTooLarge }
        return result.partialValue
    }

    private func safeFilename(_ value: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = value.components(separatedBy: illegal).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = URL(fileURLWithPath: cleaned.isEmpty ? "Sharp 锐化 2x" : cleaned)
            .deletingPathExtension().lastPathComponent
        return "\(String(stem.prefix(70)))-sharp-2x.png"
    }
}

enum OnDeviceSharpError: LocalizedError {
    case modelUnavailable
    case wrongModel
    case unreadablePage
    case imageTooLarge
    case outOfMemory
    case invalidModelOutput
    case cannotWritePNG

    var errorDescription: String? {
        switch self {
        case .modelUnavailable: "当前安装包没有包含本地 Sharp 模型，可填写电脑桥地址作为备用。"
        case .wrongModel: "本地模型不是已确认的 realesrgan-x4plus-anime Sharp 方案。"
        case .unreadablePage: "无法读取当前页面用于清晰化。"
        case .imageTooLarge: "当前页在本机生成 2x PNG 会占用过多内存，请使用电脑桥处理。"
        case .outOfMemory: "设备没有足够内存完成本页清晰化，请关闭其他应用或改用电脑桥。"
        case .invalidModelOutput: "本地动漫模型没有生成有效图片。"
        case .cannotWritePNG: "清晰化已完成，但无法写入无损 PNG。"
        }
    }
}
