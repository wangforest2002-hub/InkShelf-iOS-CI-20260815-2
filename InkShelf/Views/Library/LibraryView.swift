import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let scope: LibraryScope

    @State private var query = ""
    @State private var showFileImporter = false
    @State private var showFolderImporter = false
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pendingDeletion: Book?
    @State private var renamingBook: Book?
    @State private var previewingBook: Book?
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
                        importAction: { showFileImporter = true },
                        importFolderAction: { showFolderImporter = true }
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 24) {
                            ForEach(books) { book in
                                NavigationLink(value: book) {
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
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 110)
                    }
                    .scrollIndicators(.hidden)
                }

                if library.isImporting {
                    ImportOverlay()
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .navigationTitle(scope == .all ? "墨阅书架" : "我的收藏")
            .searchable(text: $query, prompt: "搜索标题")
            .toolbar {
                if scope == .all {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                showFileImporter = true
                            } label: {
                                Label("导入文件或图片", systemImage: "doc.badge.plus")
                            }

                            Button {
                                showFolderImporter = true
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
                        .accessibilityHint("从文件 App 导入 PDF、CBZ、ZIP 或图片")
                    }
                }
            }
            .navigationDestination(for: Book.self) { book in
                ReaderView(book: book)
                    .navigationTransition(.zoom(sourceID: book.id, in: coverTransition))
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: UTType.inkShelfFileTypes,
            allowsMultipleSelection: true
        ) { handleImportResult($0) }
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
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { handleImportResult($0) }
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
        if book.kind != .pdf {
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

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            library.importFiles(urls)
        case .failure(let error):
            library.alert = LibraryAlert(title: "无法打开文件", message: error.localizedDescription)
        }
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

private struct ImportOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(AppTheme.accent)
            Text("正在整理书架…")
                .font(.headline)
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
