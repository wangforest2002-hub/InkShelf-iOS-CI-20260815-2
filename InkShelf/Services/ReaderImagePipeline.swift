import ImageIO
import UIKit

/// Downsamples reader pages away from the main thread and keeps only a small
/// working set in memory. Source files are never modified.
final class ReaderImagePipeline: @unchecked Sendable {
    static let shared = ReaderImagePipeline()

    private let cache = NSCache<NSString, UIImage>()
    private let decodeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.inkshelf.reader.image-decode"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    private let stateQueue = DispatchQueue(label: "com.inkshelf.reader.image-state")
    private var callbacks: [String: [(UIImage?) -> Void]] = [:]

    private init() {
        cache.countLimit = 10
        let physicalMemory = Int(ProcessInfo.processInfo.physicalMemory)
        cache.totalCostLimit = min(256 * 1_024 * 1_024, max(96 * 1_024 * 1_024, physicalMemory / 24))
    }

    func load(
        _ url: URL,
        maxPixelSize: Int,
        completion: @escaping (UIImage?) -> Void
    ) {
        // Two stable buckets prevent the same page being decoded repeatedly at
        // slightly different sizes as controls and orientation change.
        let boundedPixelSize = maxPixelSize <= 640
            ? min(max(maxPixelSize, 320), 640)
            : 3_072
        let key = "\(url.standardizedFileURL.path)|\(boundedPixelSize)" as NSString
        if let cached = cache.object(forKey: key) {
            DispatchQueue.main.async { completion(cached) }
            return
        }

        let keyString = key as String
        let shouldDecode = stateQueue.sync { () -> Bool in
            if callbacks[keyString] != nil {
                callbacks[keyString, default: []].append(completion)
                return false
            }
            callbacks[keyString] = [completion]
            return true
        }
        guard shouldDecode else { return }

        decodeQueue.addOperation { [weak self] in
            guard let self else { return }
            let image: UIImage? = autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(
                    url as CFURL,
                    [kCGImageSourceShouldCache: false] as CFDictionary
                ) else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: boundedPixelSize,
                    kCGImageSourceShouldCacheImmediately: true
                ]
                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    options as CFDictionary
                ) else { return nil }
                let decoded = UIImage(cgImage: cgImage)
                self.cache.setObject(
                    decoded,
                    forKey: key,
                    cost: cgImage.bytesPerRow * cgImage.height
                )
                return decoded
            }

            let completions = self.stateQueue.sync {
                self.callbacks.removeValue(forKey: keyString) ?? []
            }
            DispatchQueue.main.async {
                completions.forEach { $0(image) }
            }
        }
    }

    func prefetch(_ urls: [URL], maxPixelSize: Int) {
        for url in urls {
            load(url, maxPixelSize: maxPixelSize) { _ in }
        }
    }

    static func pixelSize(of url: URL) -> CGSize {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
        let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
        width.doubleValue > 0,
        height.doubleValue > 0
        else { return CGSize(width: 1, height: 1) }

        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }
}
