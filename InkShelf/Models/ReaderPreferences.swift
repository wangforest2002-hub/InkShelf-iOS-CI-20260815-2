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

enum EBookFlow: String, CaseIterable, Identifiable {
    case paged
    case scroll

    var id: String { rawValue }
    var title: String { self == .paged ? "左右翻页" : "纵向滚动" }
    var systemImage: String { self == .paged ? "book.pages" : "scroll" }
}

enum EBookTheme: String, CaseIterable, Identifiable {
    case paper
    case sepia
    case night

    var id: String { rawValue }
    var title: String {
        switch self {
        case .paper: "纸白"
        case .sepia: "护眼"
        case .night: "夜间"
        }
    }

    var backgroundHex: String {
        switch self {
        case .paper: "#FAFAF7"
        case .sepia: "#F2E8D2"
        case .night: "#101116"
        }
    }

    var foregroundHex: String {
        switch self {
        case .paper: "#202126"
        case .sepia: "#3C3128"
        case .night: "#E8E6E3"
        }
    }

    var color: Color {
        switch self {
        case .paper: Color(red: 0.98, green: 0.98, blue: 0.97)
        case .sepia: Color(red: 0.95, green: 0.91, blue: 0.82)
        case .night: Color(red: 0.06, green: 0.067, blue: 0.085)
        }
    }
}

enum EBookFont: String, CaseIterable, Identifiable {
    case system
    case serif
    case rounded

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "系统黑体"
        case .serif: "阅读宋体"
        case .rounded: "圆润"
        }
    }

    var cssFamily: String {
        switch self {
        case .system: "-apple-system, BlinkMacSystemFont, sans-serif"
        case .serif: "New York, Songti SC, STSong, serif"
        case .rounded: "ui-rounded, PingFang SC, sans-serif"
        }
    }
}
