import SwiftUI

struct WelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    let onFinish: () -> Void

    private let features: [WelcomeFeature] = [
        .init(
            title: "原稿原样，清晰到底",
            subtitle: "PDF 使用 PDFKit 原生渲染，导入文件不转码；图片与压缩包也保留源文件。",
            symbol: "sparkles.rectangle.stack.fill",
            colors: [AppTheme.cyan, AppTheme.accent]
        ),
        .init(
            title: "漫画与电子书，一架收好",
            subtitle: "漫画、文件夹画集、PDF、EPUB 与常见文本电子书都能阅读，多图预览让内容一目了然。",
            symbol: "books.vertical.fill",
            colors: [AppTheme.accent, AppTheme.coral]
        ),
        .init(
            title: "iCloud 书库，按需下载",
            subtitle: "选择 iCloud Drive 中的画集文件夹即可浏览；原书首次打开后保存在本机，断网也能继续。",
            symbol: "icloud.and.arrow.down.fill",
            colors: [AppTheme.cyan, AppTheme.accent]
        ),
        .init(
            title: "阅读时，也有人陪你",
            subtitle: "可选的 AI 陪读会识别文字和画面线索，生成自然弹幕、陪伴对话与片末模拟讨论。",
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
                    Label(page == features.count - 1 ? "进入书架" : "继续", systemImage: "arrow.right")
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

                Image(systemName: feature.symbol)
                    .font(.system(size: 82, weight: .medium))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, LinearGradient(colors: feature.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: feature.colors[0].opacity(0.4), radius: 30)
                    .rotationEffect(.degrees(isActive && !reduceMotion ? 0 : -4))
                    .scaleEffect(isActive ? 1 : 0.90)
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
