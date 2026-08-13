import SwiftUI

struct EmptyLibraryView: View {
    let isFavorites: Bool
    let hasSearch: Bool
    let importAction: () -> Void
    let importFolderAction: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack(alignment: .bottom) {
                    CozyWindowView()
                        .frame(width: 220, height: 150)

                    HStack(alignment: .bottom, spacing: 14) {
                        Image(systemName: isFavorites ? "heart.fill" : "books.vertical.fill")
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

                if !isFavorites && !hasSearch {
                    VStack(spacing: 12) {
                        Button(action: importAction) {
                            Label("把读物带回家", systemImage: "plus")
                                .frame(maxWidth: 280)
                        }
                        .adaptiveProminentButton()

                        Button(action: importFolderAction) {
                            Label("布置文件夹画集", systemImage: "folder.badge.plus")
                                .frame(maxWidth: 280)
                        }
                        .adaptiveGlassButton()
                    }
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
        if isFavorites { return "珍藏角落还空着" }
        return "欢迎回到二次元小家"
    }

    private var description: String {
        if hasSearch { return "换一个书名试试，喜欢的故事也许就在旁边。" }
        if isFavorites { return "长按书架中的封面，把想反复回味的故事安放到这里。" }
        return "窗边和书架已经替你准备好了。\n带回 PDF、CBZ、图片、电子书或整个画集文件夹吧。"
    }
}
