import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let scope: LibraryScope

    @State private var query = ""
    @State private var importPicker: ImportPicker?
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pendingDeletion: Book?
    @State private var renamingBook: Book?
    @State private var previewingBook: Book?
    @State private var openedBook: Book?
    @Namespace private var coverTransition

    private var books: [Book] {
        library.filteredBooks(scope: scope, query: query)
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: horizontalSizeClass == .compact ? 142 : 176, maximum: 230), spacing: 18)]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                if books.isEmpty {
                    EmptyLibraryView(
                        isFavorites: scope == .favorites,
                        hasSearch: !query.isEmpty,
                        importAction: { importPicker = .files },
                        importFolderAction: { importPicker = .folder }
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if query.isEmpty {
                                if scope == .all {
                                    HomeWelcomeHeader(
                                        bookCount: library.books.count,
                                        favoriteCount: library.books.filter(\.isFavorite).count
                                    )

                                    if let continueBook = library.continueReadingBook {
                                        Button { open(continueBook) } label: {
                                            ContinueReadingCard(
                                                book: continueBook,
                                                coverURL: library.coverURL(for: continueBook)
                                            )
                                        }
                                        .buttonStyle(PressableCardStyle())
                                    }
                                } else {
                                    LibrarySectionHeading(
                                        title: "珍藏角落",
                                        subtitle: "喜欢的故事，都替你安静收在这里",
                                        symbol: "heart.fill"
                                    )
                                }
                            }

                            LibrarySectionHeading(
                                title: scope == .all ? "家里的书架" : "我的珍藏",
                                subtitle: "\(books.count) 本读物",
                                symbol: scope == .all ? "books.vertical.fill" : "star.fill"
                            )

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
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 110)
                    }
                    .scrollIndicators(.hidden)
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
            .navigationTitle(scope == .all ? "二次元小家" : "珍藏角落")
            .searchable(text: $query, prompt: "搜索标题")
            .toolbar {
                if scope == .all {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                importPicker = .files
                            } label: {
                                Label("导入文件或图片", systemImage: "doc.badge.plus")
                            }

                            Button {
                                importPicker = .folder
                            } label: {
                                Label("导入文件夹画集", systemImage: "folder.badge.plus")
                            }

                            Button {
                                showPhotoPicker = true
                            } label: {
                                Label("从照片导入", systemImage: "photo.badge.plus")
                            }
                        } label: {
                            Label("导入", systemImage: "plus")
                        }
                        .accessibilityHint("从文件 App 导入 PDF、EPUB、电子书、CBZ、ZIP 或图片")
                    }
                }
            }
            .navigationDestination(item: $openedBook) { book in
                ReaderView(book: book)
                    .navigationTransition(.zoom(sourceID: book.id, in: coverTransition))
            }
        }
        .sheet(item: $importPicker) { picker in
            DocumentPickerView(
                contentTypes: picker == .files ? UTType.inkShelfFileTypes : [.folder],
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
        .sheet(item: $renamingBook) { book in
            RenameBookView(book: book) { title in
                library.rename(book.id, to: title)
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $previewingBook) { book in
            GalleryOverviewView(book: book, imageURLs: library.pageURLs(for: book))
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

    private func handleImportResult(
        _ result: Result<[URL], Error>,
        removeSourcesAfterImport: Bool = false
    ) {
        switch result {
        case .success(let urls):
            library.importFiles(urls, removeSourcesAfterImport: removeSourcesAfterImport)
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

    private var pickerSmokeDirectory: URL? {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_PICKER") else { return nil }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PickerSmokeInbox", isDirectory: true)
#else
        return nil
#endif
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
            library.importFiles(urls, cleanupDirectory: temporaryRoot)
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

private enum ImportPicker: String, Identifiable {
    case files
    case folder

    var id: String { rawValue }
}

private struct ContinueReadingCard: View {
    let book: Book
    let coverURL: URL?

    var body: some View {
        HStack(spacing: 16) {
            Group {
                if let coverURL, let image = UIImage(contentsOfFile: coverURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
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
            .frame(width: 72, height: 94)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Label("为你留着位置", systemImage: "lamp.table.fill")
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
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

private struct HomeWelcomeHeader: View {
    let bookCount: Int
    let favoriteCount: Int
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                greetingCopy
                Spacer(minLength: 8)
                CozyWindowView()
                    .frame(width: 116, height: 88)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    greetingCopy
                    Spacer(minLength: 4)
                    CozyWindowView()
                        .frame(width: 82, height: 64)
                }
            }
        }
        .padding(18)
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
        .shadow(color: AppTheme.honey.opacity(0.12), radius: 24, y: 12)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.55)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var greetingCopy: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(greeting, systemImage: "house.fill")
                .font(.title2.bold())
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.wood, AppTheme.coral, AppTheme.accent],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                HomeStatChip(symbol: "books.vertical.fill", text: "\(bookCount) 本")
                if favoriteCount > 0 {
                    HomeStatChip(symbol: "heart.fill", text: "\(favoriteCount) 份喜欢")
                }
            }
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
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.28), in: Capsule())
    }
}

private struct LibrarySectionHeading: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
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
