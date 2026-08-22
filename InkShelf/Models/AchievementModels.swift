import Foundation

enum AchievementMetric: String, Codable, Sendable {
    case booksOpened
    case homeVisits
    case pagesTurned
    case booksCompleted
    case minutesRead
    case pagesSaved
    case pagesFavorited
    case readingStreak
}

enum AchievementTier: String, CaseIterable, Sendable {
    case cozy
    case shining
    case rare
    case legendary

    var title: String {
        switch self {
        case .cozy: "暖心"
        case .shining: "闪耀"
        case .rare: "珍稀"
        case .legendary: "传说"
        }
    }
}

struct ReadingAchievement: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let metric: AchievementMetric
    let target: Int
    let tier: AchievementTier

    static let all: [ReadingAchievement] = [
        .init(id: "first-home", title: "第一次回家", detail: "翻开第一本属于你的小家藏书", systemImage: "house.fill", metric: .booksOpened, target: 1, tier: .cozy),
        .init(id: "welcome-back", title: "我又回来啦", detail: "累计回到阅读小家 5 次", systemImage: "door.left.hand.open", metric: .homeVisits, target: 5, tier: .cozy),
        .init(id: "page-spark", title: "一页入心", detail: "珍藏第一张喜欢的画面", systemImage: "heart.fill", metric: .pagesFavorited, target: 1, tier: .cozy),
        .init(id: "first-finale", title: "看到最后", detail: "第一次读完一本画册或故事", systemImage: "flag.checkered", metric: .booksCompleted, target: 1, tier: .cozy),
        .init(id: "fifty-pages", title: "翻页学徒", detail: "累计翻过 50 页", systemImage: "book.pages.fill", metric: .pagesTurned, target: 50, tier: .cozy),
        .init(id: "three-day-lamp", title: "三日暖灯", detail: "连续 3 天回家阅读", systemImage: "flame.fill", metric: .readingStreak, target: 3, tier: .shining),
        .init(id: "heart-album", title: "心动画册", detail: "累计珍藏 10 张喜欢的画面", systemImage: "heart.text.square.fill", metric: .pagesFavorited, target: 10, tier: .shining),
        .init(id: "warm-hour", title: "暖灯常亮", detail: "累计阅读 60 分钟", systemImage: "lamp.table.fill", metric: .minutesRead, target: 60, tier: .shining),
        .init(id: "light-collector", title: "光影收藏家", detail: "把 5 张喜欢的画面保存到照片", systemImage: "photo.stack.fill", metric: .pagesSaved, target: 5, tier: .shining),
        .init(id: "ten-books", title: "小家常客", detail: "累计翻开 10 本不同读物", systemImage: "books.vertical.fill", metric: .booksOpened, target: 10, tier: .shining),
        .init(id: "three-hundred-pages", title: "纸间散步", detail: "累计翻过 300 页", systemImage: "figure.walk.motion", metric: .pagesTurned, target: 300, tier: .shining),
        .init(id: "five-finales", title: "故事收藏者", detail: "认真读完 5 本读物", systemImage: "checkmark.seal.fill", metric: .booksCompleted, target: 5, tier: .rare),
        .init(id: "seven-day-window", title: "窗边七日", detail: "连续 7 天留下阅读足迹", systemImage: "calendar.badge.checkmark", metric: .readingStreak, target: 7, tier: .rare),
        .init(id: "five-hours", title: "午后不散场", detail: "累计阅读 5 小时", systemImage: "cup.and.saucer.fill", metric: .minutesRead, target: 300, tier: .rare),
        .init(id: "twenty-saves", title: "私人美术馆", detail: "保存 20 张让你停留的画面", systemImage: "photo.artframe", metric: .pagesSaved, target: 20, tier: .rare),
        .init(id: "thirty-visits", title: "熟悉的门铃", detail: "累计回到阅读小家 30 次", systemImage: "bell.and.waves.left.and.right.fill", metric: .homeVisits, target: 30, tier: .rare),
        .init(id: "thousand-pages", title: "千页旅人", detail: "累计翻过 1000 页", systemImage: "sparkles.rectangle.stack.fill", metric: .pagesTurned, target: 1_000, tier: .rare),
        .init(id: "thirty-books", title: "藏书屋主人", detail: "翻开 30 本不同的读物", systemImage: "house.and.flag.fill", metric: .booksOpened, target: 30, tier: .legendary),
        .init(id: "fifty-hearts", title: "怦然心动档案", detail: "珍藏 50 张独一无二的画面", systemImage: "heart.circle.fill", metric: .pagesFavorited, target: 50, tier: .legendary),
        .init(id: "twenty-finales", title: "片尾仍有灯", detail: "完整读完 20 本读物", systemImage: "movieclapper.fill", metric: .booksCompleted, target: 20, tier: .legendary),
        .init(id: "thirty-day-home", title: "月光住客", detail: "连续 30 天回家阅读", systemImage: "moon.stars.fill", metric: .readingStreak, target: 30, tier: .legendary),
        .init(id: "thirty-hours", title: "时光藏书票", detail: "累计阅读 30 小时", systemImage: "clock.badge.checkmark.fill", metric: .minutesRead, target: 1_800, tier: .legendary),
        .init(id: "five-thousand-pages", title: "万象书海", detail: "累计翻过 5000 页", systemImage: "water.waves.and.arrow.trianglehead.up", metric: .pagesTurned, target: 5_000, tier: .legendary)
    ]
}

