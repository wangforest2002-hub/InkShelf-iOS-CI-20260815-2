import SwiftUI

struct AchievementsView: View {
    @Environment(AchievementStore.self) private var achievements
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                footprintHeader
                dailyQuestSection

                if let next = achievements.nextLockedAchievement {
                    nextAchievementCard(next)
                }

                ForEach(AchievementTier.allCases, id: \.self) { tier in
                    let items = achievements.achievements.filter { $0.tier == tier }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("\(tier.title)徽章", systemImage: tier.systemImage)
                                .font(.headline)
                                .foregroundStyle(tier.color)
                            Spacer()
                            Text("\(items.filter { achievements.isUnlocked($0) }.count)/\(items.count)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(items) { achievement in
                                AchievementCard(
                                    achievement: achievement,
                                    value: achievements.progress(for: achievement),
                                    unlockedAt: achievements.unlockedDate(achievement),
                                    appeared: appeared
                                )
                                .scrollTransition(.animated.threshold(.visible(0.24))) { content, phase in
                                    content
                                        .opacity(phase.isIdentity ? 1 : 0.55)
                                        .scaleEffect(phase.isIdentity ? 1 : 0.965)
                                }
                            }
                        }
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 80)
        }
        .background {
            ZStack {
                AuroraBackground()
                AchievementConstellation(animate: appeared && !reduceMotion)
            }
        }
        .navigationTitle("回家足迹")
        .onAppear {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.7)) {
                appeared = true
            }
        }
    }

    private var footprintHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(AppTheme.honey.opacity(0.16), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: appeared ? achievements.homeLevelProgress : 0)
                        .stroke(
                            AngularGradient(colors: [AppTheme.honey, AppTheme.coral, AppTheme.lilac], center: .center),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("Lv.").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        Text("\(achievements.homeLevel)")
                            .font(.title2.bold().monospacedDigit())
                            .contentTransition(.numericText())
                    }
                }
                .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 5) {
                    Text("\(achievements.homeLevelTitle)的小家")
                        .font(.title3.bold())
                    Text("每一次翻页，都在让这里变得更像你。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(
                        achievements.currentStreak > 0 ? "连续回家 \(achievements.currentStreak) 天" : "今天翻开一本书，点亮暖灯",
                        systemImage: achievements.currentStreak > 0 ? "flame.fill" : "lamp.table.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(achievements.currentStreak > 0 ? AppTheme.coral : AppTheme.wood)
                }
            }

            HStack(spacing: 12) {
                FootprintStat(value: achievements.footprint.openedBookIDs.count, label: "不同读物", symbol: "books.vertical.fill")
                FootprintStat(value: achievements.footprint.pagesTurned, label: "翻过页面", symbol: "book.pages.fill")
                FootprintStat(value: achievements.readingMinutes, label: "阅读分钟", symbol: "clock.fill")
            }

            HStack {
                Label("已点亮 \(achievements.unlockedCount) / \(achievements.achievements.count)", systemImage: "medal.star.fill")
                Spacer()
                Text("最长连续 \(achievements.footprint.longestReadingStreak) 天")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .inkGlass(cornerRadius: 26)
        .overlay { WarmLightSweep().clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous)) }
    }

    private var dailyQuestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("今日的小小约定", systemImage: "sun.max.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.wood)
                Spacer()
                let completed = achievements.dailyQuests().filter(\.isCompleted).count
                Text("\(completed)/3")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(completed == 3 ? AppTheme.coral : .secondary)
            }

            ForEach(achievements.dailyQuests()) { quest in
                DailyQuestRow(quest: quest, appeared: appeared)
            }
        }
        .padding(16)
        .inkGlass(cornerRadius: 24)
    }

    private func nextAchievementCard(_ achievement: ReadingAchievement) -> some View {
        let value = achievements.progress(for: achievement)
        return HStack(spacing: 14) {
            Image(systemName: achievement.systemImage)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(achievement.tier.color)
                .frame(width: 52, height: 52)
                .background(achievement.tier.color.opacity(0.13), in: Circle())
                .symbolEffect(.pulse, options: .repeating.speed(0.55), isActive: appeared && !reduceMotion)
            VStack(alignment: .leading, spacing: 5) {
                Text("离你最近的成就")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(achievement.tier.color)
                Text(achievement.title).font(.headline)
                ProgressView(value: appeared ? Double(min(value, achievement.target)) : 0, total: Double(achievement.target))
                    .tint(achievement.tier.color)
                Text("\(min(value, achievement.target)) / \(achievement.target) · \(achievement.detail)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .inkGlass(cornerRadius: 24, interactive: true)
    }
}

private struct FootprintStat: View {
    let value: Int
    let label: String
    let symbol: String
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.caption).foregroundStyle(AppTheme.accent)
            Text("\(value)").font(.headline.bold().monospacedDigit()).contentTransition(.numericText())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct DailyQuestRow: View {
    let quest: DailyReadingQuest
    let appeared: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: quest.isCompleted ? "checkmark.circle.fill" : quest.systemImage)
                .font(.title3)
                .foregroundStyle(quest.isCompleted ? AppTheme.mint : AppTheme.accent)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: quest.isCompleted)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(quest.title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(min(quest.value, quest.target))/\(quest.target)")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(quest.isCompleted ? AppTheme.mint : .secondary)
                }
                Text(quest.detail).font(.caption2).foregroundStyle(.secondary)
                ProgressView(value: appeared ? Double(min(quest.value, quest.target)) : 0, total: Double(quest.target))
                    .tint(quest.isCompleted ? AppTheme.mint : AppTheme.accent)
            }
        }
    }
}

