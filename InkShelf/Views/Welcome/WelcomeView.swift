import SwiftUI

enum WelcomeRelease {
    static let current = "2.5"
}

enum WelcomePresentationPolicy {
    static func shouldPresent(
        hasSeenLegacyWelcome: Bool,
        lastSeenRelease: String,
        showOnMajorUpdate: Bool
    ) -> Bool {
        if !hasSeenLegacyWelcome { return true }
        return showOnMajorUpdate && lastSeenRelease != WelcomeRelease.current
    }
}

struct WelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    let onFinish: () -> Void

    private let features: [WelcomeFeature] = [
        .init(
            eyebrow: "二次元小家 · 2.5 正式版",
            title: "欢迎回家",
            subtitle: "把漫画、画集、电子书和喜欢的画面安放在同一个温暖的小家。2.5 从书架到阅读器都重新梳理，只为让每次打开更自在。",
            symbol: "house.fill",
            highlights: ["清新书架", "沉浸阅读", "安心收藏"],
            colors: [AppTheme.honey, AppTheme.coral],
            artwork: .home
        ),
        .init(
            eyebrow: "全新自适应书架",
            title: "横竖封面，各得其所",
            subtitle: "横版画集保持横向宽卡，竖版读物继续紧凑排列。切换分类时内容一次完成交接，不再闪出旧卡片或留下鬼影。",
            symbol: "rectangle.grid.2x2.fill",
            highlights: ["横版原比例", "竖版双列", "分类无重影"],
            colors: [AppTheme.cyan, AppTheme.accent],
            artwork: .shelf
        ),
        .init(
            eyebrow: "阅读体验焕新",
            title: "顺滑，是阅读的底色",
            subtitle: "页面预取、高清解码和缓存调度在幕后协作；翻页、缩放、工具栏和书架动画保留质感，也把流畅度放在第一位。",
            symbol: "book.pages.fill",
            highlights: ["稳定页码", "高清预取", "自然动效"],
            colors: [AppTheme.lilac, AppTheme.cyan],
            artwork: .motion
        ),
        .init(
            eyebrow: "覆盖升级 · 数据保留",
            title: "你的书库，安心留在原处",
            subtitle: "在线更新只替换应用本体。现有画册、收藏、阅读进度、成就和本地缓存都会继续留在小家里，不需要重新导入。",
            symbol: "checkmark.shield.fill",
            highlights: ["保留书架", "保留缓存", "重复检测"],
            colors: [AppTheme.mint, AppTheme.honey],
            artwork: .storage
        ),
        .init(
            eyebrow: "一切准备就绪",
            title: "现在，回家阅读吧",
            subtitle: "去书架挑一本喜欢的画集，或在画廊珍藏单张图片。阅读方式、欢迎页、AI 陪读和存储管理都可以随时在“小家设置”中调整。",
            symbol: "heart.fill",
            highlights: ["画廊珍藏", "AI 陪读", "自由设置"],
            colors: [AppTheme.coral, AppTheme.lilac],
            artwork: .ready
        )
    ]

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                topBar

                TabView(selection: $page) {
                    ForEach(features.indices, id: \.self) { index in
                        WelcomeFeatureView(feature: features[index], isActive: page == index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                footer
            }
        }
        .tint(AppTheme.accent)
        .accessibilityIdentifier("welcome-2-5")
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Label("二次元小家", systemImage: "house.fill")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.wood)

            Text("2.5")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppTheme.accentGradient, in: Capsule())

            Spacer()

            Button("稍后", action: onFinish)
                .accessibilityIdentifier("welcome-skip")
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        VStack(spacing: 15) {
            HStack(spacing: 7) {
                ForEach(features.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? AppTheme.accent : Color.secondary.opacity(0.22))
                        .frame(width: index == page ? 24 : 7, height: 7)
                }

                Spacer()

                Text("\(page + 1) / \(features.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .animation(reduceMotion ? nil : AppMotion.value, value: page)

            Button(action: advance) {
                Label(
                    page == features.count - 1 ? "进入二次元小家" : "继续了解",
                    systemImage: page == features.count - 1 ? "house.fill" : "arrow.right"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .accessibilityIdentifier("welcome-continue")
            .adaptiveProminentButton()
        }
        .padding(.horizontal, 26)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .background(.ultraThinMaterial)
    }

    private func advance() {
        if page == features.count - 1 {
            onFinish()
        } else {
            withAnimation(reduceMotion ? nil : AppMotion.panel) {
                page += 1
            }
        }
    }
}

private struct WelcomeFeatureView: View {
    let feature: WelcomeFeature
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: horizontalSizeClass == .regular ? 28 : 21) {
                WelcomeArtwork(feature: feature, isActive: isActive)
                    .frame(maxWidth: horizontalSizeClass == .regular ? 520 : 410)

                VStack(spacing: 11) {
                    Text(feature.eyebrow)
                        .font(.caption.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(feature.colors[0])

                    Text(feature.title)
                        .font(.system(
                            size: horizontalSizeClass == .regular ? 44 : 34,
                            weight: .bold,
                            design: .rounded
                        ))
                        .multilineTextAlignment(.center)

                    Text(feature.subtitle)
                        .font(horizontalSizeClass == .regular ? .title3 : .body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .frame(maxWidth: 620)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 112), spacing: 9)],
                    spacing: 9
                ) {
                    ForEach(feature.highlights, id: \.self) { highlight in
                        Label(highlight, systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 10)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
                .frame(maxWidth: 520)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, horizontalSizeClass == .regular ? 34 : 18)
            .padding(.bottom, 24)
            .opacity(isActive ? 1 : 0.82)
            .offset(y: isActive || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? nil : AppMotion.reveal, value: isActive)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct WelcomeArtwork: View {
    let feature: WelcomeFeature
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [feature.colors[0].opacity(0.22), feature.colors[1].opacity(0.13)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(feature.colors[1].opacity(0.17))
                .frame(width: 170, height: 170)
                .blur(radius: 4)
                .offset(x: 118, y: -72)

            artworkContent
                .padding(24)

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(.white.opacity(0.72), lineWidth: 1.5)
        }
        .aspectRatio(1.45, contentMode: .fit)
        .shadow(color: feature.colors[0].opacity(0.18), radius: 24, y: 14)
        .scaleEffect(isActive ? 1 : 0.965)
        .animation(reduceMotion ? nil : AppMotion.reveal, value: isActive)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var artworkContent: some View {
        switch feature.artwork {
        case .home:
            ZStack(alignment: .bottomTrailing) {
                CozyWindowView()
                    .frame(maxWidth: 310, maxHeight: 210)
                    .padding(.trailing, 22)

                artworkBadge("正式版", symbol: "sparkles")
            }

        case .shelf:
            VStack(spacing: 13) {
                HStack(alignment: .bottom, spacing: 13) {
                    miniatureBook(colors: [AppTheme.coral, AppTheme.honey])
                    miniatureBook(colors: [AppTheme.cyan, AppTheme.lilac])
                    Spacer(minLength: 2)
                    artworkBadge("自适应", symbol: feature.symbol)
                }

                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(LinearGradient(colors: feature.colors, startPoint: .leading, endPoint: .trailing))
                    .aspectRatio(1.72, contentMode: .fit)
                    .overlay(alignment: .bottomLeading) {
                        Label("横版画集", systemImage: "photo.on.rectangle.angled")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(13)
                    }
            }

        case .motion:
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    feature.colors[index % feature.colors.count].opacity(index == 0 ? 0.88 : 0.40),
                                    feature.colors[1].opacity(index == 0 ? 0.88 : 0.40)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 190, height: 238)
                        .rotationEffect(.degrees(Double(index - 1) * 8))
                        .offset(x: CGFloat(index - 1) * 47, y: CGFloat(abs(index - 1)) * 12)
                }

                Image(systemName: feature.symbol)
                    .font(.system(size: 58, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, feature.colors[0])
            }

        case .storage:
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 176, height: 176)
                Image(systemName: feature.symbol)
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(feature.colors[0])
                HStack {
                    artworkBadge("书架保留", symbol: "books.vertical.fill")
                    Spacer()
                    artworkBadge("缓存保留", symbol: "externaldrive.fill")
                }
                .frame(maxWidth: 350)
            }

        case .ready:
            ZStack {
                Image(systemName: "house.and.flag.fill")
                    .font(.system(size: 122, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(feature.colors[0], feature.colors[1])
                    .shadow(color: feature.colors[0].opacity(0.24), radius: 20, y: 10)

                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(AppTheme.honey)
                    .offset(x: 104, y: -68)
            }
        }
    }

    private func miniatureBook(colors: [Color]) -> some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 82, height: 118)
            .overlay(alignment: .bottomLeading) {
                Image(systemName: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(11)
            }
    }

    private func artworkBadge(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.bold())
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct WelcomeFeature {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String
    let highlights: [String]
    let colors: [Color]
    let artwork: WelcomeArtworkKind
}

private enum WelcomeArtworkKind {
    case home
    case shelf
    case motion
    case storage
    case ready
}
