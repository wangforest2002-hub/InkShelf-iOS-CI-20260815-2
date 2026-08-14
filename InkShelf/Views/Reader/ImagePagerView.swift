import SwiftUI
import UIKit

struct ImagePagerView: UIViewRepresentable {
    let imageURLs: [URL]
    @Binding var currentPage: Int
    let layout: ReaderLayout
    let flow: ReaderFlow
    let order: ReadingOrder
    let coverSingle: Bool
    let backgroundColor: UIColor
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PagerCollectionView {
        let flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = 0
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.scrollDirection = flow == .horizontal ? .horizontal : .vertical

        let collectionView = PagerCollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = backgroundColor
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.isPagingEnabled = true
        collectionView.decelerationRate = .fast
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = flow == .horizontal
        collectionView.alwaysBounceVertical = flow == .vertical
        collectionView.dataSource = context.coordinator
        collectionView.prefetchDataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(ImagePageCell.self, forCellWithReuseIdentifier: ImagePageCell.reuseIdentifier)
        collectionView.semanticContentAttribute = order == .rightToLeft && flow == .horizontal ? .forceRightToLeft : .forceLeftToRight
        context.coordinator.rebuildConfiguration(from: self)
        return collectionView
    }

    func updateUIView(_ collectionView: PagerCollectionView, context: Context) {
        context.coordinator.parent = self
        collectionView.backgroundColor = backgroundColor
        collectionView.semanticContentAttribute = order == .rightToLeft && flow == .horizontal ? .forceRightToLeft : .forceLeftToRight

        if let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            let direction: UICollectionView.ScrollDirection = flow == .horizontal ? .horizontal : .vertical
            if flowLayout.scrollDirection != direction {
                flowLayout.scrollDirection = direction
                collectionView.alwaysBounceHorizontal = flow == .horizontal
                collectionView.alwaysBounceVertical = flow == .vertical
                flowLayout.invalidateLayout()
            }
        }

        let configurationChanged = context.coordinator.configurationKey != configurationKey
        if configurationChanged {
            context.coordinator.rebuildConfiguration(from: self)
            collectionView.reloadData()
            collectionView.collectionViewLayout.invalidateLayout()
        }

        let groups = context.coordinator.groups
        let target = groups.firstIndex { $0.indices.contains(currentPage) } ?? 0
        guard !groups.isEmpty,
              !collectionView.isDragging,
              !collectionView.isDecelerating,
              context.coordinator.visibleIndex(in: collectionView) != target
        else { return }

        DispatchQueue.main.async {
            collectionView.layoutIfNeeded()
            guard target < collectionView.numberOfItems(inSection: 0) else { return }
            collectionView.scrollToItem(
                at: IndexPath(item: target, section: 0),
                at: self.flow == .horizontal ? .centeredHorizontally : .centeredVertically,
                animated: false
            )
        }
    }

    fileprivate var configurationKey: String {
        [
            String(imageURLs.count),
            imageURLs.first?.standardizedFileURL.path ?? "",
            imageURLs.last?.standardizedFileURL.path ?? "",
            layout.rawValue,
            flow.rawValue,
            order.rawValue,
            String(coverSingle)
        ].joined(separator: "|")
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDataSourcePrefetching, UICollectionViewDelegate, UIScrollViewDelegate {
        var parent: ImagePagerView
        fileprivate var groups: [ImagePageGroup] = []
        fileprivate var configurationKey = ""

        init(parent: ImagePagerView) {
            self.parent = parent
        }

        func rebuildConfiguration(from parent: ImagePagerView) {
            configurationKey = parent.configurationKey
            groups = ImagePageGroup.make(
                urls: parent.imageURLs,
                layout: parent.layout,
                coverSingle: parent.coverSingle
            )
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            groups.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            guard groups.indices.contains(indexPath.item),
                  let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: ImagePageCell.reuseIdentifier,
                    for: indexPath
                  ) as? ImagePageCell
            else { return UICollectionViewCell() }

            let group = groups[indexPath.item]
            let urls = parent.order == .rightToLeft ? Array(group.urls.reversed()) : group.urls
            cell.configure(
                urls: urls,
                pageLabel: group.indices.map { String($0 + 1) }.joined(separator: "、"),
                backgroundColor: parent.backgroundColor,
                onTap: parent.onTap
            )
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            let pixelSize = preferredPixelSize(for: collectionView)
            let urls = indexPaths.flatMap { indexPath in
                groups.indices.contains(indexPath.item) ? groups[indexPath.item].urls : []
            }
            ReaderImagePipeline.shared.prefetch(urls, maxPixelSize: pixelSize)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            updateCurrentPage(from: scrollView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { updateCurrentPage(from: scrollView) }
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            updateCurrentPage(from: scrollView)
        }

        func visibleIndex(in scrollView: UIScrollView) -> Int {
            if let collectionView = scrollView as? UICollectionView {
                let center = CGPoint(
                    x: collectionView.contentOffset.x + collectionView.bounds.midX,
                    y: collectionView.contentOffset.y + collectionView.bounds.midY
                )
                if let indexPath = collectionView.indexPathForItem(at: center) {
                    return indexPath.item
                }
            }
            guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return 0 }
            if parent.flow == .horizontal {
                return Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
            }
            return Int(round(scrollView.contentOffset.y / scrollView.bounds.height))
        }

        private func updateCurrentPage(from scrollView: UIScrollView) {
            let index = min(max(0, visibleIndex(in: scrollView)), max(0, groups.count - 1))
            guard groups.indices.contains(index), let page = groups[index].indices.first else { return }
            if parent.currentPage != page { parent.currentPage = page }
        }

        private func preferredPixelSize(for collectionView: UICollectionView) -> Int {
            let longestSide = max(collectionView.bounds.width, collectionView.bounds.height)
            let scale = collectionView.window?.screen.scale ?? UIScreen.main.scale
            return min(4_096, max(1_800, Int((longestSide * scale * 1.25).rounded(.up))))
        }
    }
}