private struct AchievementCard: View {
    let achievement: ReadingAchievement
    let value: Int
    let unlockedAt: Date?
    let appeared: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: achievement.systemImage)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(unlockedAt == nil ? Color.secondary : achievement.tier.color)
                .frame(width: 46, height: 46)
                .background((unlockedAt == nil ? Color.secondary : achievement.tier.color).opacity(0.13), in: Circle())
                .symbolEffect(.bounce, value: unlockedAt != nil)
            Text(achievement.tier.title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(unlockedAt == nil ? Color.secondary : achievement.tier.color)
            Text(achievement.title).font(.headline)
            Text(achievement.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            ProgressView(value: appeared ? Double(min(value, achievement.target)) : 0, total: Double(achievement.target))
                .tint(unlockedAt == nil ? AppTheme.accent : achievement.tier.color)
            Text(unlockedAt.map { "已于 \($0.formatted(date: .abbreviated, time: .omitted)) 点亮" } ?? "\(min(value, achievement.target)) / \(achievement.target)")
                .font(.caption2)
                .foregroundStyle(unlockedAt == nil ? Color.secondary : achievement.tier.color)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .inkGlass(cornerRadius: 22)
        .opacity(unlockedAt == nil ? 0.78 : 1)
        .accessibilityElement(children: .combine)
    }
}

private struct AchievementConstellation: View {
    let animate: Bool

    var body: some View {
        GeometryReader { proxy in
            ForEach(0..<9, id: \.self) { index in
                Image(systemName: index.isMultiple(of: 3) ? "sparkle" : "star.fill")
                    .font(.system(size: CGFloat(7 + index % 4)))
                    .foregroundStyle(index.isMultiple(of: 2) ? AppTheme.honey.opacity(0.26) : AppTheme.lilac.opacity(0.22))
                    .position(
                        x: proxy.size.width * CGFloat((index * 37) % 91) / 100,
                        y: proxy.size.height * CGFloat((index * 23 + 11) % 97) / 100
                    )
                    .offset(y: animate ? -8 : 8)
                    .animation(
                        .easeInOut(duration: Double(2.8 + Double(index % 4))).repeatForever(autoreverses: true).delay(Double(index) * 0.12),
                        value: animate
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension AchievementTier {
    var color: Color {
        switch self {
        case .cozy: AppTheme.honey
        case .shining: AppTheme.coral
        case .rare: AppTheme.lilac
        case .legendary: AppTheme.cyan
        }
    }

    var systemImage: String {
        switch self {
        case .cozy: "heart.circle.fill"
        case .shining: "sparkles"
        case .rare: "diamond.fill"
        case .legendary: "crown.fill"
        }
    }
}
