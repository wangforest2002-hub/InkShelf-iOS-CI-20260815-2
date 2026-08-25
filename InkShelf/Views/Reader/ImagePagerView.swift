import SwiftUI
import UIKit

struct ImagePagerView: UIViewRepresentable {
    let imageURLs: [URL]
    @Binding var currentPage: Int
    let layout: ReaderLayout
    let flow: ReaderFlow
    let transition: ReaderPageTransition
    let order: ReadingOrder
    let coverSingle: Bool
    let backgroundColor: UIColor
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PagerCollectionView {
        let flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = flow == .continuous ? 8 : 0
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.scrollDirection = flow == .horizontal ? .horizontal : .vertical

        let collectionView = PagerCollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.usesContinuousItemSizing = flow == .continuous
        collectionView.backgroundColor = backgroundColor
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.isPagingEnabled = flow != .continuous
        collectionView.decelerationRate = flow == .continuous ? .normal : .fast
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = flow == .horizontal
        collectionView.alwaysBounceVertical = flow != .horizontal
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
        collectionView.usesContinuousItemSizing = flow == .continuous
        collectionView.isPagingEnabled = flow != .continuous
        collectionView.decelerationRate = flow == .continuous ? .normal : .fast

        if let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            let direction: UICollectionView.ScrollDirection = flow == .horizontal ? .horizontal : .vertical
            let lineSpacing: CGFloat = flow == .continuous ? 8 : 0
            if flowLayout.scrollDirection != direction || flowLayout.minimumLineSpacing != lineSpacing {
                flowLayout.scrollDirection = direction
                flowLayout.minimumLineSpacing = lineSpacing
                collectionView.alwaysBounceHorizontal = flow == .horizontal
                collectionView.alwaysBounceVertical = flow != .horizontal
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
        context.coordinator.align(collectionView, to: target)
        context.coordinator.refreshPageTurnEffects(in: collectionView)
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

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDataSourcePrefetching, UICollectionViewDelegateFlowLayout, UIScrollViewDelegate {
        var parent: ImagePagerView
        fileprivate var groups: [ImagePageGroup] = []
        fileprivate var configurationKey = ""
        private var continuousAspectRatio: CGFloat = 0.70
        private var alignmentGeneration = 0
        private var pendingAlignmentIndex: Int?
        private var isApplyingProgrammaticAlignment = false
        private var dragStartIndex: Int?

        init(parent: ImagePagerView) {
            self.parent = parent
        }

        func rebuildConfiguration(from parent: ImagePagerView) {
            cancelPendingAlignment()
            dragStartIndex = nil
            configurationKey = parent.configurationKey
            groups = ImagePageGroup.make(
                urls: parent.imageURLs,
                layout: parent.layout,
                flow: parent.flow,
                coverSingle: parent.coverSingle
            )
            if let firstURL = parent.imageURLs.first {
                let size = ReaderImagePipeline.pixelSize(of: firstURL)
                continuousAspectRatio = min(max(size.width / max(size.height, 1), 0.12), 3)
            }
        }

        /// SwiftUI may call `updateUIView` several times before the main queue
        /// performs a collection-view scroll. Only the newest requested page is
        /// allowed to execute; older queued requests are invalidated so they
        /// cannot pull the reader back after a rapid scrub or layout change.
        func align(_ collectionView: UICollectionView, to requestedIndex: Int) {
            guard !groups.isEmpty else {
                cancelPendingAlignment()
                return
            }
            let target = min(max(0, requestedIndex), groups.count - 1)
            guard !collectionView.isDragging, !collectionView.isDecelerating else {
                cancelPendingAlignment()
                return
            }
            guard visibleIndex(in: collectionView) != target else {
                if pendingAlignmentIndex != nil { cancelPendingAlignment() }
                return
            }
            guard pendingAlignmentIndex != target else { return }

            alignmentGeneration += 1
            let generation = alignmentGeneration
            pendingAlignmentIndex = target

            DispatchQueue.main.async { [weak self, weak collectionView] in
                guard let self, let collectionView else { return }
                guard self.alignmentGeneration == generation,
                      self.pendingAlignmentIndex == target
                else { return }
                guard !collectionView.isDragging, !collectionView.isDecelerating else {
                    self.cancelPendingAlignment()
                    return
                }
                guard target < collectionView.numberOfItems(inSection: 0) else {
                    self.finishAlignment(generation: generation)
                    return
                }

                collectionView.layoutIfNeeded()
                guard self.visibleIndex(in: collectionView) != target else {
                    self.finishAlignment(generation: generation)
                    return
                }

                self.isApplyingProgrammaticAlignment = true
                collectionView.scrollToItem(
                    at: IndexPath(item: target, section: 0),
                    at: self.parent.flow == .horizontal ? .centeredHorizontally : .centeredVertically,
                    animated: false
                )
                collectionView.layoutIfNeeded()
                self.isApplyingProgrammaticAlignment = false
                self.finishAlignment(generation: generation)
                self.refreshPageTurnEffects(in: collectionView)
            }
        }

        private func finishAlignment(generation: Int) {
            guard alignmentGeneration == generation else { return }
            pendingAlignmentIndex = nil
        }

        private func cancelPendingAlignment() {
            alignmentGeneration += 1
            pendingAlignmentIndex = nil
            isApplyingProgrammaticAlignment = false
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            groups.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            guard parent.flow == .continuous else { return collectionView.bounds.size }
            let width = max(collectionView.bounds.width, 1)
            return CGSize(width: width, height: max(120, width / continuousAspectRatio))
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

        func collectionView(
            _ collectionView: UICollectionView,
            didEndDisplaying cell: UICollectionViewCell,
            forItemAt indexPath: IndexPath
        ) {
            (cell as? ImagePageCell)?.resetPageTurn()
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
            refreshPageTurnEffects(in: scrollView)
            dragStartIndex = nil
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            cancelPendingAlignment()
            dragStartIndex = visibleIndex(in: scrollView)
        }

        func scrollViewWillEndDragging(
            _ scrollView: UIScrollView,
            withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            guard parent.flow != .continuous,
                  let collectionView = scrollView as? UICollectionView,
                  !groups.isEmpty
            else { return }

            let start = dragStartIndex ?? visibleIndex(in: collectionView)
            let proposed = nearestItemIndex(
                to: targetContentOffset.pointee,
                in: collectionView
            ) ?? start
            let target = ReaderPageStepLimiter.destination(
                start: start,
                proposed: proposed,
                itemCount: groups.count
            )
            if let offset = contentOffset(forItemAt: target, in: collectionView) {
                targetContentOffset.pointee = offset
            }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                updateCurrentPage(from: scrollView)
                refreshPageTurnEffects(in: scrollView)
                dragStartIndex = nil
            }
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            updateCurrentPage(from: scrollView)
            refreshPageTurnEffects(in: scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            refreshPageTurnEffects(in: scrollView)
            guard parent.flow == .continuous,
                  scrollView.isDragging || scrollView.isDecelerating
            else { return }
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
                if let nearest = collectionView.indexPathsForVisibleItems.min(by: { left, right in
                    let leftCenter = collectionView.layoutAttributesForItem(at: left)?.center ?? .zero
                    let rightCenter = collectionView.layoutAttributesForItem(at: right)?.center ?? .zero
                    let leftDistance = hypot(leftCenter.x - center.x, leftCenter.y - center.y)
                    let rightDistance = hypot(rightCenter.x - center.x, rightCenter.y - center.y)
                    return leftDistance < rightDistance
                }) {
                    return nearest.item
                }
            }
            guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return 0 }
            if parent.flow == .horizontal {
                return Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
            }
            return Int(round(scrollView.contentOffset.y / scrollView.bounds.height))
        }

        private func nearestItemIndex(
            to proposedContentOffset: CGPoint,
            in collectionView: UICollectionView
        ) -> Int? {
            let center = CGPoint(
                x: proposedContentOffset.x + collectionView.bounds.midX,
                y: proposedContentOffset.y + collectionView.bounds.midY
            )
            let searchRect = CGRect(
                x: center.x - collectionView.bounds.width,
                y: center.y - collectionView.bounds.height,
                width: collectionView.bounds.width * 2,
                height: collectionView.bounds.height * 2
            )
            return collectionView.collectionViewLayout
                .layoutAttributesForElements(in: searchRect)?
                .filter { $0.representedElementCategory == .cell }
                .min { left, right in
                    let leftDistance = parent.flow == .horizontal
                        ? abs(left.center.x - center.x)
                        : abs(left.center.y - center.y)
                    let rightDistance = parent.flow == .horizontal
                        ? abs(right.center.x - center.x)
                        : abs(right.center.y - center.y)
                    return leftDistance < rightDistance
                }?
                .indexPath.item
        }

        private func contentOffset(
            forItemAt index: Int,
            in collectionView: UICollectionView
        ) -> CGPoint? {
            guard groups.indices.contains(index),
                  let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(
                    at: IndexPath(item: index, section: 0)
                  )
            else { return nil }

            var offset = collectionView.contentOffset
            if parent.flow == .horizontal {
                let minimum = -collectionView.adjustedContentInset.left
                let maximum = max(
                    minimum,
                    collectionView.contentSize.width
                        - collectionView.bounds.width
                        + collectionView.adjustedContentInset.right
                )
                offset.x = min(max(attributes.center.x - collectionView.bounds.midX, minimum), maximum)
            } else {
                let minimum = -collectionView.adjustedContentInset.top
                let maximum = max(
                    minimum,
                    collectionView.contentSize.height
                        - collectionView.bounds.height
                        + collectionView.adjustedContentInset.bottom
                )
                offset.y = min(max(attributes.center.y - collectionView.bounds.midY, minimum), maximum)
            }
            return offset
        }

        private func updateCurrentPage(from scrollView: UIScrollView) {
            guard !isApplyingProgrammaticAlignment, pendingAlignmentIndex == nil else { return }
            let index = min(max(0, visibleIndex(in: scrollView)), max(0, groups.count - 1))
            guard groups.indices.contains(index), let page = groups[index].indices.first else { return }
            if parent.currentPage != page { parent.currentPage = page }
        }

        /// The page itself stays inside UICollectionView's native paging model,
        /// so gesture physics and page accounting remain deterministic. Only the
        /// visible presentation is transformed, which gives a book-like turn
        /// without introducing a second navigation state machine.
        func refreshPageTurnEffects(in scrollView: UIScrollView) {
            guard let collectionView = scrollView as? UICollectionView else { return }
            guard parent.flow == .horizontal, parent.transition == .book else {
                collectionView.visibleCells.forEach { ($0 as? ImagePageCell)?.resetPageTurn() }
                return
            }
            guard collectionView.bounds.width > 0 else { return }

            let viewportWidth = collectionView.bounds.width
            let viewportCenter = collectionView.contentOffset.x + collectionView.bounds.midX
            for cell in collectionView.visibleCells {
                guard let pageCell = cell as? ImagePageCell else { continue }
                let rawProgress = (cell.center.x - viewportCenter) / viewportWidth
                let progress = min(max(rawProgress, -1), 1)
                let magnitude = abs(progress)

                var transform = CATransform3DIdentity
                transform.m34 = -1 / 900
                transform = CATransform3DRotate(transform, -progress * .pi * 0.18, 0, 1, 0)
                transform = CATransform3DScale(
                    transform,
                    1 - magnitude * 0.035,
                    1 - magnitude * 0.018,
                    1
                )
                pageCell.contentView.layer.transform = transform
                pageCell.layer.zPosition = 1_000 - magnitude * 100
                pageCell.updatePageTurn(progress: progress)
            }
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

    static func make(
        urls: [URL],
        layout: ReaderLayout,
        flow: ReaderFlow,
        coverSingle: Bool
    ) -> [ImagePageGroup] {
        guard !urls.isEmpty else { return [] }
        if layout == .single || flow == .continuous {
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
    var usesContinuousItemSizing = false
    private var previousBoundsSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let layout = collectionViewLayout as? UICollectionViewFlowLayout,
              bounds.width > 0,
              bounds.height > 0
        else { return }
        if usesContinuousItemSizing {
            if previousBoundsSize != bounds.size {
                previousBoundsSize = bounds.size
                layout.invalidateLayout()
            }
            return
        }
        guard layout.itemSize != bounds.size else { return }
        layout.itemSize = bounds.size
        layout.invalidateLayout()
    }
}

private final class ImagePageCell: UICollectionViewCell {
    static let reuseIdentifier = "ImagePageCell"
    private let zoomView = ZoomingSpreadScrollView()
    private let pageShadeLayer = CAGradientLayer()

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
        pageShadeLayer.isHidden = true
        contentView.layer.addSublayer(pageShadeLayer)
        contentView.layer.allowsEdgeAntialiasing = true
        layer.allowsEdgeAntialiasing = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        zoomView.clear()
        resetPageTurn()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pageShadeLayer.frame = contentView.bounds
    }

    func configure(urls: [URL], pageLabel: String, backgroundColor: UIColor, onTap: @escaping () -> Void) {
        accessibilityLabel = "第 \(pageLabel) 页"
        zoomView.backgroundColor = backgroundColor
        zoomView.configure(urls: urls, onTap: onTap)
    }

    func updatePageTurn(progress: CGFloat) {
        let magnitude = min(1, abs(progress))
        guard magnitude > 0.002 else {
            resetPageTurn()
            return
        }

        let clear = UIColor.clear.cgColor
        let highlight = UIColor.white.withAlphaComponent(0.20).cgColor
        let shade = UIColor.black.withAlphaComponent(0.58).cgColor
        pageShadeLayer.colors = progress > 0
            ? [clear, highlight, shade]
            : [shade, highlight, clear]
        pageShadeLayer.locations = [0, 0.78, 1]
        pageShadeLayer.startPoint = CGPoint(x: 0, y: 0.5)
        pageShadeLayer.endPoint = CGPoint(x: 1, y: 0.5)
        pageShadeLayer.opacity = Float(pow(magnitude, 0.72))
        pageShadeLayer.isHidden = false

        contentView.layer.shadowColor = UIColor.black.cgColor
        contentView.layer.shadowOpacity = Float(0.28 * magnitude)
        contentView.layer.shadowRadius = 18
        contentView.layer.shadowOffset = CGSize(width: progress > 0 ? -8 : 8, height: 2)
    }

    func resetPageTurn() {
        contentView.layer.transform = CATransform3DIdentity
        contentView.layer.shadowOpacity = 0
        pageShadeLayer.opacity = 0
        pageShadeLayer.isHidden = true
        layer.zPosition = 0
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
    private var readyImageSlots: Set<Int> = []

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
        readyImageSlots = []
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
        readyImageSlots = []
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
            ReaderImagePipeline.shared.loadProgressively(
                URL(fileURLWithPath: path),
                maxPixelSize: target
            ) { [weak self] image, isFinal in
                guard let self,
                      self.loadGeneration == generation,
                      self.representedPaths == paths,
                      self.imageViews.indices.contains(index)
                else { return }

                if let image {
                    self.imageViews[index].image = image
                    let oldSize = self.naturalSizes[index]
                    let oldRatio = oldSize.width / max(oldSize.height, 1)
                    let newRatio = image.size.width / max(image.size.height, 1)
                    if abs(oldRatio - newRatio) > 0.01 {
                        self.naturalSizes[index] = image.size
                        self.needsFit = true
                        self.setNeedsLayout()
                    }
                }
                if image != nil || isFinal {
                    self.readyImageSlots.insert(index)
                }
                if self.readyImageSlots.count >= self.imageViews.count {
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
