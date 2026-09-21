import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AchievementStore.self) private var achievements
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.ambientMotionEnabled) private var ambientMotionEnabled
    let scope: LibraryScope

    @AppStorage("library.sortOrder") private var sortOrderRaw = LibrarySortOrder.lastOpened.rawValue
    @AppStorage("library.readingStatus") private var readingStatusRaw = ReadingStatusFilter.all.rawValue
    @AppStorage("library.gridDensity") private var gridDensityRaw = LibraryGridDensity.comfortable.rawValue
    @State private var query = ""
    @State private var importPicker: ImportPicker?
    @State private var showPhotoPicker = false
    @State private var showSocialPostImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pendingDeletion: Book?
    @State private var renamingBook: Book?
    @State private var previewingBook: Book?
    @State private var aiWritingBook: Book?
    @State private var profileEditingBook: Book?
    @State private var openedBook: Book?
    @State private var didAutoPresentPickerForUITest = false
    @State private var showAchievements = false
    @State private var shelfFilter: ShelfFilter = .all
    @State private var transientCoverAspectRatios: [UUID: CGFloat] = [:]
    @State private var shelfContentVisible = false
    @State private var groupEditor: ShelfGroupEditorTarget?
    @State private var pendingGroupDeletion: ShelfGroup?
    @Namespace private var coverTransition

    private var sortOrder: LibrarySortOrder {
        LibrarySortOrder(rawValue: sortOrderRaw) ?? .lastOpened
    }

    private var readingStatus: ReadingStatusFilter {
        ReadingStatusFilter(rawValue: readingStatusRaw) ?? .all
    }

    private var gridDensity: LibraryGridDensity {
        LibraryGridDensity(rawValue: gridDensityRaw) ?? .comfortable
    }

    private var presentationSortOrder: LibrarySortOrder {
        scope == .recent ? .lastOpened : sortOrder
    }

    private var presentationReadingStatus: ReadingStatusFilter {
        scope == .recent ? .all : readingStatus
    }

    private var books: [Book] {
        let filtered = library.filteredBooks(
            scope: scope,
            query: query,
            sortOrder: presentationSortOrder,
            status: presentationReadingStatus
        )
        guard scope == .all else { return filtered }
        switch shelfFilter {
        case .all:
            return filtered
        case .ungrouped:
            return filtered.filter { $0.shelfGroupID == nil }
        case .group(let id):
            return filtered.filter { $0.shelfGroupID == id }
        }
    }

    private var keepsShelfVisibleWhenEmpty: Bool {
        scope == .all && query.isEmpty && shelfFilter != .all && !library.books.isEmpty
    }

    private var shelfColumnCount: Int {
        if horizontalSizeClass == .compact { return 2 }
        return gridDensity == .compact ? 5 : 4
    }

    private var shelfGridSpacing: CGFloat {
        gridDensity == .compact ? 14 : 18
    }

    private var shelfRows: [ShelfBookRow] {
        ShelfBookRow.make(
            books: books,
            columns: shelfColumnCount,
            aspectRatio: coverAspectRatio(for:)
        )
    }

    private var shelfFilterSelection: Binding<ShelfFilter> {
        Binding(
            get: { shelfFilter },
            set: selectShelfFilter
        )
    }

    private var shelfPresentationID: ShelfPresentationID {
        ShelfPresentationID(
            filter: shelfFilter,
            queryIsEmpty: query.isEmpty,
            bookIDs: books.map(\.id)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                if books.isEmpty
                    && !(scope == .favorites && !library.favoritePageItems.isEmpty)
                    && !keepsShelfVisibleWhenEmpty {
                    EmptyLibraryView(
                        scope: scope,
                        hasSearch: !query.isEmpty,
                        importAction: { importPicker = .files }
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if query.isEmpty, scope == .all {
                                ShelfGroupStrip(
                                    selection: shelfFilterSelection,
                                    groups: library.shelfGroups,
                                    totalCount: library.books.count,
                                    ungroupedCount: library.books.filter { $0.shelfGroupID == nil }.count,
                                    countForGroup: library.bookCount(inShelfGroup:),
                                    create: { groupEditor = .create },
                                    rename: { groupEditor = .rename($0) },
                                    delete: { pendingGroupDeletion = $0 }
                                )
                            }

                            VStack(alignment: .leading, spacing: 18) {
                                if query.isEmpty, scope == .all {
                                    if shelfFilter == .all {
                                        HomeWelcomeHeader(
                                            bookCount: library.books.count,
                                            favoriteCount: library.books.filter(\.isFavorite).count
                                        )

                                        if colorScheme == .dark {
                                            NightModeShelfCard(
                                                allBookCount: library.books.count,
                                                adultBookCount: library.afterDarkBooks.count,
                                                favoritePageCount: library.favoritePageItems.count,
                                                featuredBook: library.afterDarkBooks.first
                                                    ?? library.continueReadingBook
                                                    ?? library.books.first,
                                                openFeatured: open
                                            )
                                        }

                                        homeActivityCards
                                    }
                                } else if query.isEmpty, scope == .favorites {
                                    LibrarySectionHeading(
                                        title: "珍藏角落",
                                        subtitle: "整本与单页，都替你安静收在这里",
                                        symbol: "star.fill"
                                    )
                                }

                                if scope == .favorites && !library.favoritePageItems.isEmpty && query.isEmpty {
                                    FavoritePageGrid(items: library.favoritePageItems) { item in
                                        var target = item.book
                                        target.currentPage = item.page
                                        open(target)
                                    }
                                }

                                if !books.isEmpty {
                                    LibrarySectionHeading(
                                        title: sectionTitle,
                                        subtitle: sectionSubtitle,
                                        symbol: sectionSymbol
                                    )

                                    LazyVStack(spacing: gridDensity == .compact ? 18 : 24) {
                                        ForEach(shelfRows) { row in
                                            ShelfBookRowLayout(
                                                columns: shelfColumnCount,
                                                spacing: shelfGridSpacing
                                            ) {
                                                ForEach(row.items) { item in
                                                    shelfBookButton(item.book)
                                                        .shelfColumnSpan(item.span)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                } else if keepsShelfVisibleWhenEmpty {
                                    EmptyShelfGroupCard(createGroup: false)
                                }
                            }
                            .opacity(shelfContentOpacity)
                            .offset(y: reduceMotion || shelfContentVisible ? 0 : 3)
                            .id(shelfPresentationID)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 110)
                        // A horizontally scrolling group strip and a wide
                        // welcome card must never define the width of the
                        // vertical shelf. Otherwise compact devices can lay
                        // out extra grid columns beyond the visible viewport.
                        .containerRelativeFrame(.horizontal, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .task(id: shelfPresentationID) {
                        await prepareShelfPresentation()
                    }
                }

                if library.isImporting {
                    ImportOverlay(status: library.importStatusText)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }

                if let notice = library.importNotice, !library.isImporting {
                    VStack {
                        ImportSuccessToast(text: notice)
                            .padding(.top, 8)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle(navigationTitle)
            .searchable(text: $query, prompt: "搜索标题、标签、文件名或笔记")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AppearanceModeButton()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if scope == .recent {
                            Label("按最近打开自动排序", systemImage: "clock.arrow.circlepath")
                            Text("这里只显示真正翻开过的读物")
                        } else {
                            Picker("排序方式", selection: $sortOrderRaw) {
                                ForEach(LibrarySortOrder.allCases) { order in
                                    Label(order.title, systemImage: order.systemImage).tag(order.rawValue)
                                }
                            }

                            Picker("阅读状态", selection: $readingStatusRaw) {
                                ForEach(ReadingStatusFilter.allCases) { status in
                                    Label(status.title, systemImage: status.systemImage).tag(status.rawValue)
                                }
                            }
                        }

                        Divider()

                        Picker("封面密度", selection: $gridDensityRaw) {
                            ForEach(LibraryGridDensity.allCases) { density in
                                Label(density.title, systemImage: density.systemImage).tag(density.rawValue)
                            }
                        }
                    } label: {
                        Label("整理书架", systemImage: "arrow.up.arrow.down.circle")
                    }
                    .accessibilityIdentifier("library-organize")
                    .accessibilityHint("调整排序、阅读状态和封面大小")
                }

                if scope == .all || scope == .favorites {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                importPicker = .files
                            } label: {
                                Label("批量导入文件或图片", systemImage: "doc.on.doc")
                            }

                            Button {
                                showPhotoPicker = true
                            } label: {
                                Label(scope == .favorites ? "从照片加入珍藏" : "从照片导入", systemImage: "photo.badge.plus")
                            }

                            Button {
                                showSocialPostImporter = true
                            } label: {
                                Label("从 X 收藏帖子图片", systemImage: "heart.text.square")
                            }

                            if scope == .all {
                                Divider()

                                Button {
                                    groupEditor = .create
                                } label: {
                                    Label("新建书架分组", systemImage: "folder.badge.plus")
                                }
                            }
                        } label: {
                            Label(scope == .favorites ? "加入珍藏" : "导入", systemImage: "plus")
                        }
                        .accessibilityHint("从文件 App 导入 PDF、EPUB、电子书、CBZ、ZIP 或图片")
                    }
                }
            }
            .navigationDestination(item: $openedBook) { book in
                ReaderView(book: book) { openedBook = nil }
                    .navigationTransition(.zoom(sourceID: book.id, in: coverTransition))
            }
        }
        .environment(\.ambientMotionEnabled, ambientMotionEnabled && openedBook == nil)
        .sheet(item: $importPicker) { picker in
            DocumentPickerView(
                contentTypes: UTType.inkShelfFileTypes,
                allowsMultipleSelection: true,
                asCopy: true,
                directoryURL: pickerSmokeDirectory,
                onResult: { result in
                    importPicker = nil
                    handleImportResult(result, removeSourcesAfterImport: true)
                },
                onCancel: { importPicker = nil }
            )
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoItems,
            maxSelectionCount: 500,
            matching: .images,
            preferredItemEncoding: .current
        )
        .sheet(isPresented: $showSocialPostImporter) {
            SocialPostImportView(
                shelfGroupID: importDestinationGroupID,
                favoriteOnImport: false
            )
        }
        .onAppear {
#if DEBUG
            guard ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_PICKER"),
                  !didAutoPresentPickerForUITest
            else { return }
            didAutoPresentPickerForUITest = true
            Task { @MainActor in
                await Task.yield()
                importPicker = .files
            }
#endif
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .alert(item: alertBinding) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("好")))
        }
        .confirmationDialog(
            "从书架删除？",
            isPresented: deletionPresented,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { book in
            Button("删除", role: .destructive) {
                library.delete(book)
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { book in
            Text("“\(book.title)”及其本地副本将被删除，此操作无法撤销。")
        }
        .confirmationDialog(
            "删除这个分组？",
            isPresented: shelfGroupDeletionPresented,
            titleVisibility: .visible,
            presenting: pendingGroupDeletion
        ) { group in
            Button("删除“\(group.title)”", role: .destructive) {
                if shelfFilter == .group(group.id) { selectShelfFilter(.all) }
                library.deleteShelfGroup(group.id)
                pendingGroupDeletion = nil
            }
            Button("取消", role: .cancel) { pendingGroupDeletion = nil }
        } message: { group in
            Text("只会删除分组，里面的 \(library.bookCount(inShelfGroup: group.id)) 本读物会回到“未分组”，文件不会被删除。")
        }
        .sheet(item: $groupEditor) { target in
            switch target {
            case .create:
                ShelfGroupEditorView(navigationTitle: "新建分组") { title in
                    if let group = library.createShelfGroup(title: title) {
                        selectShelfFilter(.group(group.id))
                    }
                }
            case .rename(let group):
                ShelfGroupEditorView(
                    navigationTitle: "重命名分组",
                    initialTitle: group.title
                ) { title in
                    library.renameShelfGroup(group.id, to: title)
                }
            }
        }
        .sheet(item: $renamingBook) { book in
            RenameBookView(book: book) { title in
                library.rename(book.id, to: title)
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $previewingBook) { book in
            GalleryOverviewView(book: book)
        }
        .sheet(item: $aiWritingBook) { book in
            NavigationStack {
                AIWritingStudioView(book: book)
            }
        }
        .sheet(item: $profileEditingBook) { book in
            BookProfileEditorView(book: book) { profile in
                library.updateBookProfile(
                    bookID: book.id,
                    isAfterDark: profile.isAfterDark,
                    mood: profile.mood,
                    tags: profile.tags,
                    personalNote: profile.personalNote,
                    heartRating: profile.heartRating,
                    spiceRating: profile.spiceRating
                )
            }
        }
        .sheet(isPresented: $showAchievements) {
            NavigationStack {
                AchievementsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showAchievements = false }
                        }
                    }
            }
        }
    }

    private var shelfContentOpacity: Double {
        guard scope == .all, query.isEmpty else { return 1 }
        return shelfContentVisible ? 1 : 0
    }

    private func coverAspectRatio(for book: Book) -> CGFloat? {
        let ratio = transientCoverAspectRatios[book.id]
            ?? book.coverAspectRatio.map { CGFloat($0) }
        guard let ratio, ratio.isFinite, ratio >= 0.2, ratio <= 5 else { return nil }
        return ratio
    }

    private func selectShelfFilter(_ next: ShelfFilter) {
        guard next != shelfFilter else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            shelfContentVisible = false
            shelfFilter = next
        }
    }

    @MainActor
    private func prepareShelfPresentation() async {
        guard scope == .all, query.isEmpty else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { shelfContentVisible = true }
            return
        }

        let requests = books.prefix(240).compactMap { book -> CoverRatioRequest? in
            guard coverAspectRatio(for: book) == nil,
                  let url = library.coverURL(for: book)
            else { return nil }
            return CoverRatioRequest(id: book.id, url: url)
        }
        guard !Task.isCancelled else { return }
        guard !requests.isEmpty else {
            withAnimation(reduceMotion ? nil : AppMotion.shelfReveal) {
                shelfContentVisible = true
            }
            return
        }

        let preparation = Task.detached(priority: .userInitiated) {
            var result: [UUID: CGFloat] = [:]
            for request in requests where !Task.isCancelled {
                if let ratio = CoverService.aspectRatio(at: request.url) {
                    result[request.id] = CGFloat(ratio)
                }
            }
            return result
        }
        let detected = await withTaskCancellationHandler {
            await preparation.value
        } onCancel: {
            preparation.cancel()
        }
        guard !Task.isCancelled else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            transientCoverAspectRatios.merge(detected) { _, new in new }
            shelfContentVisible = reduceMotion
        }
        guard !reduceMotion else { return }

        await Task.yield()
        guard !Task.isCancelled else { return }
        withAnimation(AppMotion.shelfReveal) {
            shelfContentVisible = true
        }
    }

    private func rememberCoverAspectRatio(_ ratio: CGFloat, for bookID: UUID) {
        guard ratio.isFinite, ratio >= 0.2, ratio <= 5,
              abs((transientCoverAspectRatios[bookID] ?? 0) - ratio) > 0.001
        else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            transientCoverAspectRatios[bookID] = ratio
        }
    }

    private func shelfBookButton(_ book: Book) -> some View {
        Button { open(book) } label: {
            BookCard(
                book: book,
                coverURL: library.coverURL(for: book),
                previewURLs: library.previewURLs(for: book),
                knownCoverAspectRatio: coverAspectRatio(for: book),
                onCoverAspectRatio: { rememberCoverAspectRatio($0, for: book.id) }
            )
            .matchedTransitionSource(id: book.id, in: coverTransition)
        }
        .buttonStyle(PressableCardStyle())
        .contextMenu {
            bookContextMenu(book)
        } preview: {
            BookPreview(
                book: book,
                coverURL: library.coverURL(for: book),
                previewURLs: library.previewURLs(for: book)
            )
        }
    }

    private var homeActivityCards: some View {
        let isWide = horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
        let layout = isWide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
        return layout {
            if let continueBook = library.continueReadingBook {
                Button { open(continueBook) } label: {
                    ContinueReadingCard(
                        book: continueBook,
                        coverURL: library.coverURL(for: continueBook),
                        minimumHeight: isWide ? 130 : 0
                    )
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityIdentifier("library-continue-reading")
                .frame(maxWidth: .infinity)
            }

            if !achievements.footprint.openedBookIDs.isEmpty {
                Button { showAchievements = true } label: {
                    FootprintHomeCard(
                        unlocked: achievements.unlockedCount,
                        total: achievements.achievements.count,
                        pages: achievements.footprint.pagesTurned,
                        minutes: achievements.readingMinutes,
                        level: achievements.homeLevel,
                        levelTitle: achievements.homeLevelTitle,
                        levelProgress: achievements.homeLevelProgress,
                        streak: achievements.currentStreak,
                        dailyCompleted: achievements.dailyQuests().filter(\.isCompleted).count,
                        minimumHeight: isWide ? 130 : 0
                    )
                }
                .buttonStyle(PressableCardStyle())
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func bookContextMenu(_ book: Book) -> some View {
        if book.kind == .archive || book.kind == .imageCollection {
            Button {
                previewingBook = book
            } label: {
                Label("预览画集", systemImage: "square.grid.2x2")
            }
        }

        Button {
            library.toggleFavorite(book.id)
        } label: {
            Label(book.isFavorite ? "取消收藏" : "收藏", systemImage: book.isFavorite ? "star.slash" : "star")
        }

        Button {
            renamingBook = book
        } label: {
            Label("重命名", systemImage: "pencil")
        }

        Button {
            aiWritingBook = book
        } label: {
            Label("AI 写文案", systemImage: "text.badge.star")
        }

        Button {
            profileEditingBook = book
        } label: {
            Label("编辑心动档案", systemImage: "heart.text.square")
        }

        Button {
            library.toggleAfterDark(book.id)
        } label: {
            Label(
                book.belongsToAfterDark ? "移出成年向档案" : "加入成年向档案",
                systemImage: book.belongsToAfterDark ? "18.circle" : "18.circle.fill"
            )
        }

        Menu {
            Button {
                library.assignBook(book.id, toShelfGroup: nil)
            } label: {
                Label("未分组", systemImage: book.shelfGroupID == nil ? "checkmark" : "tray")
            }

            ForEach(library.shelfGroups) { group in
                Button {
                    library.assignBook(book.id, toShelfGroup: group.id)
                } label: {
                    Label(
                        group.title,
                        systemImage: book.shelfGroupID == group.id ? "checkmark" : group.systemImage
                    )
                }
            }

            Divider()

            Button {
                groupEditor = .create
            } label: {
                Label("新建分组…", systemImage: "folder.badge.plus")
            }
        } label: {
            Label("移动到分组", systemImage: "folder")
        }

        if let sourceURL = library.sourceURL(for: book) {
            ShareLink(item: sourceURL) {
                Label("导出原文件", systemImage: "square.and.arrow.up")
            }
        }

        Divider()

        Button(role: .destructive) {
            pendingDeletion = book
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    private var alertBinding: Binding<LibraryAlert?> {
        Binding(get: { library.alert }, set: { library.alert = $0 })
    }

    private var deletionPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var shelfGroupDeletionPresented: Binding<Bool> {
        Binding(
            get: { pendingGroupDeletion != nil },
            set: { if !$0 { pendingGroupDeletion = nil } }
        )
    }

    private func handleImportResult(
        _ result: Result<[URL], Error>,
        removeSourcesAfterImport: Bool = false
    ) {
        switch result {
        case .success(let urls):
            library.importFiles(
                urls,
                removeSourcesAfterImport: removeSourcesAfterImport,
                shelfGroupID: importDestinationGroupID,
                favoriteOnImport: scope == .favorites
            )
        case .failure(let error):
            library.alert = LibraryAlert(title: "无法打开文件", message: error.localizedDescription)
        }
    }

    private func open(_ book: Book) {
        if let error = library.openingError(for: book) {
            library.alert = error
        } else {
            openedBook = book
        }
    }

    private var navigationTitle: String {
        switch scope {
        case .all: "我的书架"
        case .recent: "最近阅读"
        case .favorites: "珍藏角落"
        }
    }

    private var sectionTitle: String {
        if scope == .all, query.isEmpty {
            switch shelfFilter {
            case .all:
                break
            case .ungrouped:
                return "未分组"
            case .group(let id):
                return library.shelfGroups.first(where: { $0.id == id })?.title ?? "书架分组"
            }
        }
        switch scope {
        case .all: return "家里的书架"
        case .recent: return "最近翻开"
        case .favorites: return "收藏的读物"
        }
    }

    private var sectionSubtitle: String {
        var parts = ["\(books.count) 本读物", presentationSortOrder.title]
        if presentationReadingStatus != .all { parts.append(presentationReadingStatus.title) }
        return parts.joined(separator: " · ")
    }

    private var sectionSymbol: String {
        if scope == .all, query.isEmpty {
            switch shelfFilter {
            case .all:
                break
            case .ungrouped:
                return "tray.fill"
            case .group(let id):
                return library.shelfGroups.first(where: { $0.id == id })?.systemImage ?? "folder.fill"
            }
        }
        switch scope {
        case .all: return "books.vertical.fill"
        case .recent: return "clock.arrow.circlepath"
        case .favorites: return "star.fill"
        }
    }

    private var pickerSmokeDirectory: URL? {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_PICKER") else { return nil }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PickerSmokeInbox", isDirectory: true)
#else
        return nil
#endif
    }

    private var importDestinationGroupID: UUID? {
        guard scope == .all, case .group(let id) = shelfFilter else { return nil }
        return id
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("InkShelfPhotoImport", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let temporaryFolder = temporaryRoot.appendingPathComponent("照片画集", isDirectory: true)

        do {
            try fileManager.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
            var urls: [URL] = []
            for (index, item) in items.enumerated() {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let ext = item.supportedContentTypes
                    .compactMap(\.preferredFilenameExtension)
                    .first ?? "jpg"
                let url = temporaryFolder.appendingPathComponent(String(format: "%06d.%@", index + 1, ext))
                try data.write(to: url, options: .atomic)
                urls.append(url)
            }

            guard !urls.isEmpty else {
                throw BookImportError.noImages
            }
            library.importFiles(
                urls,
                cleanupDirectory: temporaryRoot,
                shelfGroupID: importDestinationGroupID,
                favoriteOnImport: scope == .favorites
            )
            photoItems = []
        } catch {
            try? fileManager.removeItem(at: temporaryRoot)
            photoItems = []
            library.alert = LibraryAlert(
                title: "无法导入照片",
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }
}

private struct ShelfPresentationID: Hashable {
    let filter: ShelfFilter
    let queryIsEmpty: Bool
    let bookIDs: [UUID]
}

private struct CoverRatioRequest: Sendable {
    let id: UUID
    let url: URL
}

struct ShelfBookRow: Identifiable {
    let items: [ShelfBookItem]

    var id: String {
        items.map { $0.book.id.uuidString }.joined(separator: "|")
    }

    static func make(
        books: [Book],
        columns: Int,
        aspectRatio: (Book) -> CGFloat?
    ) -> [ShelfBookRow] {
        let safeColumns = max(1, columns)
        var rows: [ShelfBookRow] = []
        var current: [ShelfBookItem] = []
        var remaining = safeColumns

        for book in books {
            let isLandscape = ShelfCoverLayout.isLandscape(aspectRatio(book))
            let span = isLandscape && safeColumns > 1 ? 2 : 1
            if span > remaining, !current.isEmpty {
                rows.append(ShelfBookRow(items: current))
                current = []
                remaining = safeColumns
            }
            current.append(ShelfBookItem(book: book, span: min(span, safeColumns)))
            remaining -= min(span, safeColumns)
        }
        if !current.isEmpty {
            rows.append(ShelfBookRow(items: current))
        }
        return rows
    }
}

struct ShelfBookItem: Identifiable {
    let book: Book
    let span: Int
    var id: UUID { book.id }
}

private struct ShelfColumnSpanKey: LayoutValueKey {
    static let defaultValue = 1
}

extension View {
    func shelfColumnSpan(_ span: Int) -> some View {
        layoutValue(key: ShelfColumnSpanKey.self, value: max(1, span))
    }
}

/// Each row is still created lazily by the surrounding LazyVStack. Landscape
/// covers consume two columns, while portrait covers keep the familiar dense
/// shelf. This avoids the eager cost of SwiftUI's non-lazy Grid.
struct ShelfBookRowLayout: Layout {
    let columns: Int
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = max(0, proposal.width ?? 320)
        let columnWidth = self.columnWidth(for: width)
        let height = subviews.reduce(CGFloat.zero) { result, subview in
            let span = min(max(1, subview[ShelfColumnSpanKey.self]), max(1, columns))
            let itemWidth = columnWidth * CGFloat(span) + spacing * CGFloat(span - 1)
            let size = subview.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
            return max(result, size.height)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let columnWidth = self.columnWidth(for: bounds.width)
        var x = bounds.minX
        for subview in subviews {
            let span = min(max(1, subview[ShelfColumnSpanKey.self]), max(1, columns))
            let itemWidth = columnWidth * CGFloat(span) + spacing * CGFloat(span - 1)
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: itemWidth, height: bounds.height)
            )
            x += itemWidth + spacing
        }
    }

    private func columnWidth(for availableWidth: CGFloat) -> CGFloat {
        let safeColumns = max(1, columns)
        let gaps = spacing * CGFloat(safeColumns - 1)
        return max(0, (availableWidth - gaps) / CGFloat(safeColumns))
    }
}

private enum ImportPicker: String, Identifiable {
    case files

    var id: String { rawValue }
}

private enum ShelfGroupEditorTarget: Identifiable {
    case create
    case rename(ShelfGroup)

    var id: String {
        switch self {
        case .create: "create"
        case .rename(let group): "rename-\(group.id.uuidString)"
        }
    }
}

private struct ContinueReadingCard: View {
    let book: Book
    let coverURL: URL?
    var minimumHeight: CGFloat = 0

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if coverURL != nil {
                    CoverArtwork(book: book, coverURL: coverURL, previewURLs: [])
                } else {
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0.75), .cyan.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: book.kind.systemImage)
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 64, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: AppTheme.wood.opacity(0.15), radius: 6, y: 4)

            VStack(alignment: .leading, spacing: 7) {
                Label("继续上次的故事", systemImage: "bookmark.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.wood)
                Text(book.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(book.progressLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: book.progress)
                    .tint(AppTheme.coral)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28, height: 28)
                .background(AppTheme.accent.opacity(0.09), in: Circle())
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
        .inkGlass(cornerRadius: 24, interactive: true)
        .overlay {
            WarmLightSweep()
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.honey.opacity(0.48), AppTheme.cyan.opacity(0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: AppTheme.wood.opacity(0.09), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("继续阅读 \(book.title)，\(book.progressLabel)")
    }
}

private struct NightModeShelfCard: View {
    let allBookCount: Int
    let adultBookCount: Int
    let favoritePageCount: Int
    let featuredBook: Book?
    let openFeatured: (Book) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                summary.frame(minWidth: 280, maxWidth: .infinity, alignment: .leading)
                featuredAction.frame(minWidth: 220, maxWidth: 340)
            }
            VStack(alignment: .leading, spacing: 12) {
                summary
                featuredAction
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [AppTheme.midnight.opacity(0.94), Color(red: 0.20, green: 0.10, blue: 0.22).opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityIdentifier("night-mode-library-card")
    }

    private var summary: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.peach)
                .frame(width: 42, height: 42)
                .background(AppTheme.peach.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("夜间模式已点亮")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(allBookCount) 本读物 · \(adultBookCount) 份成年档案 · \(favoritePageCount) 张心动单页")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.70))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var featuredAction: some View {
        if let featuredBook {
            Button {
                openFeatured(featuredBook)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: featuredBook.belongsToAfterDark ? "flame.fill" : "book.fill")
                        .foregroundStyle(AppTheme.peach)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(featuredBook.belongsToAfterDark ? "今晚继续心动" : "今晚继续阅读")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.peach)
                        Text(featuredBook.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressableCardStyle())
        }
    }
}
private struct HomeWelcomeHeader: View {
    let bookCount: Int
    let favoriteCount: Int
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var appeared = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                greetingCopy
                Spacer(minLength: 8)
                if !dynamicTypeSize.isAccessibilitySize {
                    CozyWindowView()
                        .frame(width: 92, height: 72)
                }
            }

            greetingCopy
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [AppTheme.nightLamp.opacity(0.42), AppTheme.lilac.opacity(0.12), AppTheme.accent.opacity(0.08)]
                            : [AppTheme.cream.opacity(0.80), AppTheme.cyan.opacity(0.10), AppTheme.peach.opacity(0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .inkGlass(cornerRadius: 28)
        .overlay {
            WarmLightSweep()
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.36), lineWidth: 1)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: reduceMotion || appeared ? 0 : 8)
        .onAppear {
            withAnimation(reduceMotion ? nil : AppMotion.reveal) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var greetingCopy: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(greeting)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    homeStats
                }
                VStack(alignment: .leading, spacing: 6) {
                    homeStats
                }
            }
        }
    }

    @ViewBuilder
    private var homeStats: some View {
        HomeStatChip(symbol: "books.vertical.fill", text: "\(bookCount) 本故事")
        if favoriteCount > 0 {
            HomeStatChip(symbol: "star.fill", text: "\(favoriteCount) 本珍藏")
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<11: "早安，欢迎回家"
        case 11..<18: "午后好，欢迎回家"
        default: "晚上好，欢迎回家"
        }
    }

    private var message: String {
        bookCount == 0 ? "把喜欢的故事带回家吧" : "暖光已经亮起，慢慢挑一本喜欢的"
    }
}

