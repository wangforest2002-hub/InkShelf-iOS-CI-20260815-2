import Foundation

/// Vision reports lines, not speech bubbles. Join only nearby, similarly sized
/// lines; keep distant bubbles, small ruby text and manually corrected blocks apart.
enum TranslationParagraphs {
    static func group(_ lines: [TranslationRegion], imageSize: CGSize) -> [TranslationRegion] {
        guard imageSize.width > 0, imageSize.height > 0 else { return lines }
        var parents = Array(lines.indices)
        func root(_ index: Int) -> Int {
            var current = index
            while parents[current] != current { current = parents[current] }
            return current
        }
        // Compare original line thicknesses, not the growing block height.
        for a in lines.indices where !lines[a].isEdited {
            for b in lines.indices where b > a && !lines[b].isEdited {
                if adjacency(lines[a], lines[b], size: imageSize) != nil {
                    let first = root(a), second = root(b)
                    if first != second { parents[second] = first }
                }
            }
        }
        var groups: [Int: [TranslationRegion]] = [:]
        for index in lines.indices { groups[root(index), default: []].append(lines[index]) }
        return ordered(groups.values.map { merge(ordered($0)) })
    }

    static func ordered(_ regions: [TranslationRegion]) -> [TranslationRegion] {
        // Quantize row positions by typical line thickness. This preserves the
        // right-to-left order of Japanese columns with slightly uneven tops.
        let heights = regions.map { $0.box.height }.sorted()
        let row = max(0.015, (heights.isEmpty ? 0.03 : heights[heights.count / 2]) * 0.5)
        return regions.sorted {
            let a = Int(($0.box.y / row).rounded()), b = Int(($1.box.y / row).rounded())
            if a != b { return a < b }
            if $0.box.x != $1.box.x { return $0.box.x > $1.box.x }
            return $0.id < $1.id
        }
    }

    static func merge(_ regions: [TranslationRegion]) -> TranslationRegion {
        precondition(!regions.isEmpty)
        guard regions.count > 1 else { return regions[0] }
        var result = regions[0]
        result.box = TranslationBox(regions.dropFirst().reduce(result.box.rect) { $0.union($1.box.rect) })
        result.source = regions.map(\.source).filter { !$0.isEmpty }.joined(separator: "\n")
        result.translated = regions.map(\.translated).filter { !$0.isEmpty }.joined(separator: "\n")
        result.confidence = regions.map(\.confidence).min() ?? 0
        result.isEdited = regions.contains(where: \.isEdited)
        // Old line translations remain readable, but should be translated again
        // as a paragraph. Never silently discard a user's corrected translation.
        result.needsRetranslation = !result.translated.isEmpty
        return result
    }

    private static func adjacency(_ first: TranslationRegion, _ second: TranslationRegion, size: CGSize) -> CGFloat? {
        guard first.isVertical == second.isVertical else { return nil }
        var a = first.box.pixels(in: size), b = second.box.pixels(in: size)
        if first.isVertical {
            // Rotate axes: columns advance from right to left, text downwards.
            a = CGRect(x: a.minY, y: -a.maxX, width: a.height, height: a.width)
            b = CGRect(x: b.minY, y: -b.maxX, width: b.height, height: b.width)
        }
        if a.minY > b.minY { swap(&a, &b) }
        let thickness = min(a.height, b.height)
        guard thickness > 0, thickness / max(a.height, b.height) >= 0.7 else { return nil }
        let gap = b.minY - a.maxY
        let overlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let alignment = min(abs(a.minX - b.minX), abs(a.midX - b.midX), abs(a.maxX - b.maxX))
        guard gap >= -thickness * 0.2, gap <= thickness * 0.85,
              overlap >= min(a.width, b.width) * 0.55, alignment <= thickness * 0.85 else { return nil }
        return max(0, gap) / thickness + alignment / thickness
    }
}

/// Both page context and targets are data, never instructions. Context is scoped
/// to the current image and bounded, prioritizing neighboring paragraphs.
struct TranslationRequestInput: Encodable {
    struct Paragraph: Encodable {
        let id: String
        let text: String
        let previousTranslation: String?
        let uncertainOCR: Bool
        init(_ region: TranslationRegion) {
            id = region.id; text = region.source
            previousTranslation = region.translated.isEmpty || region.needsRetranslation == true ? nil : region.translated
            uncertainOCR = region.confidence < 0.65
        }
    }
    let targets: [Paragraph]
    let context: [Paragraph]

    init(targets: [TranslationRegion], page: [TranslationRegion], contextBudget: Int = 12_000) {
        self.targets = targets.map(Paragraph.init)
        let targetIDs = Set(targets.map(\.id))
        let indices = page.indices.filter { targetIDs.contains(page[$0].id) }
        let nearby = page.indices.filter { !targetIDs.contains(page[$0].id) }.sorted { first, second in
            let a = indices.map { abs(first - $0) }.min() ?? first
            let b = indices.map { abs(second - $0) }.min() ?? second
            return a == b ? first < second : a < b
        }
        var remaining = max(0, contextBudget)
        var accepted: Set<Int> = []
        for index in nearby {
            let region = page[index]
            let cost = region.source.count + (region.needsRetranslation == true ? 0 : region.translated.count)
            if cost <= remaining { accepted.insert(index); remaining -= cost }
        }
        context = page.indices.filter { accepted.contains($0) }.map { Paragraph(page[$0]) }
    }
}
