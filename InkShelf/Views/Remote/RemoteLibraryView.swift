import SwiftUI
import UniformTypeIdentifiers

struct RemoteLibraryView: View {
    @Environment(RemoteLibraryStore.self) private var remote
    @Environment(LibraryStore.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var query = ""
    @State private var showUploader = false
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
        NavigationStack {
            ZStack {
                AuroraBackground()

                if remote.isAuthenticated {
                    remoteContent
                } else {
                    RemoteLibraryLoginView()
                }

                if remote.isUploading || !remote.downloadProgress.isEmpty {
                    RemoteTransferOverlay(
                        isUploading: remote.isUploading,
                        progress: remote.downloadProgress.values.first
                    )
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
            }
            .navigationTitle("云书库")
            .searchable(text: $query, prompt: "搜索服务器上的书")
            .toolbar { toolbarContent }
            .navigationDestination(item: $openedBook) { book in
                ReaderView(book: book)
                    .navigationTransition(.zoom(sourceID: book.remoteSourceID ?? book.id.uuidString, in: coverTransition))
            }
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
                if query.isEmpty, remote.currentUser?.isAdmin == true {
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
                            if remote.currentUser?.isAdmin == true {
                                Divider()
                                Button(role: .destructive) { pendingDeletion = book } label: {
                                    Label("从服务器删除", systemImage: "trash")
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
        if remote.isAuthenticated {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    if let user = remote.currentUser {
                        Label(user.title, systemImage: user.isAdmin ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    }
                    Button {
                        Task { await remote.refresh() }
                    } label: {
                        Label("刷新书库", systemImage: "arrow.clockwise")
                    }
                    Divider()
                    Button(role: .destructive) {
                        Task { await remote.logout() }
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("云书库账号")
            }

            if remote.currentUser?.isAdmin == true {
                ToolbarItem(placement: .primaryAction) {
                    Button { showUploader = true } label: {
                        Label("上传书籍", systemImage: "plus")
                    }
                    .disabled(remote.isUploading)
                }
            }
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

private struct RemoteLibraryLoginView: View {
    @Environment(RemoteLibraryStore.self) private var remote
    @FocusState private var focusedField: Field?

    private enum Field { case username, password }

    var body: some View {
        @Bindable var remote = remote

        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.14))
                        .frame(width: 104, height: 104)
                    Image(systemName: "externaldrive.fill.badge.icloud")
                        .font(.system(size: 46, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppTheme.accent)
                }

                VStack(spacing: 7) {
                    Text("连接你的私人书库")
                        .font(.title2.bold())
                    Text("使用文档中心的账号登录。封面与目录先加载，原书下载后在本机流畅阅读。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 14) {
                    TextField("网站账号", text: $remote.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }

                    SecureField("网站密码", text: $remote.password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await remote.login() } }

                    DisclosureGroup("服务器") {
                        TextField("https://example.com", text: $remote.serverAddress)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.top, 10)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .textFieldStyle(.roundedBorder)
                .padding(18)
                .inkGlass(cornerRadius: 24)

                Button {
                    Task { await remote.login() }
                } label: {
                    HStack(spacing: 9) {
                        if remote.isConnecting { ProgressView().tint(.white) }
                        Text(remote.isConnecting ? "正在连接…" : "登录云书库")
                    }
                    .frame(maxWidth: .infinity)
                }
                .adaptiveProminentButton()
                .disabled(remote.isConnecting || remote.username.isEmpty || remote.password.isEmpty)

                Label("账号和密码保存在本机钥匙串；服务器只接受 HTTPS 与已登录会话。", systemImage: "lock.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 430)
            .padding(.horizontal, 28)
            .padding(.top, 46)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
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
