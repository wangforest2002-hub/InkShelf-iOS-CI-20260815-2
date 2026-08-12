import SwiftUI
import UniformTypeIdentifiers

struct RemoteLibraryView: View {
    @AppStorage("cloud.libraryMode") private var modeRaw = CloudLibraryMode.iCloud.rawValue

    private var mode: Binding<CloudLibraryMode> {
        Binding(
            get: { CloudLibraryMode(rawValue: modeRaw) ?? .iCloud },
            set: { modeRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("云书库来源", selection: mode) {
                    ForEach(CloudLibraryMode.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(.bar)

                switch mode.wrappedValue {
                case .iCloud:
                    ICloudLibraryView()
                case .server:
                    ServerLibraryView()
                }
            }
        }
    }
}

private struct ServerLibraryView: View {
    @Environment(RemoteLibraryStore.self) private var remote
    @Environment(LibraryStore.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var query = ""
    @State private var showUploader = false
    @State private var showServerSettings = false
    @State private var openedBook: Book?
    @State private var pendingDeletion: RemoteBook?
    @Namespace private var coverTransition

    private var books: [RemoteBook] {
        remote.books.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: horizontalSizeClass == .compact ? 142 : 176, maximum: 230), spacing: 18)]
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            remoteContent

            if remote.isUploading || !remote.downloadProgress.isEmpty {
                RemoteTransferOverlay(
                    isUploading: remote.isUploading,
                    progress: remote.downloadProgress.values.first
                )
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .navigationTitle("服务器书库")
        .searchable(text: $query, prompt: "搜索服务器上的书")
        .toolbar { toolbarContent }
        .navigationDestination(item: $openedBook) { book in
            ReaderView(book: book)
                .navigationTransition(.zoom(sourceID: book.remoteSourceID ?? book.id.uuidString, in: coverTransition))
        }
        .fileImporter(
            isPresented: $showUploader,
            allowedContentTypes: UTType.inkShelfFileTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await remote.upload(urls) }
            case .failure(let error):
                remote.alert = LibraryAlert(title: "无法选择书籍", message: error.localizedDescription)
            }
        }
        .sheet(isPresented: $showServerSettings) {
            RemoteServerSettingsView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert(item: alertBinding) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("好")))
        }
        .confirmationDialog(
            "从服务器删除？",
            isPresented: deletionPresented,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { book in
            Button("删除服务器原文件", role: .destructive) {
                Task { await remote.delete(book) }
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: { book in
            Text("“\(book.title)”将从服务器永久删除；已经缓存到本机的副本不会受影响。")
        }
    }

    @ViewBuilder
    private var remoteContent: some View {
        if books.isEmpty, !remote.isLoading {
            ContentUnavailableView {
                Label(query.isEmpty ? "云书库还是空的" : "没有找到这本书", systemImage: "externaldrive.badge.icloud")
            } description: {
                Text(query.isEmpty ? "把 PDF、画集或电子书上传到服务器，所有原文件都会按原样保存。" : "换个标题关键词试试。")
            } actions: {
                if query.isEmpty {
                    Button("上传第一本书") { showUploader = true }
                        .adaptiveProminentButton()
                }
            }
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 24) {
                    ForEach(books) { book in
                        let cached = library.cachedBook(remoteID: book.id, modifiedAt: book.modifiedAt)
                        Button {
                            open(book)
                        } label: {
                            RemoteBookCard(
                                book: book,
                                coverURL: remote.coverURL(for: book),
                                isCached: cached != nil,
                                downloadProgress: remote.downloadProgress[book.id]
                            )
                            .matchedTransitionSource(id: book.id, in: coverTransition)
                        }
                        .buttonStyle(PressableCardStyle())
                        .contextMenu {
                            if let cached {
                                Button { openedBook = cached } label: {
                                    Label("打开本地缓存", systemImage: "book.pages")
                                }
                            } else {
                                Button { open(book) } label: {
                                    Label("下载并阅读", systemImage: "arrow.down.circle")
                                }
                            }
                            Divider()
                            Button(role: .destructive) { pendingDeletion = book } label: {
                                Label("从服务器删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .refreshable { await remote.refresh() }
            .overlay(alignment: .top) {
                if remote.isLoading {
                    ProgressView()
                        .padding(10)
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
                Label(
                    remote.isOnline ? "独立服务已连接" : "独立服务未连接",
                    systemImage: remote.isOnline ? "checkmark.icloud.fill" : "icloud.slash"
                )
                Button {
                    Task { await remote.refresh() }
                } label: {
                    Label("刷新书库", systemImage: "arrow.clockwise")
                }
                Button { showServerSettings = true } label: {
                    Label("服务器地址", systemImage: "network")
                }
            } label: {
                Image(systemName: remote.isOnline ? "externaldrive.fill.badge.icloud" : "externaldrive.badge.xmark")
            }
            .accessibilityLabel("云书库状态")
        }

        ToolbarItem(placement: .primaryAction) {
            Button { showUploader = true } label: {
                Label("上传书籍", systemImage: "plus")
            }
            .disabled(remote.isUploading)
        }
    }

    private func open(_ remoteBook: RemoteBook) {
        if let cached = library.cachedBook(remoteID: remoteBook.id, modifiedAt: remoteBook.modifiedAt) {
            openedBook = cached
            return
        }
        Task {
            if let imported = await remote.download(remoteBook, into: library) {
                openedBook = imported
            }
        }
    }

    private var alertBinding: Binding<LibraryAlert?> {
        Binding(get: { remote.alert }, set: { remote.alert = $0 })
    }

    private var deletionPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }
}

private struct RemoteServerSettingsView: View {
    @Environment(RemoteLibraryStore.self) private var remote
    @Environment(\.dismiss) private var dismiss
    @State private var draftAddress = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("独立服务器") {
                    TextField("https://example.com", text: $draftAddress)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Label("墨阅云书库与文档中心完全分离，直接连接，不需要账号或密码。", systemImage: "arrow.triangle.branch")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Label("此服务器没有访问密码，知道地址的人都可以查看、上传或删除书籍。", systemImage: "exclamationmark.shield")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .navigationTitle("服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("连接") {
                        let address = draftAddress
                        dismiss()
                        Task { await remote.updateServerAddress(address) }
                    }
                    .disabled(draftAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { draftAddress = remote.serverAddress }
        }
    }
}

private struct RemoteBookCard: View {
    let book: RemoteBook
    let coverURL: URL?
    let isCached: Bool
    let downloadProgress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                RemoteCover(book: book, coverURL: coverURL)
                    .aspectRatio(0.70, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 7)

                if isCached {
                    Label("已缓存", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                        .padding(8)
                        .inkGlass(cornerRadius: 14)
                        .padding(7)
                        .accessibilityLabel("已缓存到本机")
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

            VStack(alignment: .leading, spacing: 5) {
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 5) {
                    Image(systemName: isCached ? "iphone" : "icloud")
                    Text(isCached ? "本机可读" : AppFormatters.fileSize(book.size))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if let downloadProgress {
                    ProgressView(value: downloadProgress)
                        .tint(AppTheme.accent)
                } else if let progress = book.progress?.progress, progress > 0 {
                    ProgressView(value: progress)
                        .tint(AppTheme.accent)
                } else {
                    ProgressView(value: 0)
                        .tint(AppTheme.accent)
                        .opacity(0.28)
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title)，\(book.formatLabel)，\(isCached ? "已缓存" : "位于服务器")")
        .hoverEffect(.lift)
    }
}

private struct RemoteCover: View {
    let book: RemoteBook
    let coverURL: URL?

    var body: some View {
        AsyncImage(url: coverURL, transaction: Transaction(animation: .smooth)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty:
                ZStack {
                    placeholder
                    ProgressView().tint(AppTheme.accent)
                }
            default:
                placeholder
            }
        }
        .background(Color(.secondarySystemBackground))
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.accent.opacity(0.24), Color.cyan.opacity(0.18), Color.pink.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.white.opacity(0.15))
                .frame(width: 160)
                .offset(x: 55, y: -80)
            VStack(spacing: 14) {
                Image(systemName: book.kind.systemImage)
                    .font(.system(size: 44, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                Text(book.title)
                    .font(.headline)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color(red: 0.13, green: 0.16, blue: 0.30))
            .padding(18)
        }
    }
}

private struct RemoteTransferOverlay: View {
    let isUploading: Bool
    let progress: Double?

    var body: some View {
        VStack(spacing: 14) {
            if let progress, !isUploading {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                    .tint(AppTheme.accent)
                Text("正在下载 · \(Int((progress * 100).rounded()))%")
                    .font(.headline.monospacedDigit())
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(AppTheme.accent)
                Text(isUploading ? "正在上传原文件…" : "正在准备下载…")
                    .font(.headline)
            }
            Text("可继续留在此页面，完成后会自动更新书库")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .inkGlass(cornerRadius: 26)
        .shadow(color: .black.opacity(0.15), radius: 24, y: 10)
    }
}
