import SwiftUI

struct AchievementsView: View {
    @Environment(AchievementStore.self) private var achievements
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                footprintHeader

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(achievements.achievements) { achievement in
                        AchievementCard(
                            achievement: achievement,
                            value: achievements.progress(for: achievement),
                            unlockedAt: achievements.unlockedDate(achievement)
                        )
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 80)
        }
        .background(AuroraBackground())
        .navigationTitle("回家足迹")
    }

    private var footprintHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("你和画集相处的点点滴滴", systemImage: "pawprint.fill")
                .font(.title3.bold())
                .foregroundStyle(AppTheme.wood)
            HStack(spacing: 12) {
                FootprintStat(value: achievements.footprint.openedBookIDs.count, label: "翻开读物")
                FootprintStat(value: achievements.footprint.pagesTurned, label: "翻过页面")
                FootprintStat(value: achievements.readingMinutes, label: "阅读分钟")
            }
            Text("已点亮 \(achievements.unlockedCount) / \(achievements.achievements.count) 枚小徽章")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .inkGlass(cornerRadius: 26)
    }
}

private struct FootprintStat: View {
    let value: Int
    let label: String
    var body: some View {
        VStack(spacing: 3) {
            Text("\(value)").font(.title3.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AchievementCard: View {
    let achievement: ReadingAchievement
    let value: Int
    let unlockedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: achievement.systemImage)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(unlockedAt == nil ? .secondary : AppTheme.coral)
                .frame(width: 46, height: 46)
                .background((unlockedAt == nil ? Color.secondary : AppTheme.honey).opacity(0.13), in: Circle())
            Text(achievement.title).font(.headline)
            Text(achievement.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            ProgressView(value: Double(min(value, achievement.target)), total: Double(achievement.target))
                .tint(unlockedAt == nil ? AppTheme.accent : AppTheme.coral)
            Text(unlockedAt.map { "已于 \($0.formatted(date: .abbreviated, time: .omitted)) 点亮" } ?? "\(min(value, achievement.target)) / \(achievement.target)")
                .font(.caption2)
                .foregroundStyle(unlockedAt == nil ? .secondary : AppTheme.coral)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .inkGlass(cornerRadius: 22)
        .opacity(unlockedAt == nil ? 0.78 : 1)
        .accessibilityElement(children: .combine)
    }
}
