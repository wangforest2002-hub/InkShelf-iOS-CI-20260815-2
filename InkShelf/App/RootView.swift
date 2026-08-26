import SwiftUI
import UIKit

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppUpdateStore.self) private var updates
    @Environment(SocialImportStore.self) private var socialImports
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var launchDestination: LaunchDestination?
    @State private var updatePrompt: AppUpdateRelease?

    var body: some View {
        MainTabView(
            isActive: launchDestination == nil
                && updatePrompt == nil
                && socialImports.pendingRequest == nil
                && library.duplicateImportPrompt == nil
        )
            .task {
                let launchArguments = ProcessInfo.processInfo.arguments
                if launchArguments.contains("INKSHELF_UI_TEST_NIGHT")
                    || launchArguments.contains("INKSHELF_UI_TEST_SEED")
                    || launchArguments.contains("INKSHELF_UI_TEST_PICKER")
                    || launchArguments.contains("INKSHELF_UI_TEST_LONG_READER") {
                    hasSeenWelcome = true
                    launchDestination = nil
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
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    library.flushProgress()
                }
            }
            .sheet(item: duplicateImportBinding) { prompt in
                DuplicateImportDecisionView(prompt: prompt)
                    .interactiveDismissDisabled()
            }
    }

    private var socialImportBinding: Binding<SocialImportRequest?> {
        Binding(
            get: { socialImports.pendingRequest },
            set: { socialImports.pendingRequest = $0 }
        )
    }

    private var duplicateImportBinding: Binding<DuplicateImportPrompt?> {
        Binding(
            get: { library.duplicateImportPrompt },
            set: { _ in }
        )
    }

    @MainActor
    private func offerUpdateIfAvailable() async {
        guard !ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_SEED"),
              !ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_PICKER"),
              !ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_NIGHT"),
              !ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_LONG_READER")
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
    let isActive: Bool
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
                    .environment(\.ambientMotionEnabled, isActive && selectedTab == .library)
            }

            Tab("最近", systemImage: "clock.fill", value: .recent) {
                LibraryView(scope: .recent)
                    .environment(\.ambientMotionEnabled, isActive && selectedTab == .recent)
            }

            Tab("画廊", systemImage: "photo.stack.fill", value: .gallery) {
                ImageGalleryHubView()
                    .environment(\.ambientMotionEnabled, isActive && selectedTab == .gallery)
            }

            Tab("设置", systemImage: "gearshape.fill", value: .settings) {
                SettingsView()
                    .environment(\.ambientMotionEnabled, isActive && selectedTab == .settings)
            }
        }
    }

}

private struct DuplicateImportDecisionView: View {
    @Environment(LibraryStore.self) private var library
    let prompt: DuplicateImportPrompt

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("发现完全一致的内容", systemImage: "doc.on.doc.fill")
                        .font(.headline)
                        .foregroundStyle(AppTheme.honey)
                    Text("二次元小家比较的是文件或画册页面的实际内容，不会只因为名称相同就拦住导入。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("重复项目") {
                    ForEach(prompt.matches) { match in
                        HStack(spacing: 12) {
                            Group {
                                if let coverURL = library.coverURL(for: match.existingBook) {
                                    CoverArtwork(book: match.existingBook, coverURL: coverURL, previewURLs: [])
                                } else {
                                    Image(systemName: match.existingBook.kind.systemImage)
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                            .frame(width: 44, height: 58)
                            .background(AppTheme.cream.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(match.importedBook.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                Text("书架中已有“\(match.existingBook.title)”")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        library.resolveDuplicateImport(keepCopies: false)
                    } label: {
                        Label("跳过重复项目", systemImage: "arrow.uturn.backward.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("duplicate-import-skip")

                    Button {
                        library.resolveDuplicateImport(keepCopies: true)
                    } label: {
                        Label("仍然保留副本", systemImage: "plus.square.on.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("duplicate-import-keep")
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("重复画册提醒")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private enum MainTab: Hashable {
    case library
    case recent
    case gallery
    case settings
}
