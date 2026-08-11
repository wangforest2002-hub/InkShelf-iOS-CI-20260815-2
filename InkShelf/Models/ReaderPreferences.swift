import SwiftUI

enum ReaderLayout: String, CaseIterable, Identifiable {
    case single
    case spread

    var id: String { rawValue }
    var title: String { self == .single ? "单页" : "双页" }
    var systemImage: String { self == .single ? "rectangle.portrait" : "rectangle.split.2x1" }
}

enum ReaderFlow: String, CaseIterable, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }
    var title: String { self == .horizontal ? "横向翻页" : "纵向翻页" }
    var systemImage: String { self == .horizontal ? "arrow.left.and.right" : "arrow.up.and.down" }
}

enum ReadingOrder: String, CaseIterable, Identifiable {
    case leftToRight
    case rightToLeft

    var id: String { rawValue }
    var title: String { self == .leftToRight ? "从左到右" : "从右到左（日漫）" }
    var systemImage: String { self == .leftToRight ? "text.alignleft" : "text.alignright" }
}

enum ReaderBackdrop: String, CaseIterable, Identifiable {
    case black
    case graphite
    case paper

    var id: String { rawValue }
    var title: String {
        switch self {
        case .black: "纯黑"
        case .graphite: "石墨"
        case .paper: "纸张"
        }
    }

    var color: Color {
        switch self {
        case .black: .black
        case .graphite: Color(red: 0.055, green: 0.06, blue: 0.075)
        case .paper: Color(red: 0.93, green: 0.91, blue: 0.87)
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

