import Foundation

enum LibraryScope: String, Equatable, Sendable {
    case all
    case recent
    case favorites
}

enum LibrarySortOrder: String, CaseIterable, Identifiable, Sendable {
    case lastOpened
    case importedNewest
    case title
    case progress
    case fileSize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastOpened: "最近阅读"
        case .importedNewest: "最近导入"
        case .title: "标题"
        case .progress: "阅读进度"
        case .fileSize: "占用空间"
        }
    }

    var systemImage: String {
        switch self {
        case .lastOpened: "clock.arrow.circlepath"
        case .importedNewest: "tray.and.arrow.down.fill"
        case .title: "textformat.abc"
        case .progress: "chart.bar.fill"
        case .fileSize: "internaldrive.fill"
        }
    }
}

enum ReadingStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case unread
    case reading
    case finished

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部状态"
        case .unread: "尚未开始"
        case .reading: "正在阅读"
        case .finished: "已经读完"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "line.3.horizontal.decrease.circle"
        case .unread: "circle.dashed"
        case .reading: "book.pages.fill"
        case .finished: "checkmark.circle.fill"
        }
    }
}

enum LibraryGridDensity: String, CaseIterable, Identifiable, Sendable {
    case comfortable
    case compact

    var id: String { rawValue }
    var title: String { self == .comfortable ? "舒展封面" : "紧凑封面" }
    var systemImage: String { self == .comfortable ? "rectangle.grid.2x2" : "rectangle.grid.3x2" }
}

enum BookReadingStatus: String, Sendable {
    case unread
    case reading
    case finished
}

extension Book {
    var readingStatus: BookReadingStatus {
        guard lastOpenedAt != nil else { return .unread }
        return progress >= 0.999 ? .finished : .reading
    }

    func matchesLibrarySearch(_ query: String) -> Bool {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else { return true }
        let searchable = ([title, sourceFileName, kind.label, personalNote ?? ""] + normalizedTags)
            .joined(separator: "\n")
        return terms.allSatisfy { searchable.localizedCaseInsensitiveContains($0) }
    }
}

struct LibraryQuery: Sendable {
    var scope: LibraryScope
    var searchText: String
    var sortOrder: LibrarySortOrder
    var status: ReadingStatusFilter

    func apply(to books: [Book]) -> [Book] {
        books
            .filter(matchesScope)
            .filter { status == .all || $0.readingStatus.rawValue == status.rawValue }
            .filter { $0.matchesLibrarySearch(searchText) }
            .sorted(by: isOrderedBefore)
    }

    private func matchesScope(_ book: Book) -> Bool {
        switch scope {
        case .all: true
        case .recent: book.lastOpenedAt != nil
        case .favorites: book.isFavorite
        }
    }

    private func isOrderedBefore(_ left: Book, _ right: Book) -> Bool {
        let fallback = left.title.localizedStandardCompare(right.title) == .orderedAscending
        switch sortOrder {
        case .lastOpened:
            let lhs = left.lastOpenedAt ?? left.importedAt
            let rhs = right.lastOpenedAt ?? right.importedAt
            return lhs == rhs ? fallback : lhs > rhs
        case .importedNewest:
            return left.importedAt == right.importedAt ? fallback : left.importedAt > right.importedAt
        case .title:
            return fallback
        case .progress:
            return left.progress == right.progress ? fallback : left.progress > right.progress
        case .fileSize:
            return left.fileSize == right.fileSize ? fallback : left.fileSize > right.fileSize
        }
    }
}
