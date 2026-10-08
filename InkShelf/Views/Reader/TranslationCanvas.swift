import SwiftUI
import UIKit

struct TranslationCanvas: UIViewRepresentable {
    let image: UIImage
    let regions: [TranslationRegion]
    let mode: TranslationDisplayMode
    let selectedID: String?
    let isSelecting: Bool
    let onSelect: (String) -> Void
    let onRegion: (TranslationBox) -> Void

    func makeUIView(context: Context) -> TranslationScrollView { TranslationScrollView() }
    func updateUIView(_ view: TranslationScrollView, context: Context) {
        view.configure(image: image, regions: regions, mode: mode, selectedID: selectedID,
                       selecting: isSelecting, onSelect: onSelect, onRegion: onRegion)
    }
}

final class TranslationScrollView: UIScrollView, UIScrollViewDelegate {
    private let page = UIImageView()
    private let selectionLayer = CAShapeLayer()
    private var regionButtons: [UIButton] = []
    private var startPoint: CGPoint?
    private var previousBounds = CGSize.zero
    private var selectionID: String?
    private var onSelect: ((String) -> Void)?
    private var onRegion: ((TranslationBox) -> Void)?
    private lazy var selectionPan = UIPanGestureRecognizer(target: self, action: #selector(selectRegion(_:)))

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = UIColor(red: 0.055, green: 0.055, blue: 0.075, alpha: 1)
        showsVerticalScrollIndicator = false; showsHorizontalScrollIndicator = false
        maximumZoomScale = 5; bouncesZoom = true
        page.isUserInteractionEnabled = true
        page.contentMode = .scaleToFill
        addSubview(page)
        selectionLayer.strokeColor = UIColor.systemCyan.cgColor
        selectionLayer.fillColor = UIColor.systemCyan.withAlphaComponent(0.15).cgColor
        selectionLayer.lineWidth = 4
        page.layer.addSublayer(selectionLayer)
        page.addGestureRecognizer(selectionPan)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        accessibilityIdentifier = "translation-canvas"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(image: UIImage, regions: [TranslationRegion], mode: TranslationDisplayMode,
                   selectedID: String?, selecting: Bool, onSelect: @escaping (String) -> Void,
                   onRegion: @escaping (TranslationBox) -> Void) {
        self.onSelect = onSelect; self.onRegion = onRegion
        if page.image !== image {
            zoomScale = 1
            page.image = image
            page.frame = CGRect(origin: .zero, size: image.size)
            contentSize = image.size
            previousBounds = .zero
        }
        selectionPan.isEnabled = selecting
        panGestureRecognizer.isEnabled = !selecting
        pinchGestureRecognizer?.isEnabled = !selecting
        for button in regionButtons { button.removeFromSuperview() }
        regionButtons.removeAll()
        if !selecting {
            for (index, region) in regions.enumerated() {
                let button = TranslationRegionButton(type: .custom)
                let box = region.box.pixels(in: image.size)
                let selected = region.id == selectedID
                button.frame = box
                // The image remains intact. Full translations live in a readable
                // sheet and the page transcript, independent of OCR box size.
                button.backgroundColor = selected ? UIColor.systemOrange.withAlphaComponent(0.16)
                    : mode == .original ? .clear : UIColor.systemBlue.withAlphaComponent(0.06)
                button.layer.cornerRadius = 8
                button.layer.borderWidth = mode == .original && !selected ? 0 : selected ? 5 : 2
                button.layer.borderColor = (selected ? UIColor.systemOrange : UIColor.systemBlue).cgColor
                button.accessibilityLabel = "段落 \(index + 1)，\(region.source)"
                button.accessibilityHint = "点按查看此段的完整中文翻译"
                button.accessibilityIdentifier = "translation-region-\(region.id)"
                button.addAction(UIAction { [weak self] _ in self?.onSelect?(region.id) }, for: .touchUpInside)
                page.addSubview(button); regionButtons.append(button)
            }
        }
        layoutIfNeeded()
        if selectedID != selectionID, let region = regions.first(where: { $0.id == selectedID }) {
            let rect = region.box.pixels(in: image.size)
            scrollRectToVisible(page.convert(rect, to: self).insetBy(dx: -18, dy: -18), animated: !UIAccessibility.isReduceMotionEnabled)
        }
        selectionID = selectedID
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image = page.image, bounds.width > 0, bounds.height > 0 else { return }
        if bounds.size != previousBounds {
            let fitted = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let wasFitted = previousBounds == .zero || abs(zoomScale - minimumZoomScale) < 0.02
            minimumZoomScale = fitted
            maximumZoomScale = max(4, fitted * 6)
            previousBounds = bounds.size
            if wasFitted { zoomScale = fitted }
        }
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { page }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { setNeedsLayout() }

    @objc private func selectRegion(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: page)
        if gesture.state == .began { startPoint = point }
        guard let startPoint else { return }
        let rect = CGRect(x: min(startPoint.x, point.x), y: min(startPoint.y, point.y),
                          width: abs(startPoint.x - point.x), height: abs(startPoint.y - point.y))
            .intersection(page.bounds)
        selectionLayer.path = UIBezierPath(rect: rect.isNull ? .zero : rect).cgPath
        if gesture.state == .ended {
            selectionLayer.path = nil; self.startPoint = nil
            guard !rect.isNull, rect.width * zoomScale > 12, rect.height * zoomScale > 12 else { return }
            onRegion?(TranslationBox(CGRect(x: rect.minX / page.bounds.width, y: rect.minY / page.bounds.height,
                                           width: rect.width / page.bounds.width, height: rect.height / page.bounds.height)))
        } else if gesture.state == .cancelled || gesture.state == .failed {
            selectionLayer.path = nil; self.startPoint = nil
        }
    }

    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        guard !selectionPan.isEnabled else { return }
        if zoomScale > minimumZoomScale * 1.2 { setZoomScale(minimumZoomScale, animated: !UIAccessibility.isReduceMotionEnabled) }
        else {
            let point = gesture.location(in: page)
            let scale = min(maximumZoomScale, minimumZoomScale * 2.5)
            zoom(to: CGRect(x: point.x - bounds.width / scale / 2, y: point.y - bounds.height / scale / 2,
                            width: bounds.width / scale, height: bounds.height / scale), animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }
}

private final class TranslationRegionButton: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Keep small paragraph regions tappable even while the full page is fitted.
        let scale = max(0.01, abs(superview?.transform.a ?? 1))
        let minimumSide = 44 / scale
        return bounds.insetBy(dx: min(0, (bounds.width - minimumSide) / 2),
                              dy: min(0, (bounds.height - minimumSide) / 2)).contains(point)
    }
}
