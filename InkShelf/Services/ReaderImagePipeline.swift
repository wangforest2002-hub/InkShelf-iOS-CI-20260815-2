import ImageIO
import UIKit

/// Downsamples reader pages away from the main thread and keeps only a small
/// working set in memory. Source files are never modified.
final class ReaderImagePipeline: @unchecked Sendable {
    static let shared = ReaderImagePipeline()

    enum RequestPriority: Equatable {
        case display
        case prefetch

        fileprivate var queuePriority: Operation.QueuePriority {
            switch self {
            case .display: .veryHigh
            case .prefetch: .low
            }
        }
    }

    private let cache = NSCache<NSString, UIImage>()
    private let previewQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.inkshelf.reader.image-preview"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    private let fullDecodeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.inkshelf.reader.image-full-decode"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    private let stateQueue = DispatchQueue(label: "com.inkshelf.reader.image-state")
    private var callbacks: [String: [(UIImage?) -> Void]] = [:]
    private var operations: [String: Operation] = [:]

    private init() {
        cache.countLimit = 10
        let physicalMemory = Int(ProcessInfo.processInfo.physicalMemory)
        cache.totalCostLimit = min(256 * 1_024 * 1_024, max(96 * 1_024 * 1_024, physicalMemory / 24))
    }

    func load(
        _ url: URL,
        maxPixelSize: Int,
        priority: RequestPriority = .display,
        completion: @escaping (UIImage?) -> Void
    ) {
        let boundedPixelSize = Self.pixelBucket(for: maxPixelSize)
        let key = cacheKey(for: url, pixelSize: boundedPixelSize)
        if let cached = cache.object(forKey: key) {
            DispatchQueue.main.async { completion(cached) }
            return
        }

        let keyString = key as String
        var decodeOperation: BlockOperation?
        let shouldDecode = stateQueue.sync { () -> Bool in
            if callbacks[keyString] != nil {
                callbacks[keyString, default: []].append(completion)
                if priority == .display {
                    operations[keyString]?.queuePriority = priority.queuePriority
                }
                return false
            }
            callbacks[keyString] = [completion]
            let operation = BlockOperation { [weak self] in
                self?.decode(
                    url: url,
                    boundedPixelSize: boundedPixelSize,
                    key: key,
                    keyString: keyString
                )
            }
            operation.qualityOfService = priority == .display ? .userInitiated : .utility
            operation.queuePriority = priority.queuePriority
            operations[keyString] = operation
            decodeOperation = operation
            return true
        }
        guard shouldDecode, let decodeOperation else { return }
        let queue = boundedPixelSize <= 1_024 ? previewQueue : fullDecodeQueue
        queue.addOperation(decodeOperation)
    }

    /// Makes a page visible quickly, then replaces it with the reading-quality
    /// decode. A cached full-resolution page skips the preview callback.
    func loadProgressively(
        _ url: URL,
        maxPixelSize: Int,
        completion: @escaping (_ image: UIImage?, _ isFinal: Bool) -> Void
    ) {
        let fullPixelSize = Self.pixelBucket(for: maxPixelSize)
        let fullKey = cacheKey(for: url, pixelSize: fullPixelSize)
        if let cached = cache.object(forKey: fullKey) {
            DispatchQueue.main.async { completion(cached, true) }
            return
        }

        let previewPixelSize = min(1_024, fullPixelSize)
        load(url, maxPixelSize: previewPixelSize, priority: .display) { [weak self] preview in
            let needsFullDecode = previewPixelSize < fullPixelSize
            completion(preview, !needsFullDecode)
            guard needsFullDecode, let self else { return }
            self.load(url, maxPixelSize: fullPixelSize, priority: .display) { fullImage in
                completion(fullImage ?? preview, true)
            }
        }
    }

    func prefetch(_ urls: [URL], maxPixelSize: Int) {
        for url in urls {
            load(url, maxPixelSize: maxPixelSize, priority: .prefetch) { _ in }
        }
    }

    /// Stable buckets avoid decoding the same page repeatedly for tiny layout
    /// changes while still providing a cheap first paint for oversized art.
    static func pixelBucket(for requestedSize: Int) -> Int {
        switch requestedSize {
        case ...512: 512
        case ...1_024: 1_024
        default: 3_072
        }
    }

    private func cacheKey(for url: URL, pixelSize: Int) -> NSString {
        "\(url.standardizedFileURL.path)|\(pixelSize)" as NSString
    }

    private func decode(
        url: URL,
        boundedPixelSize: Int,
        key: NSString,
        keyString: String
    ) {
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
            cache.setObject(
                decoded,
                forKey: key,
                cost: cgImage.bytesPerRow * cgImage.height
            )
            return decoded
        }

        let completions = stateQueue.sync {
            operations.removeValue(forKey: keyString)
            return callbacks.removeValue(forKey: keyString) ?? []
        }
        DispatchQueue.main.async {
            completions.forEach { $0(image) }
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

/// Shelf covers have a very different working set from full reader pages.
/// Keeping their thumbnails in a dedicated cache prevents a long shelf from
/// evicting the adjacent high-resolution pages that make swiping feel instant.
final class CoverImagePipeline: @unchecked Sendable {
    static let shared = CoverImagePipeline()

    private let cache = NSCache<NSString, UIImage>()
    private let decodeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.inkshelf.cover-decode"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    private let stateQueue = DispatchQueue(label: "com.inkshelf.cover-state")
    private var callbacks: [String: [(UIImage?) -> Void]] = [:]

    private init() {
        cache.countLimit = 160
        cache.totalCostLimit = 72 * 1_024 * 1_024
    }

    func image(for url: URL, maxPixelSize: Int = 768) async -> UIImage? {
        await withCheckedContinuation { continuation in
            load(url, maxPixelSize: maxPixelSize) { image in
                continuation.resume(returning: image)
            }
        }
    }

    func load(
        _ url: URL,
        maxPixelSize: Int = 768,
        completion: @escaping (UIImage?) -> Void
    ) {
        let size = min(max(maxPixelSize, 256), 1_024)
        let key = "\(url.standardizedFileURL.path)|\(size)" as NSString
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
                    kCGImageSourceThumbnailMaxPixelSize: size,
                    kCGImageSourceShouldCacheImmediately: true
                ]
                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    options as CFDictionary
                ) else { return nil }
                let decoded = UIImage(cgImage: cgImage)
                cache.setObject(
                    decoded,
                    forKey: key,
                    cost: cgImage.bytesPerRow * cgImage.height
                )
                return decoded
            }

            let completions = stateQueue.sync {
                callbacks.removeValue(forKey: keyString) ?? []
            }
            DispatchQueue.main.async {
                completions.forEach { $0(image) }
            }
        }
    }
}
