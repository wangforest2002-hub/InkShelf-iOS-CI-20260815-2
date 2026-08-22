import SwiftUI

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppUpdateStore.self) private var updates
    @Environment(SocialImportStore.self) private var socialImports
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var launchDestination: LaunchDestination?
    @State private var updatePrompt: AppUpdateRelease?

    var body: some View {
        MainTabView()
            .task {
                if ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_NIGHT") {
                    hasSeenWelcome = true
                    return
                }
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
            .task {
                _ = await AIReliabilityConfigurationService.shared.refresh()
            }
            .sheet(item: $updatePrompt) { release in
                AppUpdatePromptView(release: release)
            }
            .sheet(item: socialImportBinding) { request in
                SocialPostImportView(
                    shelfGroupID: nil,
                    favoriteOnImport: false,
                    initialURL: request.postURL
                )
            }
    }

    private var socialImportBinding: Binding<SocialImportRequest?> {
        Binding(
            get: { socialImports.pendingRequest },
            set: { socialImports.pendingRequest = $0 }
        )
    }

    @MainActor
    private func offerUpdateIfAvailable() async {
        guard !ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_SEED"),
              !ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_PICKER"),
              !ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_NIGHT")
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
    @State private var selectedTab: MainTab = .library

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
        TabView(selection: $selectedTab) {
            Tab("书架", systemImage: "books.vertical.fill", value: .library) {
                LibraryView(scope: .all)
            }

            Tab("最近", systemImage: "clock.fill", value: .recent) {
                LibraryView(scope: .recent)
            }

            Tab("画廊", systemImage: "photo.stack.fill", value: .gallery) {
                ImageGalleryHubView()
            }

            Tab("设置", systemImage: "gearshape.fill", value: .settings) {
                SettingsView()
            }
        }
    }
}

private enum MainTab: Hashable {
    case library
    case recent
    case gallery
    case settings
}
