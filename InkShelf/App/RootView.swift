import SwiftUI

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppUpdateStore.self) private var updates
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var launchDestination: LaunchDestination?
    @State private var updatePrompt: AppUpdateRelease?

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
                if !hasSeen {
                    launchDestination = .welcome
                } else {
                    Task { await offerUpdateIfAvailable() }
                }
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
            .task {
                guard hasSeenWelcome, library.interruptedReadingBook == nil else { return }
                await offerUpdateIfAvailable()
            }
            .sheet(item: $updatePrompt) { release in
                AppUpdatePromptView(release: release)
            }
    }

    @MainActor
    private func offerUpdateIfAvailable() async {
        guard !ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_SEED"),
              !ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_PICKER")
        else { return }
        if !updates.didCheckThisLaunch {
            await updates.checkForUpdates(silent: true)
        }
        guard launchDestination == nil,
              updates.shouldOfferAutomaticPrompt,
              let release = updates.availableRelease
        else { return }
        updatePrompt = release
    }
}

private enum LaunchDestination: Identifiable, Equatable {
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