fileprivate struct ImagePageGroup {
    let indices: [Int]
    let urls: [URL]

    static func make(urls: [URL], layout: ReaderLayout, coverSingle: Bool) -> [ImagePageGroup] {
        guard !urls.isEmpty else { return [] }
        if layout == .single {
            return urls.indices.map { ImagePageGroup(indices: [$0], urls: [urls[$0]]) }
        }

        var groups: [ImagePageGroup] = []
        var index = 0
        if coverSingle {
            groups.append(ImagePageGroup(indices: [0], urls: [urls[0]]))
            index = 1
        }
        while index < urls.count {
            let end = min(index + 2, urls.count)
            let indices = Array(index..<end)
            groups.append(ImagePageGroup(indices: indices, urls: indices.map { urls[$0] }))
            index = end
        }
        return groups
    }
}

final class PagerCollectionView: UICollectionView {
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let layout = collectionViewLayout as? UICollectionViewFlowLayout,
              bounds.width > 0,
              bounds.height > 0,
              layout.itemSize != bounds.size
        else { return }
        layout.itemSize = bounds.size
        layout.invalidateLayout()
    }
}

private final class ImagePageCell: UICollectionViewCell {
    static let reuseIdentifier = "ImagePageCell"
    private let zoomView = ZoomingSpreadScrollView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(zoomView)
        zoomView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            zoomView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            zoomView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            zoomView.topAnchor.constraint(equalTo: contentView.topAnchor),
            zoomView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        zoomView.clear()
    }

    func configure(urls: [URL], pageLabel: String, backgroundColor: UIColor, onTap: @escaping () -> Void) {
        accessibilityLabel = "第 \(pageLabel) 页"
        zoomView.backgroundColor = backgroundColor
        zoomView.configure(urls: urls, onTap: onTap)
    }
}

private final class ZoomingSpreadScrollView: UIScrollView, UIScrollViewDelegate {
    private let canvas = UIView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var imageViews: [UIImageView] = []
    private var naturalSizes: [CGSize] = []
    private var representedPaths: [String] = []
    private var tapAction: (() -> Void)?
    private var needsFit = true
    private var lastBoundsSize: CGSize = .zero
    private var loadGeneration = 0
    private var requestedPixelSize = 0
    private var loadedImageCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        contentInsetAdjustmentBehavior = .never
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        delaysContentTouches = false
        isDirectionalLockEnabled = true
        addSubview(canvas)
        addSubview(spinner)
        spinner.hidesWhenStopped = true

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        singleTap.require(toFail: doubleTap)
        singleTap.cancelsTouchesInView = false
        doubleTap.cancelsTouchesInView = false
        addGestureRecognizer(singleTap)
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(urls: [URL], onTap: @escaping () -> Void) {
        tapAction = onTap
        let paths = urls.map(\.standardizedFileURL.path)
        guard paths != representedPaths else { return }

        loadGeneration += 1
        representedPaths = paths
        requestedPixelSize = 0
        loadedImageCount = 0
        imageViews.forEach { $0.removeFromSuperview() }
        naturalSizes = urls.map { ReaderImagePipeline.pixelSize(of: $0) }
        imageViews = urls.map { _ in
            let view = UIImageView()
            view.contentMode = .scaleAspectFit
            view.clipsToBounds = true
            canvas.addSubview(view)
            return view
        }
        spinner.startAnimating()
        needsFit = true
        setNeedsLayout()
    }

