import SwiftUI

struct EmptyLibraryView: View {
    let isFavorites: Bool
    let hasSearch: Bool
    let importAction: () -> Void
    let importFolderAction: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    var body: some View {
        ContentUnavailableView {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.16))
                    .frame(width: 150, height: 150)
                    .blur(radius: 12)

                Image(systemName: isFavorites ? "star.fill" : "books.vertical.fill")
                    .font(.system(size: 62, weight: .medium))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(AppTheme.cyan, AppTheme.accent)
                    .offset(y: floating ? -5 : 5)

                Image(systemName: "sparkle")
                    .font(.title2)
                    .foregroundStyle(AppTheme.coral)
                    .offset(x: 60, y: floating ? -54 : -46)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: floating)
        } description: {
            Text(description)
                .multilineTextAlignment(.center)
        } actions: {
            if !isFavorites && !hasSearch {
                Button(action: importAction) {
                    Label("导入文件", systemImage: "plus")
                }
                .adaptiveProminentButton()

                Button(action: importFolderAction) {
                    Label("选择文件夹", systemImage: "folder.badge.plus")
                }
                .adaptiveGlassButton()
            }
        }
        .onAppear { floating = true }
    }

    private var description: String {
        if hasSearch { return "没有找到匹配的读物" }
        if isFavorites { return "长按书架中的封面即可加入收藏" }
        return "支持 PDF、CBZ、ZIP、图片和整个文件夹\n源文件始终原样保留在设备上"
    }
}