private struct HomeStatChip: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.honey.opacity(0.09), in: Capsule())
    }
}

private struct FootprintHomeCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    let unlocked: Int
    let total: Int
    let pages: Int
    let minutes: Int
    let level: Int
    let levelTitle: String
    let levelProgress: Double
    let streak: Int
    let dailyCompleted: Int
    var minimumHeight: CGFloat = 0

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(AppTheme.honey.opacity(0.18), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: appeared ? levelProgress : 0)
                    .stroke(AppTheme.accentGradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(level)").font(.headline.bold().monospacedDigit())
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Lv.\(level) \(levelTitle)").font(.headline)
                    if streak > 0 {
                        Label("\(streak)天", systemImage: "flame.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.coral)
                    }
                }
                Text("\(pages) 页 · \(minutes) 分钟 · \(unlocked)/\(total) 枚徽章")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Label("今日约定 \(dailyCompleted)/3", systemImage: dailyCompleted == 3 ? "checkmark.seal.fill" : "sun.max.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(dailyCompleted == 3 ? AppTheme.mint : AppTheme.wood)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
        .inkGlass(cornerRadius: 22, interactive: true)
        .onAppear {
            withAnimation(reduceMotion ? nil : AppMotion.reveal) { appeared = true }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LibrarySectionHeading: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                heading
                Spacer(minLength: 8)
                detail
            }
            VStack(alignment: .leading, spacing: 5) {
                heading
                detail
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var heading: some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private var detail: some View {
        Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct ImportOverlay: View {
    let status: String?

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(AppTheme.accent)
            Text(status ?? "正在整理书架…")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("原文件不会被压缩或转码")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .inkGlass(cornerRadius: 26)
        .shadow(color: .black.opacity(0.15), radius: 24, y: 10)
        .accessibilityElement(children: .combine)
    }
}

private struct ImportSuccessToast: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .inkGlass(cornerRadius: 20)
            .overlay {
                Capsule().stroke(AppTheme.mint.opacity(0.45), lineWidth: 1)
            }
            .shadow(color: AppTheme.mint.opacity(0.16), radius: 16, y: 8)
            .accessibilityAddTraits(.isStaticText)
    }
}

private struct RenameBookView: View {
    @Environment(\.dismiss) private var dismiss
    let book: Book
    let onSave: (String) -> Void
    @State private var title: String

    init(book: Book, onSave: @escaping (String) -> Void) {
        self.book = book
        self.onSave = onSave
        _title = State(initialValue: book.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("标题", text: $title)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit(save)
            }
            .navigationTitle("重命名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        onSave(title)
        dismiss()
    }
}
