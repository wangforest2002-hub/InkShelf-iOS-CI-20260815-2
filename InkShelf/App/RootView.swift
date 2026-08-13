import SwiftUI

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(RemoteLibraryStore.self) private var remoteLibrary
    @Environment(ICloudLibraryStore.self) private var iCloudLibrary
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
                await remoteLibrary.loadIfNeeded()
                await iCloudLibrary.loadIfNeeded()
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
                        ReaderView(book: book)
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
            Tab("小家", systemImage: "house.fill") {
                LibraryView(scope: .all)
            }

            Tab("珍藏", systemImage: "heart.fill") {
                LibraryView(scope: .favorites)
            }

            Tab("云阁楼", systemImage: "externaldrive.fill.badge.icloud") {
                RemoteLibraryView()
            }

            Tab("设置", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
    }
}
