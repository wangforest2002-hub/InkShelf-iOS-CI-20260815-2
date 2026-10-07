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
        if mode != .original && !selecting {
            for (index, region) in regions.enumerated() {
                let button = TranslationRegionButton(type: .custom)
                let box = region.box.pixels(in: image.size)
                let fittedFont = TranslationTypography.font(for: region.translated, in: box.size, imageWidth: image.size.width)
                let showText = mode == .chinese && !region.translated.isEmpty && fittedFont != nil
                let fontSize = max(30, image.size.width * 0.026)
                let title = showText ? region.translated : "\(index + 1)"
                button.setTitle(title, for: .normal)
                button.titleLabel?.font = showText ? fittedFont : .systemFont(ofSize: fontSize, weight: .medium)
                button.titleLabel?.numberOfLines = showText ? 0 : 1
                button.titleLabel?.adjustsFontSizeToFitWidth = false
                button.titleLabel?.lineBreakMode = .byTruncatingTail
                button.backgroundColor = showText ? .white : UIColor.systemBlue.withAlphaComponent(0.88)
                button.setTitleColor(showText ? .black : .white, for: .normal)
                let badgeSide = fontSize * 1.8
                button.frame = showText ? box : CGRect(x: box.minX, y: box.minY, width: badgeSide, height: badgeSide)
                button.layer.cornerRadius = 6
                button.layer.borderWidth = region.id == selectedID ? 6 : 2
                button.layer.borderColor = (region.id == selectedID ? UIColor.systemOrange : UIColor.systemBlue).cgColor
                button.accessibilityLabel = "区域 \(index + 1)，\(region.translated.isEmpty ? region.source : region.translated)"
                button.accessibilityHint = "点按查看原文与完整译文"
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
        // Keep small numbered regions tappable even while the full page is fitted.
        let scale = max(0.01, abs(superview?.transform.a ?? 1))
        let minimumSide = 44 / scale
        return bounds.insetBy(dx: min(0, (bounds.width - minimumSide) / 2),
                              dy: min(0, (bounds.height - minimumSide) / 2)).contains(point)
    }
}

enum TranslationTypography {
    static func font(for text: String, in size: CGSize, imageWidth: CGFloat) -> UIFont? {
        guard !text.isEmpty, size.width > 12, size.height > 12 else { return nil }
        let minimum = max(22, imageWidth * 0.022)
        var pointSize = max(minimum, imageWidth * 0.036)
        while pointSize >= minimum {
            let font = UIFont.systemFont(ofSize: pointSize, weight: .medium)
            let bounds = (text as NSString).boundingRect(
                with: CGSize(width: size.width - 12, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil
            )
            if ceil(bounds.height) <= size.height - 12 { return font }
            pointSize -= 2
        }
        return nil
    }
}
