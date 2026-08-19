import PhotosUI
import SwiftUI

struct HomeWorldView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HomeWorldStore.self) private var home
    @Environment(KokoAgentStore.self) private var koko
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isEditing = false
    @State private var selectedPlacementID: UUID?
    @State private var openedBook: Book?
    @State private var showsFurnitureCatalog = false
    @State private var showsBookPicker = false
    @State private var showsThemePicker = false
    @State private var showsKokoSettings = false
    @State private var showsKokoChat = false
    @State private var showsKokoBubble = false
    @State private var confirmsRoomReset = false
    @State private var showsPhotoPicker = false
    @State private var pendingArtworkKind: HomeArtworkKind?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var artworkImportError: String?
    @State private var bubbleTask: Task<Void, Never>?

    private var renderableBooks: [HomeRenderableBook] {
        library.books.map {
            HomeRenderableBook(id: $0.id, title: $0.title, coverURL: library.coverURL(for: $0))
        }
    }

    private var renderableArtworks: [HomeRenderableArtwork] {
        home.state.artworks.map {
            HomeRenderableArtwork(
                id: $0.id,
                kind: $0.kind,
                imageURL: home.artworkURL(for: $0),
                aspectRatio: $0.aspectRatio
            )
        }
    }

    private var selectedPlacement: HomePlacement? {
        home.placement(withID: selectedPlacementID)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                HomeSceneView(
                    state: home.state,
                    books: renderableBooks,
                    artworks: renderableArtworks,
                    selectedPlacementID: selectedPlacementID,
                    isEditing: isEditing,
                    showsKokoZone: showsKokoSettings,
                    kokoDecision: koko.decision,
                    kokoDecisionRevision: koko.decisionRevision,
                    reduceMotion: reduceMotion,
                    onSelectPlacement: { selectedPlacementID = $0 },
                    onOpenBook: openBook,
                    onTransformChanged: home.updatePlacement,
                    onKokoTapped: kokoTapped
                )
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 12) {
                    Spacer(minLength: 80)

                    if showsKokoBubble && !isEditing {
                        KokoSpeechBubble(
                            decision: koko.decision,
                            isThinking: koko.isThinking,
                            openChat: { showsKokoChat = true },
                            dismiss: { showsKokoBubble = false }
                        )
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if isEditing, let selectedPlacement {
                        HomePlacementInspector(
                            title: title(for: selectedPlacement),
                            placement: selectedPlacement,
                            update: { home.updatePlacement(selectedPlacement.id, transform: $0) },
                            toggleLock: {
                                home.updatePlacement(selectedPlacement.id, locked: !selectedPlacement.isLocked)
                            },
                            duplicate: {
                                selectedPlacementID = home.duplicatePlacement(selectedPlacement.id)
                            },
                            remove: {
                                home.removePlacement(selectedPlacement.id)
                                selectedPlacementID = nil
                            }
                        )
                        .padding(.horizontal, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if isEditing {
                        HomeEditingDock(
                            addFurniture: { showsFurnitureCatalog = true },
                            addBook: { showsBookPicker = true },
                            addArtwork: beginArtworkImport,
                            editKokoZone: { showsKokoSettings = true },
                            resetRoom: { confirmsRoomReset = true },
                            done: finishEditing
                        )
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    } else {
                        HomeLivingDock(
                            actionTitle: koko.decision.action.title,
                            moodTitle: koko.innerState.mood.title,
                            theme: home.state.theme,
                            edit: beginEditing,
                            talk: { showsKokoChat = true },
                            chooseTheme: { showsThemePicker = true }
                        )
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                    }
                }
            }
            .navigationTitle("小家")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Label(home.state.theme.title, systemImage: home.state.theme.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .inkGlass(cornerRadius: 18)
                        .accessibilityIdentifier("home-theme")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isEditing ? finishEditing() : beginEditing()
                    } label: {
                        Label(isEditing ? "完成" : "布置", systemImage: isEditing ? "checkmark" : "paintbrush.pointed.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("home-edit-toggle")
                }
            }
            .navigationDestination(item: $openedBook) { book in
                ReaderView(book: book) {
                    openedBook = nil
                    koko.react(
                        to: .returnedFromReading,
                        world: home.state,
                        books: library.books,
                        prefersAI: true
                    )
                }
            }
        }
        .sheet(isPresented: $showsFurnitureCatalog) {
            HomeFurnitureCatalogView { furniture in
                selectedPlacementID = home.addFurniture(furniture)
            }
        }
        .sheet(isPresented: $showsBookPicker) {
            HomeBookPlacementPicker(
                books: library.books,
                coverURL: library.coverURL(for:),
                placedBookIDs: Set(home.state.placements.compactMap(\.bookID))
            ) { book in
                selectedPlacementID = home.addBook(book.id)
                koko.react(to: .bookPlaced, world: home.state, books: library.books, prefersAI: true)
            }
        }
        .sheet(isPresented: $showsThemePicker) {
            HomeThemePickerView(selection: home.state.theme) { theme in
                home.setTheme(theme)
            }
        }
        .sheet(isPresented: $showsKokoSettings) {
            KokoHomeSettingsView()
        }
        .sheet(isPresented: $showsKokoChat) {
            KokoChatView()
        }
        .confirmationDialog(
            "想把图片做成什么？",
            isPresented: Binding(
                get: { pendingArtworkKind == nil && showsPhotoPicker == false && artworkKindDialogVisible },
                set: { if !$0 { artworkKindDialogVisible = false } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(HomeArtworkKind.allCases) { kind in
                Button(kind.title) { chooseArtworkKind(kind) }
            }
            Button("取消", role: .cancel) { artworkKindDialogVisible = false }
        } message: {
            Text("可以导入透明 PNG 或照片，放进房间后仍能自由移动和缩放。")
        }
        .photosPicker(
            isPresented: $showsPhotoPicker,
            selection: $photoItems,
            maxSelectionCount: 24,
            matching: .images,
            preferredItemEncoding: .current
        )
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty, let kind = pendingArtworkKind else { return }
            Task { await importArtwork(items, kind: kind) }
        }
        .onChange(of: home.state) { _, newState in
            koko.updateContext(world: newState, books: library.books)
        }
        .confirmationDialog(
            "恢复初始家具布置？",
            isPresented: $confirmsRoomReset,
            titleVisibility: .visible
        ) {
            Button("恢复家具", role: .destructive) {
                home.resetRoom()
                selectedPlacementID = nil
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已摆放的画集、挂画和立牌会保留，只恢复默认家具。")
        }
        .alert("收藏没有放进家里", isPresented: Binding(
            get: { artworkImportError != nil },
            set: { if !$0 { artworkImportError = nil } }
        )) {
            Button("好", role: .cancel) { artworkImportError = nil }
        } message: {
            Text(artworkImportError ?? "请稍后重试。")
        }
        .alert(item: Binding(
            get: { home.alert },
            set: { home.alert = $0 }
        )) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("好")))
        }
        .onAppear {
            home.reconcileBooks(validIDs: Set(library.books.map(\.id)))
            home.seedRecentBooksIfNeeded(library.books)
            koko.start(world: home.state, books: library.books)
        }
        .onDisappear {
            bubbleTask?.cancel()
            home.flush()
            koko.stop()
        }
    }

    @State private var artworkKindDialogVisible = false

    private func beginEditing() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
            isEditing = true
            showsKokoBubble = false
        }
    }

    private func finishEditing() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
            isEditing = false
            selectedPlacementID = nil
        }
        home.flush()
        koko.react(to: .roomChanged, world: home.state, books: library.books, prefersAI: true)
    }

    private func openBook(_ id: UUID) {
        guard let book = library.books.first(where: { $0.id == id }) else { return }
        if let error = library.openingError(for: book) {
            library.alert = error
            return
        }
        openedBook = book
    }

    private func kokoTapped() {
        koko.react(to: .tapped, world: home.state, books: library.books, prefersAI: true)
        showDecisionBubble()
    }

    private func beginArtworkImport() {
        artworkKindDialogVisible = true
    }

    private func chooseArtworkKind(_ kind: HomeArtworkKind) {
        pendingArtworkKind = kind
        artworkKindDialogVisible = false
        showsPhotoPicker = true
    }

    private func importArtwork(_ items: [PhotosPickerItem], kind: HomeArtworkKind) async {
        defer {
            photoItems = []
            pendingArtworkKind = nil
        }
        var lastPlacementID: UUID?
        do {
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                lastPlacementID = try home.importArtwork(data: data, kind: kind)
            }
            selectedPlacementID = lastPlacementID
        } catch {
            artworkImportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func title(for placement: HomePlacement) -> String {
        if let furniture = placement.furniture { return furniture.title }
        if let bookID = placement.bookID,
           let book = library.books.first(where: { $0.id == bookID }) {
            return book.title
        }
        if let artworkID = placement.artworkID,
           let artwork = home.artworkWithID(artworkID) {
            return artwork.title
        }
        return placement.displayName
    }

    private func showDecisionBubble() {
        bubbleTask?.cancel()
        withAnimation(reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.84)) {
            showsKokoBubble = true
        }
        bubbleTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) {
                    showsKokoBubble = false
                }
            }
        }
    }
}

