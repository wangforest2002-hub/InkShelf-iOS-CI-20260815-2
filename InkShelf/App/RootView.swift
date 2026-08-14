import SwiftUI

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var launchDestination: LaunchDestination?

    var body: some View {
        MainTabView()
            .task {
                if !hasSeenWelcome {
                    launchDestination = .welcome
                } else if let book = library.interruptedReadingBook {
                    launchDestination = .reader(book)
                }
            }
            .onChange(of: hasSeenWelcome) { _, hasSeen in
                if !hasSeen { launchDestination = .welcome }
            }
            .fullScreenCover(item: $launchDestination) { destination in
                switch destination {
                case .welcome:
                    WelcomeView {
                        hasSeenWelcome = true
                        launchDestination = nil
                    }
                case .reader(let book):
                    NavigationStack {
                        ReaderView(book: book) { launchDestination = nil }
                    }
                }
            }
    }
}

private enum LaunchDestination: Identifiable {
    case welcome
    case reader(Book)

    var id: String {
        switch self {
        case .welcome: "welcome"
        case .reader(let book): "reader-\(book.id.uuidString)"
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

            Tab("最近", systemImage: "clock.fill") {
                LibraryView(scope: .recent)
            }

            Tab("珍藏", systemImage: "star.fill") {
                LibraryView(scope: .favorites)
            }

            Tab("设置", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
    }
}
