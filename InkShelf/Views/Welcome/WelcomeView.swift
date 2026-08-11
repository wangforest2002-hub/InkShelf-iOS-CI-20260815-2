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
            title: "属于你的离线书架",
            subtitle: "漫画、文件夹画集和 PDF 全部保存在设备本地，多图预览让内容一目了然。",
            symbol: "books.vertical.fill",
            colors: [AppTheme.accent, AppTheme.coral]
        ),
        .init(
            title: "按喜欢的方式阅读",
            subtitle: "单页、双页、横向、纵向与日漫顺序自由切换，阅读进度自动记忆。",
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
