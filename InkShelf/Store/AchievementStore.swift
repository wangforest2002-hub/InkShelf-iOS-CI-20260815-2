import Foundation
import Observation

@MainActor
@Observable
final class AchievementStore {
    private(set) var footprint: ReadingFootprint
    private(set) var latestUnlock: ReadingAchievement?

    @ObservationIgnored private let defaults: UserDefaults
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
    var unlockedCount: Int { footprint.unlockedAt.count }
    var readingMinutes: Int { Int(footprint.readingSeconds / 60) }

    func isUnlocked(_ achievement: ReadingAchievement) -> Bool {
        footprint.unlockedAt[achievement.id] != nil
    }

    func unlockedDate(_ achievement: ReadingAchievement) -> Date? {
        footprint.unlockedAt[achievement.id]
    }

    func progress(for achievement: ReadingAchievement) -> Int {
        switch achievement.metric {
        case .booksOpened: footprint.openedBookIDs.count
        case .pagesTurned: footprint.pagesTurned
        case .booksCompleted: footprint.completedBookIDs.count
        case .minutesRead: readingMinutes
        case .pagesSaved: footprint.pagesSaved
        case .pagesFavorited: footprint.pagesFavorited
        }
    }

    func recordOpened(bookID: UUID) {
        footprint.openedBookIDs.insert(bookID)
        finishUpdate()
    }

    func recordPageTurn(bookID: UUID, reachedLastPage: Bool) {
        footprint.pagesTurned += 1
        if reachedLastPage { footprint.completedBookIDs.insert(bookID) }
        finishUpdate()
    }

    func recordReadingDuration(_ duration: TimeInterval) {
        guard duration > 1 else { return }
        footprint.readingSeconds += min(duration, 12 * 60 * 60)
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

    private func finishUpdate() {
        for achievement in achievements where footprint.unlockedAt[achievement.id] == nil {
            guard progress(for: achievement) >= achievement.target else { continue }
            footprint.unlockedAt[achievement.id] = .now
            latestUnlock = achievement
        }
        if let data = try? JSONEncoder().encode(footprint) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
