import Foundation

enum AchievementMetric: String, Codable, Sendable {
    case booksOpened
    case pagesTurned
    case booksCompleted
    case minutesRead
    case pagesSaved
    case pagesFavorited
}

struct ReadingAchievement: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let metric: AchievementMetric
    let target: Int

    static let all: [ReadingAchievement] = [
        .init(id: "first-home", title: "第一次回家", detail: "翻开第一本属于你的小家藏书", systemImage: "house.fill", metric: .booksOpened, target: 1),
        .init(id: "page-spark", title: "一页入心", detail: "珍藏第一张喜欢的画面", systemImage: "heart.fill", metric: .pagesFavorited, target: 1),
        .init(id: "first-finale", title: "看到最后", detail: "第一次读完一本画册或故事", systemImage: "flag.checkered", metric: .booksCompleted, target: 1),
        .init(id: "fifty-pages", title: "翻页学徒", detail: "累计翻过 50 页", systemImage: "book.pages.fill", metric: .pagesTurned, target: 50),
        .init(id: "warm-hour", title: "暖灯常亮", detail: "累计阅读 60 分钟", systemImage: "lamp.table.fill", metric: .minutesRead, target: 60),
        .init(id: "light-collector", title: "光影收藏家", detail: "把 5 张喜欢的画面保存到照片", systemImage: "photo.stack.fill", metric: .pagesSaved, target: 5),
        .init(id: "ten-books", title: "小家常客", detail: "累计翻开 10 本不同读物", systemImage: "books.vertical.fill", metric: .booksOpened, target: 10),
        .init(id: "thousand-pages", title: "千页旅人", detail: "累计翻过 1000 页", systemImage: "sparkles.rectangle.stack.fill", metric: .pagesTurned, target: 1_000)
    ]
}

struct ReadingFootprint: Codable, Sendable {
    var openedBookIDs: Set<UUID> = []
    var completedBookIDs: Set<UUID> = []
    var pagesTurned = 0
    var readingSeconds: TimeInterval = 0
    var pagesSaved = 0
    var pagesFavorited = 0
    var unlockedAt: [String: Date] = [:]
}