    func clear() {
        loadGeneration += 1
        representedPaths = []
        tapAction = nil
        requestedPixelSize = 0
        loadedImageCount = 0
        imageViews.forEach { $0.removeFromSuperview() }
        imageViews = []
        naturalSizes = []
        spinner.stopAnimating()
        minimumZoomScale = 1
        maximumZoomScale = 1
        zoomScale = 1
        contentSize = .zero
        contentOffset = .zero
        needsFit = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        guard !imageViews.isEmpty, bounds.width > 0, bounds.height > 0 else { return }

        if needsFit || lastBoundsSize != bounds.size {
            fitCanvasToBounds()
        } else {
            centerCanvas()
        }
        requestDisplayImagesIfNeeded()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        canvas
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        panGestureRecognizer.isEnabled = zoomScale > minimumZoomScale + 0.01
        centerCanvas()
    }

    private func fitCanvasToBounds() {
        lastBoundsSize = bounds.size
        needsFit = false

        let normalizedHeight = max(naturalSizes.map(\.height).max() ?? 1, 1)
        let normalizedWidths = naturalSizes.map { max(1, $0.width / max($0.height, 1) * normalizedHeight) }
        let naturalGap = imageViews.count > 1 ? max(12, normalizedHeight * 0.004) : 0
        let naturalCanvas = CGSize(
            width: normalizedWidths.reduce(0, +) + naturalGap,
            height: normalizedHeight
        )
        let fitScale = min(bounds.width / naturalCanvas.width, bounds.height / naturalCanvas.height)
        let fittedCanvas = CGSize(
            width: max(1, naturalCanvas.width * fitScale),
            height: max(1, naturalCanvas.height * fitScale)
        )

        minimumZoomScale = 1
        maximumZoomScale = 8
        zoomScale = 1
        contentInset = .zero
        canvas.transform = .identity
        canvas.bounds = CGRect(origin: .zero, size: fittedCanvas)
        canvas.frame = CGRect(origin: .zero, size: fittedCanvas)

        var x: CGFloat = 0
        for (index, imageView) in imageViews.enumerated() {
            let width = normalizedWidths[index] * fitScale
            imageView.frame = CGRect(x: x, y: 0, width: width, height: fittedCanvas.height)
            x += width + naturalGap * fitScale
        }
        contentSize = fittedCanvas
        contentOffset = .zero
        panGestureRecognizer.isEnabled = false
        centerCanvas()
    }

    private func requestDisplayImagesIfNeeded() {
        let screenScale = window?.screen.scale ?? UIScreen.main.scale
        let target = min(4_096, max(1_800, Int((max(bounds.width, bounds.height) * screenScale * 1.25).rounded(.up))))
        guard target > requestedPixelSize, representedPaths.count == imageViews.count else { return }
        requestedPixelSize = target
        let generation = loadGeneration
        let paths = representedPaths

        for (index, path) in paths.enumerated() {
            ReaderImagePipeline.shared.load(URL(fileURLWithPath: path), maxPixelSize: target) { [weak self] image in
                guard let self,
                      self.loadGeneration == generation,
                      self.representedPaths == paths,
                      self.imageViews.indices.contains(index)
                else { return }
                self.imageViews[index].image = image
                self.loadedImageCount += 1
                if self.loadedImageCount >= self.imageViews.count {
                    self.spinner.stopAnimating()
                }
            }
        }
    }

    private func centerCanvas() {
        var frame = canvas.frame
        frame.origin.x = frame.width < bounds.width ? (bounds.width - frame.width) / 2 : 0
        frame.origin.y = frame.height < bounds.height ? (bounds.height - frame.height) / 2 : 0
        canvas.frame = frame
    }

    @objc private func singleTapped() {
        tapAction?()
    }

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.15 {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }

        let targetScale = min(maximumZoomScale, minimumZoomScale * 2.8)
        let point = recognizer.location(in: canvas)
        let width = bounds.width / targetScale
        let height = bounds.height / targetScale
        let zoomRect = CGRect(
            x: point.x - width / 2,
            y: point.y - height / 2,
            width: width,
            height: height
        )
        zoom(to: zoomRect, animated: true)
    }
}
