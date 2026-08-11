import SwiftUI

struct RootView: View {
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false

    var body: some View {
        MainTabView()
            .task {
                showWelcome = !hasSeenWelcome
            }
            .onChange(of: hasSeenWelcome) { _, hasSeen in
                if !hasSeen { showWelcome = true }
            }
            .fullScreenCover(isPresented: $showWelcome) {
                WelcomeView {
                    hasSeenWelcome = true
                    showWelcome = false
                }
            }
    }
}

private struct MainTabView: View {
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                tabs
                    .tabBarMinimizeBehavior(.onScrollDown)
            } else {
                tabs
            }
        }
        .tint(AppTheme.accent)
    }

    private var tabs: some View {
        TabView {
            Tab("书架", systemImage: "books.vertical.fill") {
                LibraryView(scope: .all)
            }

            Tab("收藏", systemImage: "star.fill") {
                LibraryView(scope: .favorites)
            }

            Tab("设置", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
    }
}
