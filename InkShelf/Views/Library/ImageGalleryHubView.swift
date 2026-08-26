import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ImageGalleryHubView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ambientMotionEnabled) private var ambientMotionEnabled
    @State private var section: ImageGallerySection = .imports
    @State private var query = ""
    @State private var showFilePicker = false
    @State private var showPhotoPicker = false
    @State private var showSocialPostImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var openedBook: Book?
    @State private var previewingBook: Book?
    @State private var profileEditingBook: Book?
    @State private var pendingDeletion: Book?
    @Namespace private var coverTransition

    private var imageBooks: [Book] {
        library.imageCollectionBooks
            .filter { $0.matchesLibrarySearch(query) }
    }

    private var favoriteBooks: [Book] {
        library.favoriteBooks
            .filter { $0.matchesLibrarySearch(query) }
    }

    private var favoritePages: [FavoritePageItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return library.favoritePageItems
        }
        return library.favoritePageItems.filter { $0.book.matchesLibrarySearch(query) }
    }

    private var gridColumns: [GridItem] {
        let minimum: CGFloat = horizontalSizeClass == .compact ? 142 : 176
        return [GridItem(.adaptive(minimum: minimum, maximum: 230), spacing: 18)]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ImageGalleryHero(
                            section: $section,
                            imageCount: library.imageCollectionBooks.count,
                            pageCount: library.favoritePageItems.count,
                            bookCount: library.favoriteBooks.count
                        )

                        Group { galleryContent }
                            .id(section)
                            .transition(.opacity)
                            .animation(reduceMotion ? nil : AppMotion.value, value: section)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)

                if library.isImporting {
                    GalleryImportOverlay(status: library.importStatusText)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                }

                if let notice = library.importNotice, !library.isImporting {
                    VStack {
                        Label(notice, systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .inkGlass(cornerRadius: 20)
                            .overlay { Capsule().stroke(AppTheme.mint.opacity(0.45), lineWidth: 1) }
                            .padding(.top, 8)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle("我的画廊")
            .searchable(text: $query, prompt: "搜索图片画集、收藏读物或来源")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AppearanceModeButton()
                }
                ToolbarItem(placement: .primaryAction) {
                    importMenu
                }
            }
            .navigationDestination(item: $openedBook) { book in
                ReaderView(book: book) { openedBook = nil }
                    .navigationTransition(.zoom(sourceID: book.id, in: coverTransition))
            }
        }
        .environment(\.ambientMotionEnabled, ambientMotionEnabled && openedBook == nil)
        .sheet(isPresented: $showFilePicker) {
            DocumentPickerView(
                contentTypes: [.image],
                allowsMultipleSelection: true,
                asCopy: true,
                onResult: { result in
                    showFilePicker = false
                    switch result {
                    case .success(let urls):
                        importImages(urls, removeSourcesAfterImport: true)
                    case .failure(let error):
                        library.alert = LibraryAlert(title: "无法导入图片", message: error.localizedDescription)
                    }
                },
                onCancel: { showFilePicker = false }
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
            SocialPostImportView(shelfGroupID: nil, favoriteOnImport: false)
        }
        .sheet(item: $previewingBook) { book in
            GalleryOverviewView(book: book, imageURLs: library.pageURLs(for: book))
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
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .alert(item: alertBinding) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("好")))
        }
        .confirmationDialog(
            "从小家删除？",
            isPresented: deletionPresented,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { book in
            Button("删除“\(book.title)”", role: .destructive) {
                library.delete(book)
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: { book in
            Text("会删除这项内容的本地副本；其他画集、单页珍藏和收藏读物不会受到影响。")
        }
    }

    @ViewBuilder
    private var galleryContent: some View {
        switch section {
        case .imports:
            GallerySectionHeading(
                title: "独立导入的图片",
                subtitle: "照片、文件和 X 帖子图片会组成自己的画集",
                symbol: "photo.on.rectangle.angled"
            )
            if imageBooks.isEmpty {
                GalleryEmptyCard(
                    title: query.isEmpty ? "还没有图片画集" : "没有找到对应图片",
                    message: query.isEmpty ? "从系统照片、文件 App 或 X 帖子带回喜欢的图片。它们不会再和阅读中的单页收藏混在一起。" : "换个关键词试试。",
                    symbol: "photo.badge.plus",
                    actionTitle: query.isEmpty ? "导入图片" : nil,
                    action: { showPhotoPicker = true }
                )
            } else {
                bookGrid(imageBooks)
            }

        case .favoritePages:
            GallerySectionHeading(
                title: "阅读中收藏的画面",
                subtitle: "只收纳你在阅读器里点亮爱心的单页",
                symbol: "heart.rectangle.stack.fill"
            )
            if favoritePages.isEmpty {
                GalleryEmptyCard(
                    title: query.isEmpty ? "心动单页还空着" : "没有找到对应收藏",
                    message: query.isEmpty ? "阅读画册时点一下工具栏里的爱心，这一页就会单独回到这里。" : "换个书名、标签或来源试试。",
                    symbol: "heart.circle",
                    actionTitle: nil,
                    action: {}
                )
            } else {
                FavoritePageGrid(items: favoritePages) { item in
                    var target = item.book
                    target.currentPage = item.page
                    open(target)
                }
            }

        case .favoriteBooks:
            GallerySectionHeading(
                title: "收藏的整本读物",
                subtitle: "PDF、漫画、电子书和画集的整本收藏",
                symbol: "star.fill"
            )
            if favoriteBooks.isEmpty {
                GalleryEmptyCard(
                    title: query.isEmpty ? "还没有整本收藏" : "没有找到对应读物",
                    message: query.isEmpty ? "在书架长按一本读物并选择“收藏”，它会出现在这里。" : "换个关键词试试。",
                    symbol: "star",
                    actionTitle: nil,
                    action: {}
                )
            } else {
                bookGrid(favoriteBooks)
            }
        }
    }

    private func bookGrid(_ books: [Book]) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 24) {
            ForEach(books) { book in
                Button { open(book) } label: {
                    BookCard(
                        book: book,
                        coverURL: library.coverURL(for: book),
                        previewURLs: library.previewURLs(for: book)
                    )
                    .matchedTransitionSource(id: book.id, in: coverTransition)
                }
                .buttonStyle(PressableCardStyle())
                .contextMenu { galleryContextMenu(book) }
            }
        }
    }

    private var importMenu: some View {
        Menu {
            Button {
                showPhotoPicker = true
            } label: {
                Label("从系统照片导入", systemImage: "photo.badge.plus")
            }

            Button {
                showFilePicker = true
            } label: {
                Label("从文件或 iCloud 导入图片", systemImage: "folder.badge.plus")
            }

            Button {
                showSocialPostImporter = true
            } label: {
                Label("从 X 帖子导入图片", systemImage: "heart.text.square")
            }
        } label: {
            Label("导入图片", systemImage: "plus")
        }
        .accessibilityIdentifier("gallery-import")
    }

    @ViewBuilder
    private func galleryContextMenu(_ book: Book) -> some View {
        if book.kind == .imageCollection {
            Button {
                previewingBook = book
            } label: {
                Label("预览全部图片", systemImage: "square.grid.2x2")
            }
        }

        Button {
            library.toggleFavorite(book.id)
        } label: {
            Label(book.isFavorite ? "取消整本收藏" : "收藏整本", systemImage: book.isFavorite ? "star.slash" : "star")
        }

        Button {
            profileEditingBook = book
        } label: {
            Label("编辑心动档案", systemImage: "heart.text.square")
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
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    private func open(_ book: Book) {
        if let error = library.openingError(for: book) {
            library.alert = error
        } else {
            openedBook = book
        }
    }

    private func importImages(_ urls: [URL], removeSourcesAfterImport: Bool = false) {
        library.importFiles(
            urls,
            removeSourcesAfterImport: removeSourcesAfterImport,
            shelfGroupID: nil,
            favoriteOnImport: false
        )
        section = .imports
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("InkShelfGalleryImport", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let temporaryFolder = temporaryRoot.appendingPathComponent("我的图片", isDirectory: true)

        do {
            try fileManager.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
            var urls: [URL] = []
            for (index, item) in items.enumerated() {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let ext = item.supportedContentTypes.compactMap(\.preferredFilenameExtension).first ?? "jpg"
                let url = temporaryFolder.appendingPathComponent(String(format: "%06d.%@", index + 1, ext))
                try data.write(to: url, options: .atomic)
                urls.append(url)
            }
            guard !urls.isEmpty else { throw BookImportError.noImages }
            library.importFiles(urls, cleanupDirectory: temporaryRoot, favoriteOnImport: false)
            section = .imports
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

private enum ImageGallerySection: String, CaseIterable, Identifiable {
    case imports
    case favoritePages
    case favoriteBooks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .imports: "我的图片"
        case .favoritePages: "心动单页"
        case .favoriteBooks: "收藏读物"
        }
    }

    var systemImage: String {
        switch self {
        case .imports: "photo.stack.fill"
        case .favoritePages: "heart.rectangle.stack.fill"
        case .favoriteBooks: "star.fill"
        }
    }
}

private struct ImageGalleryHero: View {
    @Binding var section: ImageGallerySection
    let imageCount: Int
    let pageCount: Int
    let bookCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(AppTheme.coral.opacity(0.14))
                    Image(systemName: "photo.artframe")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.coral)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text("把喜欢的画面分门安放")
                        .font(.headline)
                    Text("导入图片与阅读收藏互不混放，一眼就能找到。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Picker("画廊区域", selection: $section) {
                ForEach(ImageGallerySection.allCases) { item in
                    Label(item.title, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("gallery-section-picker")

            HStack(spacing: 8) {
                GalleryCountChip(symbol: "photo.stack.fill", count: imageCount, title: "图片")
                GalleryCountChip(symbol: "heart.fill", count: pageCount, title: "单页")
                GalleryCountChip(symbol: "star.fill", count: bookCount, title: "读物")
            }
        }
        .padding(18)
        .inkGlass(cornerRadius: 28)
        .overlay { WarmLightSweep().clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous)) }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(reduceMotion ? nil : AppMotion.reveal) { appeared = true }
        }
    }
}

private struct GalleryCountChip: View {
    let symbol: String
    let count: Int
    let title: String

    var body: some View {
        Label("\(count) \(title)", systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.08), in: Capsule())
            .contentTransition(.numericText())
    }
}

private struct GallerySectionHeading: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct GalleryEmptyCard: View {
    let title: String
    let message: String
    let symbol: String
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.coral)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 34)
        .inkGlass(cornerRadius: 26)
    }
}

private struct GalleryImportOverlay: View {
    let status: String?

    var body: some View {
        VStack(spacing: 13) {
            ProgressView().controlSize(.large).tint(AppTheme.accent)
            Text(status ?? "正在整理图片…")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("完成后会进入“我的图片”，不会自动混入心动单页")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .inkGlass(cornerRadius: 26)
        .shadow(color: .black.opacity(0.15), radius: 24, y: 10)
    }
}