private struct HomeLivingDock: View {
    let actionTitle: String
    let moodTitle: String
    let theme: HomeRoomTheme
    let edit: () -> Void
    let talk: () -> Void
    let chooseTheme: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: talk) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("东京小公寓")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("拖动环顾 · 轻点走动")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            DockCircleButton(symbol: "bubble.left.and.text.bubble.right.fill", label: "和可可聊聊", action: talk)
            DockCircleButton(symbol: theme.systemImage, label: "房间氛围", action: chooseTheme)
            DockCircleButton(symbol: "paintbrush.pointed.fill", label: "布置小家", action: edit)
        }
        .padding(12)
        .inkGlass(cornerRadius: 28)
    }
}

private struct HomeEditingDock: View {
    let addFurniture: () -> Void
    let addBook: () -> Void
    let addArtwork: () -> Void
    let editKokoZone: () -> Void
    let resetRoom: () -> Void
    let done: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                EditingDockButton(title: "家具", symbol: "sofa.fill", action: addFurniture)
                EditingDockButton(title: "画集", symbol: "books.vertical.fill", action: addBook)
                EditingDockButton(title: "收藏", symbol: "photo.artframe", action: addArtwork)
                EditingDockButton(title: "可可", symbol: "figure.walk", action: editKokoZone)
                EditingDockButton(title: "恢复", symbol: "arrow.counterclockwise", action: resetRoom)
                EditingDockButton(title: "完成", symbol: "checkmark.circle.fill", emphasized: true, action: done)
            }
            .padding(10)
        }
        .scrollIndicators(.hidden)
        .inkGlass(cornerRadius: 28)
    }
}

