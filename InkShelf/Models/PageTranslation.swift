import Foundation

/// Coordinates always describe the upright source image, with a top-left origin.
struct TranslationBox: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        let clipped = rect.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let safe = clipped.isNull ? CGRect.zero : clipped
        x = safe.minX; y = safe.minY; width = safe.width; height = safe.height
    }

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    func pixels(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width, y: y * size.height, width: width * size.width, height: height * size.height)
    }
}

struct TranslationRegion: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var box: TranslationBox
    var source: String
    var translated = ""
    var confidence: Float
    var isVertical: Bool
    var isEdited = false
    var needsReview: Bool { confidence < 0.65 || translated.isEmpty }
}

struct PageTranslationDocument: Codable, Sendable {
    var schema = 1
    var regions: [TranslationRegion]
    var modelID: String?
    var updatedAt = Date()
}

struct TranslationReply: Decodable {
    struct Segment: Decodable { let id: String; let translation: String }
    let segments: [Segment]

    /// Reject unknown and duplicate IDs. Never attach a sentence by array order.
    func validated(for regions: [TranslationRegion]) throws -> [String: String] {
        let allowed = Set(regions.map(\.id))
        var result: [String: String] = [:]
        for segment in segments {
            let value = segment.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard allowed.contains(segment.id), result[segment.id] == nil,
                  !value.isEmpty, value.count <= 4_000 else { throw DeepSeekError.invalidJSON }
            result[segment.id] = value
        }
        guard !result.isEmpty else { throw DeepSeekError.emptyResponse }
        return result
    }
}

enum TranslationDisplayMode: String, CaseIterable, Identifiable {
    case original = "原图"
    case chinese = "中文"
    case comparison = "对照"
    var id: Self { self }
}
