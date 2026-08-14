import SwiftUI

struct WelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    let onFinish: () -> Void

    private let features: [WelcomeFeature] = [
        .init(
            title: "欢迎回到二次元小家",
            subtitle: "这里不只是一副书架。窗边有暖光，喜欢的故事有自己的位置，每次打开都像回到熟悉的小屋。",
            symbol: "house.fill",
            colors: [AppTheme.honey, AppTheme.coral]
        ),
        .init(
            title: "原稿原样，清晰到底",
            subtitle: "PDF 使用 PDFKit 原生渲染，导入文件不转码；图片与压缩包也保留源文件。",
            symbol: "sparkles.rectangle.stack.fill",
            colors: [AppTheme.cyan, AppTheme.accent]
        ),
        .init(
            title: "漫画与电子书，一架收好",
            subtitle: "漫画、图片画集、PDF、EPUB 与常见文本电子书都能阅读，首图封面让书架清爽明快。",
            symbol: "books.vertical.fill",
            colors: [AppTheme.accent, AppTheme.coral]
        ),
        .init(
            title: "喜欢的画面，单独珍藏",
            subtitle: "一键收藏当前页，或把高清画面保存到系统照片；整本收藏和单页珍藏各有自己的位置。",
            symbol: "heart.rectangle.stack.fill",
            colors: [AppTheme.coral, AppTheme.honey]
        ),
        .init(
            title: "阅读时，也有人陪你",
            subtitle: "可选的 AI 陪读会生成自然弹幕、陪伴对话与片末模拟讨论，也能帮你写简介、推荐和分享文案。",
            symbol: "sparkles",
            colors: [AppTheme.coral, AppTheme.accent]
        ),
        .init(
            title: "按喜欢的方式阅读",
            subtitle: "单页、双页、横向、纵向、日漫顺序和电子书重排自由切换，阅读进度自动记忆。",
            symbol: "rectangle.split.2x1.fill",
            colors: [AppTheme.coral, AppTheme.cyan]
        )
    ]

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                HStack {
                    Label("二次元小家", systemImage: "house.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.wood)
                        .padding(22)
                    Spacer()
                    Button("跳过", action: onFinish)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(22)
                }

                TabView(selection: $page) {
                    ForEach(features.indices, id: \.self) { index in
                        WelcomeFeatureView(feature: features[index], isActive: page == index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .animation(reduceMotion ? nil : .smooth, value: page)

                Button {
                    if page == features.count - 1 {
                        onFinish()
                    } else {
                        withAnimation(reduceMotion ? nil : .snappy) {
                            page += 1
                        }
                    }
                } label: {
                    Label(page == features.count - 1 ? "回到我的小家" : "继续", systemImage: "arrow.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .adaptiveProminentButton()
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .tint(AppTheme.accent)
    }
}

private struct WelcomeFeatureView: View {
    let feature: WelcomeFeature
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 30) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [feature.colors[0].opacity(0.42), .clear],
                            center: .center,
                            startRadius: 5,
                            endRadius: 125
                        )
                    )
                    .frame(width: 270, height: 270)

                if feature.symbol == "house.fill" {
                    CozyWindowView()
                        .frame(width: 230, height: 170)
                        .overlay(alignment: .bottom) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 54, weight: .semibold))
                                .foregroundStyle(AppTheme.wood)
                                .padding(15)
                                .background(.ultraThinMaterial, in: Circle())
                                .offset(y: 32)
                        }
                        .scaleEffect(isActive ? 1 : 0.92)
                } else {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 82, weight: .medium))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, LinearGradient(colors: feature.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: feature.colors[0].opacity(0.4), radius: 30)
                        .rotationEffect(.degrees(isActive && !reduceMotion ? 0 : -4))
                        .scaleEffect(isActive ? 1 : 0.90)
                }
            }
            .animation(reduceMotion ? nil : .bouncy(duration: 0.7), value: isActive)

            VStack(spacing: 14) {
                Text(feature.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text(feature.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: 440)
            }
            .padding(.horizontal, 30)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WelcomeFeature {
    let title: String
    let subtitle: String
    let symbol: String
    let colors: [Color]
}