private struct DockCircleButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 42, height: 42)
                .background(AppTheme.accent.opacity(0.14), in: Circle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel(label)
    }
}

private struct EditingDockButton: View {
    let title: String
    let symbol: String
    var emphasized = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.headline)
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(emphasized ? .white : .primary)
            .frame(width: 58, height: 54)
            .background(emphasized ? AnyShapeStyle(AppTheme.accentGradient) : AnyShapeStyle(AppTheme.accent.opacity(0.10)), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(PressableCardStyle())
    }
}

private struct KokoSpeechBubble: View {
    let decision: KokoDecision
    let isThinking: Bool
    let openChat: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.headline)
                .foregroundStyle(AppTheme.lilac)
                .frame(width: 38, height: 38)
                .background(AppTheme.lilac.opacity(0.13), in: Circle())

            Button(action: openChat) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("可可")
                            .font(.subheadline.bold())
                        if decision.generatedByAI {
                            Text("AI")
                                .font(.caption2.bold())
                                .foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.accent.opacity(0.10), in: Capsule())
                        }
                        if isThinking { ProgressView().controlSize(.mini) }
                    }
                    Text(decision.phrase)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .accessibilityLabel("收起可可的话")
        }
        .padding(14)
        .inkGlass(cornerRadius: 24)
    }
}

