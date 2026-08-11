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

    fileprivate var groups: [ImagePageGroup] {
        ImagePageGroup.make(urls: imageURLs, layout: layout, coverSingle: coverSingle)
    }

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
        collectionView.isPagingEnabled = true
        collectionView.decelerationRate = .fast
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = flow == .horizontal
        collectionView.alwaysBounceVertical = flow == .vertical
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(ImagePageCell.self, forCellWithReuseIdentifier: ImagePageCell.reuseIdentifier)
        collectionView.semanticContentAttribute = order == .rightToLeft && flow == .horizontal ? .forceRightToLeft : .forceLeftToRight
        context.coordinator.configurationKey = configurationKey
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

        if context.coordinator.configurationKey != configurationKey {
            context.coordinator.configurationKey = configurationKey
            collectionView.reloadData()
        }

        let target = groups.firstIndex { $0.indices.contains(currentPage) } ?? 0
        guard !groups.isEmpty,
              !collectionView.isDragging,
              !collectionView.isDecelerating,
              context.coordinator.visibleIndex(in: collectionView) != target
        else { return }

        DispatchQueue.main.async {
            guard target < collectionView.numberOfItems(inSection: 0) else { return }
            collectionView.scrollToItem(at: IndexPath(item: target, section: 0), at: self.flow == .horizontal ? .centeredHorizontally : .centeredVertically, animated: false)
        }
    }

    private var configurationKey: String {
        "\(imageURLs.map(\.path).joined(separator: "|"))-\(layout.rawValue)-\(flow.rawValue)-\(order.rawValue)-\(coverSingle)"
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UIScrollViewDelegate {
        var parent: ImagePagerView
        var configurationKey = ""

        init(parent: ImagePagerView) {
            self.parent = parent
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.groups.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ImagePageCell.reuseIdentifier,
                for: indexPath
            ) as? ImagePageCell else {
                return UICollectionViewCell()
            }

            let group = parent.groups[indexPath.item]
            let urls: [URL] = parent.order == .rightToLeft ? Array(group.urls.reversed()) : group.urls
            cell.configure(
                urls: urls,
                pageLabel: group.indices.map { String($0 + 1) }.joined(separator: "、"),
                backgroundColor: parent.backgroundColor,
                onTap: parent.onTap
            )
            return cell
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            updateCurrentPage(from: scrollView)
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
            let index = min(max(0, visibleIndex(in: scrollView)), max(0, parent.groups.count - 1))
            guard index < parent.groups.count, let page = parent.groups[index].indices.first else { return }
            if parent.currentPage != page {
                parent.currentPage = page
            }
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
        if let layout = collectionViewLayout as? UICollectionViewFlowLayout,
           bounds.size.width > 0,
           bounds.size.height > 0,
           layout.itemSize != bounds.size {
            layout.itemSize = bounds.size
            layout.invalidateLayout()
        }
        super.layoutSubviews()
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
    private var imageViews: [UIImageView] = []
    private var representedPaths: [String] = []
    private var tapAction: (() -> Void)?
    private var needsFit = true
    private var lastBoundsSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        delaysContentTouches = false
        addSubview(canvas)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(urls: [URL], onTap: @escaping () -> Void) {
        tapAction = onTap
        let paths = urls.map(\.path)
        guard paths != representedPaths else { return }
        representedPaths = paths

        imageViews.forEach { $0.removeFromSuperview() }
        imageViews = urls.compactMap { url in
            guard let image = UIImage(contentsOfFile: url.path) else { return nil }
            let view = UIImageView(image: image)
            view.contentMode = .scaleAspectFit
            view.clipsToBounds = true
            canvas.addSubview(view)
            return view
        }
        needsFit = true
        setNeedsLayout()
    }

    func clear() {
        representedPaths = []
        tapAction = nil
        imageViews.forEach { $0.removeFromSuperview() }
        imageViews = []
        zoomScale = 1
        contentOffset = .zero
        needsFit = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !imageViews.isEmpty, bounds.width > 0, bounds.height > 0 else { return }
        guard needsFit || lastBoundsSize != bounds.size else {
            centerCanvas()
            return
        }

        lastBoundsSize = bounds.size
        needsFit = false
        let sizes = imageViews.map { view -> CGSize in
            guard let image = view.image else { return CGSize(width: 1, height: 1) }
            return CGSize(
                width: max(image.size.width * image.scale, 1),
                height: max(image.size.height * image.scale, 1)
            )
        }
        let canvasHeight = max(sizes.map(\.height).max() ?? 1, 1)
        let widths = sizes.map { max(1, $0.width / max($0.height, 1) * canvasHeight) }
        let gap = imageViews.count > 1 ? max(12, canvasHeight * 0.004) : 0
        let canvasSize = CGSize(width: widths.reduce(0, +) + gap, height: canvasHeight)

        canvas.frame = CGRect(origin: .zero, size: canvasSize)
        var x: CGFloat = 0
        for (index, imageView) in imageViews.enumerated() {
            imageView.frame = CGRect(x: x, y: 0, width: widths[index], height: canvasHeight)
            x += widths[index] + gap
        }
        contentSize = canvasSize

        let horizontalFit = bounds.width / canvasSize.width
        let verticalFit = bounds.height / canvasSize.height
        let fitScale = min(horizontalFit, verticalFit)
        minimumZoomScale = fitScale
        maximumZoomScale = max(fitScale * 10, 2)
        zoomScale = fitScale
        panGestureRecognizer.isEnabled = false
        centerCanvas()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        canvas
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        panGestureRecognizer.isEnabled = zoomScale > minimumZoomScale + 0.01
        centerCanvas()
    }

    private func centerCanvas() {
        let horizontalInset = max(0, (bounds.width - contentSize.width * zoomScale) / 2)
        let verticalInset = max(0, (bounds.height - contentSize.height * zoomScale) / 2)
        contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
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
        let zoomRect = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
        zoom(to: zoomRect, animated: true)
    }
}
