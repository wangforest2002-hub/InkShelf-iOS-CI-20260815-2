import SwiftUI

struct AchievementsView: View {
    @Environment(AchievementStore.self) private var achievements
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false
    @State private var showResetConfirmation = false
    @State private var resetFeedback = 0
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize >= .xxxLarge ? 260 : 160, maximum: 300), spacing: 14)]
    }

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
                            Label {
                                Text("\(tier.title)徽章")
                            } icon: {
                                Image(systemName: tier.systemImage)
                                    .foregroundStyle(tier.color)
                            }
                            .font(.headline)
                            Spacer()
                            Text("\(items.filter { achievements.isUnlocked($0) }.count)/\(items.count)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(tier.color.opacity(0.10), in: Capsule())
                        }

                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(items) { achievement in
                                AchievementCard(
                                    achievement: achievement,
                                    value: achievements.progress(for: achievement),
                                    unlockedAt: achievements.unlockedDate(achievement),
                                    appeared: appeared
                                )
                                .scrollTransition(.interactive.threshold(.visible(0.14))) { content, phase in
                                    content
                                        .opacity(reduceMotion || phase.isIdentity ? 1 : 0.88)
                                        .offset(y: reduceMotion || phase.isIdentity ? 0 : 5)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 1080)
            .padding(18)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .background {
            ZStack {
                AuroraBackground()
                AchievementConstellation(animate: appeared && !reduceMotion)
            }
        }
        .navigationTitle("回家足迹")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("重置成就进度", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Label("足迹设置", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("achievements-options")
            }
        }
        .confirmationDialog(
            "重新开始回家足迹？",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空等级与全部成就", role: .destructive) {
                withAnimation(reduceMotion ? nil : AppMotion.panel) {
                    achievements.resetProgress()
                    appeared = false
                    resetFeedback += 1
                }
                Task { @MainActor in
                    await Task.yield()
                    withAnimation(reduceMotion ? nil : AppMotion.reveal) {
                        appeared = true
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会清空小家等级、徽章、连续阅读和每日任务；不会删除书籍、缓存、分组、珍藏或阅读位置。")
        }
        .sensoryFeedback(.warning, trigger: resetFeedback)
        .onAppear {
            withAnimation(reduceMotion ? nil : AppMotion.reveal) {
                appeared = true
            }
        }
    }

    private var footprintHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("阅读成长手帐", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(colorScheme == .dark ? AppTheme.peach : AppTheme.wood)

            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(spacing: 16))
            headerLayout {
                levelRing

                VStack(alignment: .leading, spacing: 5) {
                    Text("\(achievements.homeLevelTitle)的小家")
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("每一次翻页，都在让这里变得更像你。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(
                        achievements.currentStreak > 0 ? "连续回家 \(achievements.currentStreak) 天" : "今天翻开一本书，点亮暖灯",
                        systemImage: achievements.currentStreak > 0 ? "flame.fill" : "lamp.table.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(achievements.currentStreak > 0 ? AppTheme.coral : (colorScheme == .dark ? AppTheme.peach : AppTheme.wood))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize >= .xxxLarge ? 1 : 3),
                spacing: 10
            ) {
                FootprintStat(value: achievements.footprint.openedBookIDs.count, label: "不同读物", symbol: "books.vertical.fill", tint: AppTheme.accent)
                FootprintStat(value: achievements.footprint.pagesTurned, label: "翻过页面", symbol: "book.pages.fill", tint: AppTheme.lilac)
                FootprintStat(value: achievements.readingMinutes, label: "阅读分钟", symbol: "clock.fill", tint: AppTheme.coral)
            }

            let summaryLayout = dynamicTypeSize >= .xxxLarge
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 12))
            summaryLayout {
                Label("已点亮 \(achievements.unlockedCount) / \(achievements.achievements.count)", systemImage: "medal.star.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("最长连续 \(achievements.footprint.longestReadingStreak) 天")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(20)
        .inkGlass(cornerRadius: 26)
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [AppTheme.honey.opacity(0.28), .clear, AppTheme.lilac.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
    }

    private var levelRing: some View {
        ZStack {
            Circle()
                .fill(AppTheme.honey.opacity(0.07))
            Circle()
                .stroke(AppTheme.honey.opacity(0.16), lineWidth: 7)
            Circle()
                .trim(from: 0, to: appeared ? achievements.homeLevelProgress : 0)
                .stroke(
                    AngularGradient(colors: [AppTheme.honey, AppTheme.coral, AppTheme.lilac], center: .center),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : AppMotion.reveal, value: achievements.homeLevelProgress)
            VStack(spacing: 0) {
                Text("Lv.")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(achievements.homeLevel)")
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(12)
        }
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 112 : 84, height: dynamicTypeSize.isAccessibilitySize ? 112 : 84)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("小家等级")
        .accessibilityValue("\(achievements.homeLevel) 级，\(achievements.homeLevelTitle)")
    }

    private var dailyQuestSection: some View {
        let quests = achievements.dailyQuests()
        let completed = quests.filter(\.isCompleted).count
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("今日的小小约定", systemImage: "sun.max.fill")
                    .font(.headline)
                    .foregroundStyle(colorScheme == .dark ? AppTheme.peach : AppTheme.wood)
                Spacer()
                Text("\(completed)/\(quests.count)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(completed == quests.count ? AppTheme.coral : .secondary)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.coral.opacity(0.08), in: Capsule())
            }

            ForEach(quests) { quest in
                DailyQuestRow(quest: quest, appeared: appeared)
                if quest.id != quests.last?.id {
                    Divider().padding(.leading, 48)
                }
            }
        }
        .padding(18)
        .inkGlass(cornerRadius: 24)
    }

    private func nextAchievementCard(_ achievement: ReadingAchievement) -> some View {
        let value = achievements.progress(for: achievement)
        let cardLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(spacing: 14))
        return cardLayout {
            Image(systemName: achievement.systemImage)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(achievement.tier.color)
                .frame(width: 52, height: 52)
                .background(achievement.tier.color.opacity(0.13), in: Circle())
                .accessibilityHidden(true)
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .inkGlass(cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }
}

private struct FootprintStat: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Int
    let label: String
    let symbol: String
    let tint: Color
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text("\(value)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(tint.opacity(colorScheme == .dark ? 0.12 : 0.065), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(reduceMotion ? nil : AppMotion.value, value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
    }
}

private struct DailyQuestRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let quest: DailyReadingQuest
    let appeared: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: quest.isCompleted ? "checkmark.circle.fill" : quest.systemImage)
                .font(.title3)
                .foregroundStyle(quest.isCompleted ? AppTheme.mint : AppTheme.accent)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .background((quest.isCompleted ? AppTheme.mint : AppTheme.accent).opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                let titleLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(spacing: 8))
                titleLayout {
                    Text(quest.title).font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(min(quest.value, quest.target))/\(quest.target)")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(quest.isCompleted ? AppTheme.mint : .secondary)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                }
                Text(quest.detail).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: appeared ? Double(min(quest.value, quest.target)) : 0, total: Double(quest.target))
                    .tint(quest.isCompleted ? AppTheme.mint : AppTheme.accent)
            }
        }
        .animation(reduceMotion ? nil : AppMotion.value, value: quest.value)
        .accessibilityElement(children: .combine)
    }
}