private struct HomePlacementInspector: View {
    let title: String
    let placement: HomePlacement
    let update: (HomeTransform) -> Void
    let toggleLock: () -> Void
    let duplicate: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Text(placement.isLocked ? "已锁定，解锁后可调整" : "拖动移动 · 双指旋转")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: toggleLock) {
                    Image(systemName: placement.isLocked ? "lock.fill" : "lock.open.fill")
                }
                Button(action: duplicate) { Image(systemName: "plus.square.on.square") }
                    .disabled(placement.kind == .artwork)
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }
            }

            HStack(spacing: 10) {
                InspectorNudgeButton(symbol: "rotate.left", label: "左转") { change(yaw: -.pi / 12) }
                InspectorNudgeButton(symbol: "minus.magnifyingglass", label: "缩小") { change(scale: -0.08) }
                Text("\(Int((placement.transform.scale * 100).rounded()))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 42)
                InspectorNudgeButton(symbol: "plus.magnifyingglass", label: "放大") { change(scale: 0.08) }
                InspectorNudgeButton(symbol: "rotate.right", label: "右转") { change(yaw: .pi / 12) }
                if placement.kind != .furniture || placement.transform.y > 0.01 {
                    InspectorNudgeButton(symbol: "arrow.up.and.down", label: "调整高度") {
                        change(y: placement.transform.y > 1.8 ? -0.12 : 0.12)
                    }
                }
            }
            .disabled(placement.isLocked)
        }
        .padding(14)
        .inkGlass(cornerRadius: 24)
    }

    private func change(yaw: Float = 0, scale: Float = 0, y: Float = 0) {
        var transform = placement.transform
        transform.yaw += yaw
        transform.scale += scale
        transform.y += y
        transform.clamp()
        update(transform)
    }
}

private struct InspectorNudgeButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 34, height: 30)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel(label)
    }
}

