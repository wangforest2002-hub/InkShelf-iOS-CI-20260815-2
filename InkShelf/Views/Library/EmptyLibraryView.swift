import SwiftUI

struct EmptyLibraryView: View {
    let scope: LibraryScope
    let hasSearch: Bool
    let importAction: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack(alignment: .bottom) {
                    CozyWindowView()
                        .frame(width: 220, height: 150)

                    HStack(alignment: .bottom, spacing: 14) {
                        Image(systemName: symbol)
                            .font(.system(size: 44, weight: .medium))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(AppTheme.coral, AppTheme.accent)
                            .offset(y: floating ? -4 : 2)

                        Image(systemName: "cup.and.saucer.fill")
                            .font(.title)
                            .foregroundStyle(AppTheme.wood)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .offset(y: 22)
                }
                .padding(.bottom, 18)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                    value: floating
                )

                VStack(spacing: 9) {
                    Text(title)
                        .font(.title2.bold())
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                if scope == .all && !hasSearch {
                    Button(action: importAction) {
                        Label("从文件或 iCloud 导入", systemImage: "doc.badge.plus")
                            .frame(maxWidth: 280)
                    }
                    .adaptiveProminentButton()
                }

                Label("原文件会原样保存，不压缩、不转码", systemImage: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
        }
        .onAppear { floating = true }
    }

    private var title: String {
        if hasSearch { return "这间小屋里还没找到它" }
        if scope == .favorites { return "珍藏角落还空着" }
        if scope == .recent { return "最近还没有翻开的书" }
        return "欢迎回到二次元小家"
    }

    private var description: String {
        if hasSearch { return "换一个书名试试，喜欢的故事也许就在旁边。" }
        if scope == .favorites { return "可以收藏整本读物，也可以在阅读时珍藏喜欢的单页。" }
        if scope == .recent { return "翻开一本读物后，它会带着阅读进度出现在这里。" }
        return "窗边和书架已经替你准备好了。\n从本地或 iCloud Drive 带回 PDF、CBZ、图片和电子书吧。"
    }

    private var symbol: String {
        switch scope {
        case .all: "books.vertical.fill"
        case .recent: "clock.fill"
        case .favorites: "star.fill"
        }
    }
}