private struct AchievementCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let achievement: ReadingAchievement
    let value: Int
    let unlockedAt: Date?
    let appeared: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: achievement.systemImage)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(unlockedAt == nil ? Color.secondary : achievement.tier.color)
                    .frame(width: 48, height: 48)
                    .background(
                        LinearGradient(
                            colors: [(unlockedAt == nil ? Color.secondary : achievement.tier.color).opacity(0.18), (unlockedAt == nil ? Color.secondary : achievement.tier.color).opacity(0.045)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Image(systemName: unlockedAt == nil ? "circle.dotted" : "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(unlockedAt == nil ? Color.secondary : achievement.tier.color)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .accessibilityLabel(unlockedAt == nil ? "尚未点亮" : "已点亮")
            }
            Text(achievement.title).font(.headline)
            Text(achievement.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
            ProgressView(value: appeared ? Double(min(value, achievement.target)) : 0, total: Double(achievement.target))
                .tint(unlockedAt == nil ? AppTheme.accent : achievement.tier.color)
            Text(achievement.tier.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(unlockedAt == nil ? Color.secondary : achievement.tier.color)
            Text(unlockedAt.map { "已于 \($0.formatted(date: .abbreviated, time: .omitted)) 点亮" } ?? "\(min(value, achievement.target)) / \(achievement.target)")
                .font(.caption2)
                .foregroundStyle(unlockedAt == nil ? Color.secondary : achievement.tier.color)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 226, maxHeight: .infinity, alignment: .topLeading)
        .inkGlass(cornerRadius: 22)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(achievement.tier.color.opacity(unlockedAt == nil ? 0.06 : 0.24), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : AppMotion.value, value: value)
        .accessibilityElement(children: .combine)
    }
}

private struct AchievementConstellation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .offset(y: animate ? -4 : 4)
                    .animation(reduceMotion ? nil : AppMotion.reveal.delay(Double(index) * 0.025), value: animate)
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
