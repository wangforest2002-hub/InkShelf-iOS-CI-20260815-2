import Foundation
import Observation

@MainActor
@Observable
final class AchievementStore {
    private(set) var footprint: ReadingFootprint
    private(set) var latestUnlock: ReadingAchievement?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private static let storageKey = "reading.footprint.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(ReadingFootprint.self, from: data) {
            footprint = stored
        } else {
            footprint = ReadingFootprint()
        }
    }

    var achievements: [ReadingAchievement] { ReadingAchievement.all }
    var unlockedCount: Int { achievements.filter(isUnlocked).count }
    var readingMinutes: Int { Int(footprint.readingSeconds / 60) }
    var currentStreak: Int { activeStreak(on: .now) }
    var homeExperience: Int {
        footprint.pagesTurned
            + readingMinutes * 2
            + footprint.completedBookIDs.count * 40
            + footprint.pagesFavorited * 8
            + footprint.pagesSaved * 10
    }
    var homeLevel: Int {
        (Self.levelThresholds.lastIndex(where: { homeExperience >= $0 }) ?? 0) + 1
    }
    var homeLevelTitle: String {
        let titles = ["初来乍到", "窗边读者", "暖灯住客", "藏书管家", "小家主人", "星夜收藏家", "万象馆长"]
        return titles[min(max(homeLevel - 1, 0), titles.count - 1)]
    }
    var homeLevelProgress: Double {
        let index = min(max(homeLevel - 1, 0), Self.levelThresholds.count - 1)
        guard index < Self.levelThresholds.count - 1 else { return 1 }
        let lower = Self.levelThresholds[index]
        let upper = Self.levelThresholds[index + 1]
        return min(max(Double(homeExperience - lower) / Double(max(upper - lower, 1)), 0), 1)
    }
    var nextLockedAchievement: ReadingAchievement? {
        achievements
            .filter { !isUnlocked($0) }
            .max {
                let left = Double(progress(for: $0)) / Double(max($0.target, 1))
                let right = Double(progress(for: $1)) / Double(max($1.target, 1))
                return left < right
            }
    }

    @ObservationIgnored private static let levelThresholds = [0, 80, 240, 600, 1_300, 2_600, 5_000]

    func isUnlocked(_ achievement: ReadingAchievement) -> Bool {
        footprint.unlockedAt[achievement.id] != nil
    }

    func unlockedDate(_ achievement: ReadingAchievement) -> Date? {
        footprint.unlockedAt[achievement.id]
    }

    func progress(for achievement: ReadingAchievement) -> Int {
        switch achievement.metric {
        case .booksOpened: footprint.openedBookIDs.count
        case .homeVisits: footprint.homeVisits
        case .pagesTurned: footprint.pagesTurned
        case .booksCompleted: footprint.completedBookIDs.count
        case .minutesRead: readingMinutes
        case .pagesSaved: footprint.pagesSaved
        case .pagesFavorited: footprint.pagesFavorited
        case .readingStreak: footprint.longestReadingStreak
        }
    }

    func recordOpened(bookID: UUID, at date: Date = .now) {
        footprint.openedBookIDs.insert(bookID)
        footprint.homeVisits += 1
        recordReadingDay(date)
        finishUpdate()
    }

    func recordPageTurn(bookID: UUID, reachedLastPage: Bool, at date: Date = .now) {
        footprint.pagesTurned += 1
        if reachedLastPage { footprint.completedBookIDs.insert(bookID) }
        let key = dayKey(for: date)
        footprint.readingDayKeys.insert(key)
        footprint.pageTurnsByDay[key, default: 0] += 1
        updateLongestStreak(endingAt: date)
        finishUpdate()
    }

    func recordReadingDuration(_ duration: TimeInterval, at date: Date = .now) {
        guard duration > 1 else { return }
        let recorded = min(duration, 12 * 60 * 60)
        footprint.readingSeconds += recorded
        let key = dayKey(for: date)
        footprint.readingDayKeys.insert(key)
        footprint.readingSecondsByDay[key, default: 0] += recorded
        updateLongestStreak(endingAt: date)
        finishUpdate()
    }

    func recordSavedPage() {
        footprint.pagesSaved += 1
        finishUpdate()
    }

    func recordFavoritedPage() {
        footprint.pagesFavorited += 1
        finishUpdate()
    }

    func clearLatestUnlock() {
        latestUnlock = nil
    }

    func resetProgress() {
        saveTask?.cancel()
        latestUnlock = nil
        footprint = ReadingFootprint()
        defaults.removeObject(forKey: Self.storageKey)
    }

    func flush() {
        saveTask?.cancel()
        persistImmediately()
    }

    func dailyQuests(on date: Date = .now) -> [DailyReadingQuest] {
        let key = dayKey(for: date)
        let cameHome = footprint.readingDayKeys.contains(key) ? 1 : 0
        let pages = footprint.pageTurnsByDay[key, default: 0]
        let minutes = Int(footprint.readingSecondsByDay[key, default: 0] / 60)
        return [
            DailyReadingQuest(
                id: "come-home",
                title: "点亮小屋",
                detail: "今天翻开一本喜欢的读物",
                systemImage: "house.lodge.fill",
                value: cameHome,
                target: 1
            ),
            DailyReadingQuest(
                id: "ten-pages",
                title: "十页散步",
                detail: "今天悠闲地翻过 10 页",
                systemImage: "book.pages.fill",
                value: pages,
                target: 10
            ),
            DailyReadingQuest(
                id: "fifteen-minutes",
                title: "暖灯片刻",
                detail: "今天陪一本书待上 15 分钟",
                systemImage: "lamp.table.fill",
                value: minutes,
                target: 15
            )
        ]
    }

    private func finishUpdate() {
        for achievement in achievements where footprint.unlockedAt[achievement.id] == nil {
            guard progress(for: achievement) >= achievement.target else { continue }
            footprint.unlockedAt[achievement.id] = .now
            latestUnlock = achievement
        }
        schedulePersistence()
    }

    private func schedulePersistence() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.persistImmediately()
        }
    }

    private func persistImmediately() {
        if let data = try? JSONEncoder().encode(footprint) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func recordReadingDay(_ date: Date) {
        footprint.readingDayKeys.insert(dayKey(for: date))
        updateLongestStreak(endingAt: date)
    }

    private func updateLongestStreak(endingAt date: Date) {
        footprint.longestReadingStreak = max(
            footprint.longestReadingStreak,
            consecutiveStreak(endingAt: date)
        )
    }

    private func activeStreak(on date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: date)
        if footprint.readingDayKeys.contains(dayKey(for: today)) {
            return consecutiveStreak(endingAt: today)
        }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              footprint.readingDayKeys.contains(dayKey(for: yesterday))
        else { return 0 }
        return consecutiveStreak(endingAt: yesterday)
    }

    private func consecutiveStreak(endingAt date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var cursor = calendar.startOfDay(for: date)
        var count = 0
        while footprint.readingDayKeys.contains(dayKey(for: cursor)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private func dayKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