struct DailyReadingQuest: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let value: Int
    let target: Int

    var isCompleted: Bool { value >= target }
}

struct ReadingFootprint: Codable, Sendable {
    var openedBookIDs: Set<UUID>
    var completedBookIDs: Set<UUID>
    var pagesTurned: Int
    var readingSeconds: TimeInterval
    var pagesSaved: Int
    var pagesFavorited: Int
    var unlockedAt: [String: Date]
    var homeVisits: Int
    var readingDayKeys: Set<String>
    var pageTurnsByDay: [String: Int]
    var readingSecondsByDay: [String: TimeInterval]
    var longestReadingStreak: Int

    init(
        openedBookIDs: Set<UUID> = [],
        completedBookIDs: Set<UUID> = [],
        pagesTurned: Int = 0,
        readingSeconds: TimeInterval = 0,
        pagesSaved: Int = 0,
        pagesFavorited: Int = 0,
        unlockedAt: [String: Date] = [:],
        homeVisits: Int = 0,
        readingDayKeys: Set<String> = [],
        pageTurnsByDay: [String: Int] = [:],
        readingSecondsByDay: [String: TimeInterval] = [:],
        longestReadingStreak: Int = 0
    ) {
        self.openedBookIDs = openedBookIDs
        self.completedBookIDs = completedBookIDs
        self.pagesTurned = pagesTurned
        self.readingSeconds = readingSeconds
        self.pagesSaved = pagesSaved
        self.pagesFavorited = pagesFavorited
        self.unlockedAt = unlockedAt
        self.homeVisits = homeVisits
        self.readingDayKeys = readingDayKeys
        self.pageTurnsByDay = pageTurnsByDay
        self.readingSecondsByDay = readingSecondsByDay
        self.longestReadingStreak = longestReadingStreak
    }

    private enum CodingKeys: String, CodingKey {
        case openedBookIDs, completedBookIDs, pagesTurned, readingSeconds
        case pagesSaved, pagesFavorited, unlockedAt, homeVisits, readingDayKeys
        case pageTurnsByDay, readingSecondsByDay, longestReadingStreak
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        openedBookIDs = try values.decodeIfPresent(Set<UUID>.self, forKey: .openedBookIDs) ?? []
        completedBookIDs = try values.decodeIfPresent(Set<UUID>.self, forKey: .completedBookIDs) ?? []
        pagesTurned = try values.decodeIfPresent(Int.self, forKey: .pagesTurned) ?? 0
        readingSeconds = try values.decodeIfPresent(TimeInterval.self, forKey: .readingSeconds) ?? 0
        pagesSaved = try values.decodeIfPresent(Int.self, forKey: .pagesSaved) ?? 0
        pagesFavorited = try values.decodeIfPresent(Int.self, forKey: .pagesFavorited) ?? 0
        unlockedAt = try values.decodeIfPresent([String: Date].self, forKey: .unlockedAt) ?? [:]
        homeVisits = try values.decodeIfPresent(Int.self, forKey: .homeVisits) ?? 0
        readingDayKeys = try values.decodeIfPresent(Set<String>.self, forKey: .readingDayKeys) ?? []
        pageTurnsByDay = try values.decodeIfPresent([String: Int].self, forKey: .pageTurnsByDay) ?? [:]
        readingSecondsByDay = try values.decodeIfPresent([String: TimeInterval].self, forKey: .readingSecondsByDay) ?? [:]
        longestReadingStreak = try values.decodeIfPresent(Int.self, forKey: .longestReadingStreak) ?? 0
    }
}
