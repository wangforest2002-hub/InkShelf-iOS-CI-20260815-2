import Foundation

/// A single source of truth for the page label, scrubber and spread anchor.
/// Stored progress remains a zero-based physical page so old libraries keep
/// working, while the UI can accurately describe a one- or two-page spread.
struct ReaderPagePosition: Equatable, Sendable {
    let currentPage: Int
    let pageCount: Int
    let layout: ReaderLayout
    let flow: ReaderFlow
    let coverSingle: Bool
    let isEBook: Bool

    private var lastPage: Int { max(0, pageCount - 1) }
    var clampedPage: Int { min(max(0, currentPage), lastPage) }

    var visibleRange: ClosedRange<Int> {
        guard !isEBook, layout == .spread, flow != .continuous else {
            return clampedPage...clampedPage
        }
        if coverSingle, clampedPage == 0 { return 0...0 }

        let firstPairedPage = coverSingle ? 1 : 0
        let distance = max(0, clampedPage - firstPairedPage)
        let lower = firstPairedPage + (distance / 2) * 2
        return lower...min(lower + 1, lastPage)
    }

    var anchorPage: Int { visibleRange.lowerBound }

    var displayLabel: String {
        let unit = isEBook ? "章" : "页"
        if visibleRange.lowerBound == visibleRange.upperBound {
            return "第 \(visibleRange.lowerBound + 1) \(unit) · 共 \(pageCount) \(unit)"
        }
        return "第 \(visibleRange.lowerBound + 1)–\(visibleRange.upperBound + 1) 页 · 共 \(pageCount) 页"
    }

    var accessibilityValue: String {
        displayLabel.replacingOccurrences(of: " · ", with: "，")
    }

    var sliderUpperBound: Double {
        isEBook ? Double(max(pageCount, 1)) : Double(max(lastPage, 1))
    }

    func sliderValue(ebookProgress: Double) -> Double {
        if isEBook {
            return min(
                max(Double(clampedPage) + min(max(ebookProgress, 0), 1), 0),
                Double(max(pageCount, 1))
            )
        }
        // A spread is complete when its trailing physical page is visible.
        // Returning the upper bound keeps the thumb at 100% on the final
        // two-page spread instead of making it jump backward to its anchor.
        return Double(visibleRange.upperBound)
    }

    func progressPercentage(ebookProgress: Double) -> Int {
        guard pageCount > 0 else { return 0 }
        let fraction: Double
        if isEBook {
            fraction = sliderValue(ebookProgress: ebookProgress) / Double(pageCount)
        } else {
            fraction = Double(visibleRange.upperBound + 1) / Double(pageCount)
        }
        return min(max(Int((fraction * 100).rounded()), 0), 100)
    }

    func comicPage(forSliderValue value: Double) -> Int {
        let requested = min(max(Int(value.rounded()), 0), lastPage)
        return ReaderPagePosition(
            currentPage: requested,
            pageCount: pageCount,
            layout: layout,
            flow: flow,
            coverSingle: coverSingle,
            isEBook: false
        ).anchorPage
    }

    func ebookTarget(forSliderValue value: Double) -> (chapter: Int, progress: Double) {
        guard pageCount > 0 else { return (0, 0) }
        let bounded = min(max(value, 0), Double(pageCount))
        if bounded >= Double(pageCount) { return (pageCount - 1, 1) }
        let chapter = min(max(Int(bounded.rounded(.down)), 0), pageCount - 1)
        return (chapter, min(max(bounded - Double(chapter), 0), 1))
    }
}