private struct HomeFurnitureCatalogView: View {
    @Environment(\.dismiss) private var dismiss
    let add: (HomeFurnitureKind) -> Void
    private let columns = [GridItem(.adaptive(minimum: 124, maximum: 180), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(HomeFurnitureKind.allCases) { furniture in
                        Button {
                            add(furniture)
                        } label: {
                            VStack(spacing: 12) {
                                Image(systemName: furniture.systemImage)
                                    .font(.system(size: 30, weight: .medium))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 62, height: 62)
                                    .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
                                Text(furniture.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .inkGlass(cornerRadius: 22)
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
                .padding(18)
            }
            .background(AuroraBackground())
            .navigationTitle("添加家具")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct HomeBookPlacementPicker: View {
    @Environment(\.dismiss) private var dismiss
    let books: [Book]
    let coverURL: (Book) -> URL?
    let placedBookIDs: Set<UUID>
    let add: (Book) -> Void
    @State private var query = ""

    private var filtered: [Book] {
        books.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    ContentUnavailableView("还没有画集", systemImage: "books.vertical", description: Text("先去书架导入，再把喜欢的放进家里。"))
                } else {
                    List(filtered) { book in
                        Button {
                            add(book)
                        } label: {
                            HStack(spacing: 13) {
                                CoverArtwork(book: book, coverURL: coverURL(book), previewURLs: [])
                                    .frame(width: 48, height: 66)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(book.progressLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if placedBookIDs.contains(book.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.mint)
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $query, prompt: "搜索画集")
                }
            }
            .navigationTitle("把画集放进家里")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct HomeThemePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State var selection: HomeRoomTheme
    let select: (HomeRoomTheme) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ForEach(HomeRoomTheme.allCases) { theme in
                    Button {
                        selection = theme
                        select(theme)
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: theme.systemImage)
                                .font(.title2)
                                .foregroundStyle(theme == .sunset ? AppTheme.honey : theme == .rain ? AppTheme.cyan : AppTheme.lilac)
                                .frame(width: 54, height: 54)
                                .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 18))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(theme.title).font(.headline)
                                Text(theme.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selection == theme {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.mint)
                            }
                        }
                        .padding(16)
                        .inkGlass(cornerRadius: 24)
                    }
                    .buttonStyle(PressableCardStyle())
                }
                Spacer()
            }
            .padding(18)
            .background(AuroraBackground())
            .navigationTitle("房间氛围")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct KokoHomeSettingsView: View {
    @Environment(HomeWorldStore.self) private var home
    @Environment(KokoAgentStore.self) private var koko
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("心情", value: koko.innerState.mood.title)
                    KokoStateMeter(title: "精力", value: koko.innerState.energy, tint: AppTheme.honey)
                    KokoStateMeter(title: "好奇心", value: koko.innerState.curiosity, tint: AppTheme.lilac)
                    KokoStateMeter(title: "陪伴意愿", value: koko.innerState.socialNeed, tint: AppTheme.mint)
                    KokoStateMeter(title: "整理意愿", value: koko.innerState.orderNeed, tint: AppTheme.cyan)
                } header: {
                    Text("可可此刻")
                } footer: {
                    Text("这是保存在本机的模拟自主状态，会随着时间、阅读和房间变化缓慢改变。")
                }

                Section {
                    Toggle("自主活动", isOn: Binding(
                        get: { home.state.koko.roamingEnabled },
                        set: { home.updateKoko(roamingEnabled: $0) }
                    ))
                    Toggle("回家时迎接", isOn: Binding(
                        get: { home.state.koko.welcomesHome },
                        set: { home.updateKoko(welcomesHome: $0) }
                    ))
                    Toggle("阅读时保持安静", isOn: Binding(
                        get: { home.state.koko.quietWhileReading },
                        set: { home.updateKoko(quietWhileReading: $0) }
                    ))
                } header: {
                    Text("可可的习惯")
                } footer: {
                    Text("可可会在本机完成走路、避让和动作；AI只偶尔决定高层意图与语句。")
                }

                Section("活动范围") {
                    ZoneSlider(title: "左右中心", value: zoneBinding(\.centerX), range: -1.8...1.8)
                    ZoneSlider(title: "前后中心", value: zoneBinding(\.centerZ), range: -1.5...1.5)
                    ZoneSlider(title: "范围宽度", value: zoneBinding(\.width), range: 0.8...5.4)
                    ZoneSlider(title: "范围深度", value: zoneBinding(\.depth), range: 0.8...4.4)
                    Button("恢复默认范围") {
                        home.updateKokoZone(KokoActivityZone())
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .navigationTitle("可可的活动范围")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func zoneBinding(_ keyPath: WritableKeyPath<KokoActivityZone, Float>) -> Binding<Double> {
        Binding(
            get: { Double(home.state.koko.activityZone[keyPath: keyPath]) },
            set: { value in
                var zone = home.state.koko.activityZone
                zone[keyPath: keyPath] = Float(value)
                home.updateKokoZone(zone)
            }
        )
    }
}

private struct KokoStateMeter: View {
    let title: String
    let value: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .frame(width: 72, alignment: .leading)
            ProgressView(value: value)
                .tint(tint)
            Text(value, format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }
}

private struct ZoneSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(1)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}

private struct KokoChatView: View {
    @Environment(KokoAgentStore.self) private var koko
    @Environment(HomeWorldStore.self) private var home
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if koko.conversation.isEmpty {
                                KokoChatBubble(
                                    text: "欢迎回家。你可以和我说说今天想看什么，也可以只在这里安静待一会儿。",
                                    isUser: false
                                )
                            }
                            ForEach(koko.conversation) { item in
                                KokoChatBubble(text: item.text, isUser: item.role == .user)
                                    .id(item.id)
                            }
                            if koko.isReplying {
                                HStack {
                                    ProgressView()
                                    Text("可可正在想…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 6)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: koko.conversation.count) { _, _ in
                        if let id = koko.conversation.last?.id {
                            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }

                HStack(alignment: .bottom, spacing: 10) {
                    TextField("和可可说点什么…", text: $message, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                    }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || koko.isReplying)
                    .accessibilityLabel("发送")
                }
                .padding(12)
                .background(.ultraThinMaterial)
            }
            .background(AuroraBackground())
            .navigationTitle("和可可聊聊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                if !koko.conversation.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("清空", role: .destructive) { koko.clearConversation() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() {
        let text = message
        message = ""
        Task { await koko.send(text, world: home.state, books: library.books) }
    }
}

private struct KokoChatBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 56) }
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(isUser ? AppTheme.accent : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(isUser ? .white : .primary)
            if !isUser { Spacer(minLength: 56) }
        }
    }
}
