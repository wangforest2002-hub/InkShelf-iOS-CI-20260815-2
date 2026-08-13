import SwiftUI
import UniformTypeIdentifiers

struct ICloudLibraryView: View {
    @Environment(ICloudLibraryStore.self) private var cloud
    @Environment(LibraryStore.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var query = ""
    @State private var showFolderPicker = false
    @State private var showFolderHelp = false
    @State private var openedBook: Book?
    @State private var pendingUnlink: ICloudFolderLink?
    @State private var pendingLocalRemoval: ICloudBook?
    @Namespace private var coverTransition

    private var visibleBooks: [ICloudBook] {
        cloud.books.filter {
            query.isEmpty ||
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.collection.localizedCaseInsensitiveContains(query)
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: horizontalSizeClass == .compact ? 142 : 176, maximum: 230), spacing: 18)]
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            content

            if cloud.isDownloading {
                ICloudDownloadOverlay(progress: cloud.downloadProgress.values.first ?? 0)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .navigationTitle("iCloud 书库")
        .searchable(text: $query, prompt: "搜索书名或文件夹")
        .toolbar { toolbarContent }
        .navigationDestination(item: $openedBook) { book in
            ReaderView(book: book)
                .navigationTransition(.zoom(sourceID: book.remoteSourceID ?? book.id.uuidString, in: coverTransition))
        }
        .sheet(isPresented: $showFolderPicker) {
            DocumentPickerView(
                contentTypes: [.folder],
                allowsMultipleSelection: false,
                asCopy: false,
                onResult: { result in
                    showFolderPicker = false
                    switch result {
                    case .success(let urls):
                        if let folder = urls.first { cloud.linkFolder(folder) }
                    case .failure(let error):
                        cloud.alert = LibraryAlert(title: "无法选择 iCloud 文件夹", message: error.localizedDescription)
                    }
                },
                onCancel: { showFolderPicker = false }
            )
            .ignoresSafeArea()
        }
        .alert(item: alertBinding) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("好")))
        }
        .confirmationDialog(
            "连接一个书库文件夹",
            isPresented: $showFolderHelp,
            titleVisibility: .visible
        ) {
            Button("开始选择") { showFolderPicker = true }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请先把书放进一个普通文件夹。iCloud Drive 和“我的 iPad”根目录不能直接选；根目录里的 CBZ 显示为不可点是正常的。选中书库文件夹后点“打开”或“完成”。")
        }
        .confirmationDialog(
            "断开 iCloud 文件夹？",
            isPresented: unlinkPresented,
            titleVisibility: .visible,
            presenting: pendingUnlink
        ) { folder in
            Button("断开连接", role: .destructive) {
                cloud.unlink(folder)
                pendingUnlink = nil
            }
            Button("取消", role: .cancel) { pendingUnlink = nil }
        } message: { folder in
            Text("二次元小家将不再索引“\(folder.name)”。iCloud 原文件和已下载的本地副本都不会被删除。")
        }
        .confirmationDialog(
            "删除本地副本？",
            isPresented: localRemovalPresented,
            titleVisibility: .visible,
            presenting: pendingLocalRemoval
        ) { book in
            Button("删除本地副本", role: .destructive) {
                cloud.removeLocalCopy(of: book, from: library)
                pendingLocalRemoval = nil
            }
            Button("取消", role: .cancel) { pendingLocalRemoval = nil }
        } message: { book in
            Text("“\(book.title)”会从本机书架移除，但 iCloud 中的 CBZ 原文件仍然保留。")
        }
    }

    @ViewBuilder
    private var content: some View {
        if cloud.folders.isEmpty {
            ContentUnavailableView {
                Label("连接 iCloud 画集", systemImage: "icloud.and.arrow.down")
            } description: {
                Text("在系统“文件”中选择存放 CBZ 的 iCloud Drive 文件夹。只建立索引，打开时才下载原书。")
            } actions: {
                Button("选择 iCloud 文件夹") { showFolderHelp = true }
                    .adaptiveProminentButton()
                Text("提示：先在“文件”App 新建“二次元小家书库”文件夹，并把 CBZ 放进去。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else if visibleBooks.isEmpty, !cloud.isIndexing {
            ContentUnavailableView {
                Label(query.isEmpty ? "没有找到读物" : "没有搜索结果", systemImage: "icloud.slash")
            } description: {
                Text(query.isEmpty ? "所选文件夹中暂时没有支持的 PDF、CBZ、图片或电子书。" : "换个书名或文件夹名称试试。")
            } actions: {
                if query.isEmpty {
                    Button("重新扫描") { Task { await cloud.refresh() } }
                        .adaptiveProminentButton()
                }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ICloudLibrarySummary(
                        folderCount: cloud.folders.count,
                        bookCount: cloud.books.count,
                        totalSize: cloud.totalCloudSize
                    )

                    LazyVGrid(columns: gridColumns, spacing: 24) {
                        ForEach(visibleBooks) { cloudBook in
                            let cached = cloud.cachedBook(for: cloudBook, in: library)
                            Button { open(cloudBook) } label: {
                                ICloudBookCard(
                                    book: cloudBook,
                                    cachedBook: cached,
                                    coverURL: cached.flatMap { library.coverURL(for: $0) },
                                    previewURLs: cached.map { library.previewURLs(for: $0) } ?? [],
                                    downloadProgress: cloud.downloadProgress[cloudBook.id]
                                )
                                .matchedTransitionSource(id: cloudBook.sourceID, in: coverTransition)
                            }
                            .buttonStyle(PressableCardStyle())
                            .contextMenu {
                                if let cached {
                                    Button { openedBook = cached } label: {
                                        Label("离线打开", systemImage: "book.pages")
                                    }
                                    Button(role: .destructive) { pendingLocalRemoval = cloudBook } label: {
                                        Label("删除本地副本", systemImage: "iphone.slash")
                                    }
                                } else {
                                    Button { open(cloudBook) } label: {
                                        Label("下载并阅读", systemImage: "icloud.and.arrow.down")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .refreshable { await cloud.refresh() }
            .overlay(alignment: .top) {
                if cloud.isIndexing {
                    Label("正在扫描 iCloud…", systemImage: "arrow.triangle.2.circlepath.icloud")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .inkGlass(cornerRadius: 18)
                        .padding(.top, 8)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Label("\(cloud.folders.count) 个文件夹 · \(cloud.books.count) 本", systemImage: "icloud.fill")
                Button { Task { await cloud.refresh() } } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
                ForEach(cloud.folders) { folder in
                    Button(role: .destructive) { pendingUnlink = folder } label: {
                        Label("断开 \(folder.name)", systemImage: "link.badge.minus")
                    }
                }
            } label: {
                Image(systemName: "icloud.fill")
            }
            .accessibilityLabel("iCloud 文件夹")
        }

        ToolbarItem(placement: .primaryAction) {
            Button { showFolderHelp = true } label: {
                Label("连接文件夹", systemImage: "folder.badge.plus")
            }
        }
    }

    private func open(_ book: ICloudBook) {
        if let cached = cloud.cachedBook(for: book, in: library) {
            openedBook = cached
            return
        }
        Task {
            if let imported = await cloud.open(book, into: library) {
                openedBook = imported
            }
        }
    }

    private var alertBinding: Binding<LibraryAlert?> {
        Binding(get: { cloud.alert }, set: { cloud.alert = $0 })
    }

    private var unlinkPresented: Binding<Bool> {
        Binding(get: { pendingUnlink != nil }, set: { if !$0 { pendingUnlink = nil } })
    }

    private var localRemovalPresented: Binding<Bool> {
        Binding(get: { pendingLocalRemoval != nil }, set: { if !$0 { pendingLocalRemoval = nil } })
    }
}

private struct ICloudLibrarySummary: View {
    let folderCount: Int
    let bookCount: Int
    let totalSize: Int64

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "icloud.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 42, height: 42)
                .background(AppTheme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("iCloud Drive")
                    .font(.headline)
                Text("\(folderCount) 个文件夹 · \(bookCount) 本 · \(AppFormatters.fileSize(totalSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("按需下载")
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(AppTheme.accent.opacity(0.1), in: Capsule())
        }
        .padding(14)
        .inkGlass(cornerRadius: 22)
    }
}

private struct ICloudBookCard: View {
    let book: ICloudBook
    let cachedBook: Book?
    let coverURL: URL?
    let previewURLs: [URL]
    let downloadProgress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                if let cachedBook {
                    CoverArtwork(book: cachedBook, coverURL: coverURL, previewURLs: previewURLs)
                } else {
                    ICloudPlaceholderCover(book: book)
                }

                if cachedBook != nil {
                    Image(systemName: "checkmark.icloud.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .padding(8)
                        .inkGlass(cornerRadius: 14)
                        .padding(7)
                        .accessibilityLabel("已保存在本机，可离线阅读")
                }

                Text(book.formatLabel)
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.48), in: Capsule())
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .aspectRatio(0.70, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 7)

            VStack(alignment: .leading, spacing: 5) {
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 5) {
                    Image(systemName: cachedBook == nil ? "icloud" : "iphone")
                    Text(cachedBook == nil ? book.collection : "离线可读")
                        .lineLimit(1)
                    Text("·")
                    Text(AppFormatters.fileSize(book.size))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                ProgressView(value: downloadProgress ?? (cachedBook == nil ? 0 : 1))
                    .tint(cachedBook == nil ? AppTheme.accent : .green)
                    .opacity(downloadProgress == nil && cachedBook == nil ? 0.28 : 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title)，\(book.collection)，\(cachedBook == nil ? "位于 iCloud" : "离线可读")")
        .hoverEffect(.lift)
    }
}

private struct ICloudPlaceholderCover: View {
    let book: ICloudBook

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.cyan.opacity(0.28), AppTheme.accent.opacity(0.24), Color.pink.opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: 150)
                .offset(x: 52, y: -78)
            VStack(spacing: 14) {
                Image(systemName: book.kind.systemImage)
                    .font(.system(size: 44, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                Text(book.title)
                    .font(.headline)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                Text(book.collection)
                    .font(.caption2.weight(.semibold))
                    .opacity(0.7)
                    .lineLimit(1)
            }
            .foregroundStyle(Color(red: 0.13, green: 0.16, blue: 0.30))
            .padding(18)
        }
    }
}

private struct ICloudDownloadOverlay: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 14) {
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .controlSize(.large)
                .tint(AppTheme.accent)
            Text(
                progress < 0.50
                    ? "正在等待 iCloud 下载…"
                    : "正在整理本地副本 · \(Int((progress * 100).rounded()))%"
            )
                .font(.headline.monospacedDigit())
            Text("首次打开需要等待；完成后将直接使用本地阅读引擎")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .inkGlass(cornerRadius: 26)
        .shadow(color: .black.opacity(0.15), radius: 24, y: 10)
    }
}
