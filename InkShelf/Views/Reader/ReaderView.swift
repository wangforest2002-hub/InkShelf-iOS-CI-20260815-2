import SwiftUI
import UIKit

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(LibraryStore.self) private var library
    @Environment(AICompanionStore.self) private var companion
    @Environment(AchievementStore.self) private var achievements
    let book: Book
    let onClose: (() -> Void)?

    @State private var currentPage: Int
    @State private var pageCount: Int
    @State private var imageURLs: [URL] = []
    @State private var ebookPackage: EBookPackage?
    @State private var ebookProgress: Double
    @State private var controlsVisible = true
    @State private var showSettings = false
    @State private var showThumbnails = false
    @State private var showAICompanion = false
    @State private var showEndComments = false
    @State private var pdfLocked = false
    @State private var passwordDraft = ""
    @State private var pdfPassword = ""
    @State private var didTryPassword = false
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var prefetchTask: Task<Void, Never>?
    @State private var readerAlert: ReaderAlert?
    @State private var readerNotice: String?
    @State private var isSavingPage = false
    @State private var isEnhancingPage = false
    @State private var activeReadingStartedAt: Date?
    @State private var layoutRaw: String
    @State private var flowRaw: String
    @State private var orderRaw: String
    @State private var backdropRaw: String
    @State private var coverSingle: Bool

    @AppStorage("reader.layout") private var defaultLayoutRaw = ReaderLayout.single.rawValue
    @AppStorage("reader.flow") private var defaultFlowRaw = ReaderFlow.horizontal.rawValue
    @AppStorage("reader.order") private var defaultOrderRaw = ReadingOrder.leftToRight.rawValue
    @AppStorage("reader.backdrop") private var defaultBackdropRaw = ReaderBackdrop.black.rawValue
    @AppStorage("reader.coverSingle") private var defaultCoverSingle = true
    @AppStorage("reader.keepAwake") private var keepAwake = true
    @AppStorage("ai.enabled") private var aiEnabled = false
    @AppStorage("ai.autoDanmaku") private var autoDanmaku = true
    @AppStorage("ai.autoShowEnd") private var autoShowEnd = true
    @AppStorage("sharp.bridgeAddress") private var sharpBridgeAddress = ""
    @AppStorage("ebook.flow") private var ebookFlowRaw = EBookFlow.paged.rawValue
    @AppStorage("ebook.theme") private var ebookThemeRaw = EBookTheme.paper.rawValue
    @AppStorage("ebook.font") private var ebookFontRaw = EBookFont.serif.rawValue
    @AppStorage("ebook.fontSize") private var ebookFontSize = 19.0
    @AppStorage("ebook.lineHeight") private var ebookLineHeight = 1.72
    @AppStorage("ebook.margin") private var ebookMargin = 24.0

    init(book: Book, onClose: (() -> Void)? = nil) {
        self.book = book
        self.onClose = onClose
        let defaults = UserDefaults.standard
        let profile = book.readerProfile
        _currentPage = State(initialValue: min(max(0, book.currentPage), max(0, book.pageCount - 1)))
        _pageCount = State(initialValue: max(1, book.pageCount))
        _ebookProgress = State(initialValue: book.ebookChapterProgress ?? 0)
        _layoutRaw = State(initialValue: profile?.layoutRaw
            ?? defaults.string(forKey: "reader.layout")
            ?? ReaderLayout.single.rawValue)
        _flowRaw = State(initialValue: profile?.flowRaw
            ?? defaults.string(forKey: "reader.flow")
            ?? ReaderFlow.horizontal.rawValue)
        _orderRaw = State(initialValue: profile?.orderRaw
            ?? defaults.string(forKey: "reader.order")
            ?? ReadingOrder.leftToRight.rawValue)
        _backdropRaw = State(initialValue: profile?.backdropRaw
            ?? defaults.string(forKey: "reader.backdrop")
            ?? ReaderBackdrop.black.rawValue)
        _coverSingle = State(initialValue: profile?.coverSingle
            ?? (defaults.object(forKey: "reader.coverSingle") as? Bool)
            ?? true)
    }

    private var layout: ReaderLayout { ReaderLayout(rawValue: layoutRaw) ?? .single }
    private var flow: ReaderFlow { ReaderFlow(rawValue: flowRaw) ?? .horizontal }
    private var order: ReadingOrder { ReadingOrder(rawValue: orderRaw) ?? .leftToRight }
    private var backdrop: ReaderBackdrop { ReaderBackdrop(rawValue: backdropRaw) ?? .black }
    private var ebookFlow: EBookFlow { EBookFlow(rawValue: ebookFlowRaw) ?? .paged }
    private var ebookTheme: EBookTheme { EBookTheme(rawValue: ebookThemeRaw) ?? .paper }
    private var ebookFont: EBookFont { EBookFont(rawValue: ebookFontRaw) ?? .serif }
    private var bookReaderProfile: BookReaderProfile {
        BookReaderProfile(
            layoutRaw: layoutRaw,
            flowRaw: flowRaw,
            orderRaw: orderRaw,
            backdropRaw: backdropRaw,
            coverSingle: coverSingle
        )
    }

    var body: some View {
        ZStack {
            (book.kind == .ebook ? ebookTheme.color : backdrop.color).ignoresSafeArea()

            readerContent
                .ignoresSafeArea()

            if aiEnabled,
               autoDanmaku,
               let reaction = companion.currentReaction,
               reaction.page == currentPage {
                DanmakuOverlay(
                    messages: reaction.danmaku,
                    pageToken: "\(book.id)-\(currentPage)-\(reaction.id)"
                )
                .transition(.opacity)
            }

            if companion.activity.isBusy, companion.currentBookID == book.id {
                VStack {
                    AIReadingPill(activity: companion.activity)
                        .padding(.top, 62)
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if aiEnabled,
               let reaction = companion.currentReaction,
               reaction.page == currentPage,
               let translation = reaction.translation,
               !translation.segments.isEmpty {
                VStack {
                    Spacer()
                    Button(action: openAICompanion) {
                        AICompactTranslationCard(translation: translation)
                    }
                    .buttonStyle(PressableCardStyle())
                    .padding(.horizontal, 18)
                    .padding(.bottom, controlsVisible ? 142 : 18)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(16)
            }

            if let achievement = achievements.latestUnlock {
                VStack {
                    AchievementUnlockToast(achievement: achievement)
                        .padding(.top, controlsVisible ? 112 : 20)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(30)
                .allowsHitTesting(false)
            }

            if let readerNotice {
                VStack {
                    Spacer()
                    ReaderNoticeToast(text: readerNotice)
                        .padding(.bottom, controlsVisible ? 126 : 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(29)
                .allowsHitTesting(false)
            }

            if pdfLocked {
                PDFPasswordOverlay(
                    password: $passwordDraft,
                    showError: didTryPassword,
                    submit: unlockPDF
                )
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }

            if controlsVisible {
                ReaderControls(
                    title: book.title,
                    kind: book.kind,
                    nightMood: book.belongsToAfterDark ? (book.mood?.title ?? "成年人夜读") : nil,
                    currentPage: $currentPage,
                    pageCount: pageCount,
                    layout: layout,
                    ebookFlow: ebookFlow,
                    isEBook: book.kind == .ebook,
                    aiEnabled: aiEnabled && companion.hasAPIKey,
                    aiActivity: companion.currentBookID == book.id ? companion.activity : .idle,
                    isFavorite: favoriteState,
                    isPageFavorite: pageFavoriteState,
                    canUsePageActions: book.kind != .ebook && !pdfLocked,
                    isSavingPage: isSavingPage,
                    isEnhancingPage: isEnhancingPage,
                    dismiss: closeReader,
                    toggleFavorite: { library.toggleFavorite(book.id) },
                    togglePageFavorite: togglePageFavorite,
                    savePage: saveCurrentPage,
                    enhancePage: enhanceCurrentPage,
                    toggleLayout: toggleLayout,
                    toggleAI: toggleAI,
                    showThumbnails: { showThumbnails = true },
                    showSettings: { showSettings = true },
                    onInteraction: showControlsTemporarily
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .zIndex(20)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(controlsVisible ? .automatic : .hidden)
        .preferredColorScheme(book.kind == .ebook ? (ebookTheme == .night ? .dark : .light) : .dark)
        .sensoryFeedback(.selection, trigger: currentPage)
        .sensoryFeedback(.selection, trigger: aiEnabled)
        .sensoryFeedback(.success, trigger: achievements.unlockedCount)
        .sensoryFeedback(.success, trigger: readerNotice)
        .onAppear {
            library.beginReading(book.id)
            achievements.recordOpened(bookID: book.id)
            activeReadingStartedAt = .now
            if book.kind == .ebook {
                ebookPackage = library.ebookPackage(for: book)
                pageCount = max(1, ebookPackage?.chapters.count ?? book.pageCount)
            } else if book.kind != .pdf {
                imageURLs = library.pageURLs(for: book)
                pageCount = max(1, imageURLs.count)
                schedulePrefetchPages(around: currentPage)
            }
            UIApplication.shared.isIdleTimerDisabled = keepAwake
            scheduleControlsHide()
            if book.kind != .pdf { prepareAIPage() }
        }
        .onChange(of: currentPage) { _, newPage in
            if book.kind == .ebook {
                library.updateEBookProgress(bookID: book.id, chapter: newPage, progression: ebookProgress)
            } else {
                library.updateProgress(bookID: book.id, page: newPage)
            }
            achievements.recordPageTurn(
                bookID: book.id,
                reachedLastPage: pageCount > 0 && newPage >= pageCount - 1
            )
            if controlsVisible { scheduleControlsHide() }
            schedulePrefetchPages(around: newPage)
            prepareAIPage()
        }
        .onChange(of: ebookProgress) { _, newValue in
            guard book.kind == .ebook else { return }
            library.updateEBookProgress(bookID: book.id, chapter: currentPage, progression: newValue)
        }
        .onChange(of: keepAwake) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
        .onChange(of: bookReaderProfile) { _, profile in
            guard book.kind != .ebook else { return }
            library.updateReaderProfile(bookID: book.id, profile: profile)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                activeReadingStartedAt = .now
            } else {
                recordReadingPause()
                library.flushProgress()
            }
        }
        .onDisappear {
            hideControlsTask?.cancel()
            prefetchTask?.cancel()
            companion.cancelAll()
            library.flushProgress()
            recordReadingPause()
            UIApplication.shared.isIdleTimerDisabled = false
            if scenePhase == .active {
                library.endReading(book.id)
            }
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsView(
                layoutRaw: $layoutRaw,
                flowRaw: $flowRaw,
                orderRaw: $orderRaw,
                backdropRaw: $backdropRaw,
                coverSingle: $coverSingle,
                keepAwake: $keepAwake,
                isEBook: book.kind == .ebook,
                ebookFlowRaw: $ebookFlowRaw,
                ebookThemeRaw: $ebookThemeRaw,
                ebookFontRaw: $ebookFontRaw,
                ebookFontSize: $ebookFontSize,
                ebookLineHeight: $ebookLineHeight,
                ebookMargin: $ebookMargin,
                saveComicDefaults: saveComicDefaults
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showThumbnails) {
            if let ebookPackage, book.kind == .ebook {
                EBookNavigatorView(package: ebookPackage, chapterIndex: $currentPage)
            } else {
                ThumbnailBrowser(
                    book: book,
                    pdfURL: book.kind == .pdf ? library.contentURL(for: book) : nil,
                    imageURLs: imageURLs,
                    password: pdfPassword,
                    totalPageCount: pageCount,
                    currentPage: $currentPage
                )
            }
        }
        .sheet(isPresented: $showAICompanion) {
            AICompanionPanel(
                bookTitle: book.title,
                page: currentPage,
                pageCount: pageCount,
                isLastPage: currentPage >= pageCount - 1,
                showEndDiscussion: {
                    showAICompanion = false
                    showEndComments = true
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEndComments) {
            AIEndDiscussionView(bookTitle: book.title)
        }
        .onChange(of: companion.endDiscussion?.id) { _, newValue in
            guard newValue != nil,
                  autoShowEnd,
                  currentPage >= pageCount - 1,
                  !showAICompanion
            else { return }
            showEndComments = true
        }
        .onChange(of: companion.errorMessage) { _, message in
            guard aiEnabled, let message, !message.isEmpty else { return }
            showNotice(message)
        }
        .onChange(of: achievements.latestUnlock?.id) { _, newValue in
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(3.5))
                achievements.clearLatestUnlock()
            }
        }
        .alert(item: $readerAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("好")))
        }
    }

    @ViewBuilder
    private var readerContent: some View {
        if book.kind == .ebook, let ebookPackage {
            EBookReaderView(
                packageURL: library.contentURL(for: book),
                package: ebookPackage,
                chapterIndex: $currentPage,
                chapterProgress: $ebookProgress,
                flow: ebookFlow,
                theme: ebookTheme,
                font: ebookFont,
                fontSize: ebookFontSize,
                lineHeight: ebookLineHeight,
                margin: ebookMargin,
                onTap: toggleControls
            )
        } else if book.kind == .pdf {
            PDFKitReaderView(
                url: library.contentURL(for: book),
                currentPage: $currentPage,
                layout: layout,
                flow: flow,
                order: order,
                coverSingle: coverSingle,
                password: pdfPassword,
                onTap: toggleControls,
                onDocumentState: handlePDFState
            )
        } else if imageURLs.isEmpty {
            ProgressView("正在准备页面…")
                .tint(.white)
                .foregroundStyle(.white)
        } else {
            ImagePagerView(
                imageURLs: imageURLs,
                currentPage: $currentPage,
                layout: layout,
                flow: flow,
                order: order,
                coverSingle: coverSingle,
                backgroundColor: UIColor(backdrop.color),
                onTap: toggleControls
            )
        }
    }

    private var favoriteState: Bool {
        library.books.first(where: { $0.id == book.id })?.isFavorite ?? book.isFavorite
    }

    private var pageFavoriteState: Bool {
        library.isPageFavorite(bookID: book.id, page: currentPage)
    }

    private func handlePDFState(_ count: Int, _ locked: Bool) {
        if count > 0 {
            pageCount = count
            currentPage = min(currentPage, count - 1)
            library.updatePageCount(bookID: book.id, pageCount: count)
        }
        if pdfLocked != locked {
            withAnimation(reduceMotion ? nil : .snappy) {
                pdfLocked = locked
            }
        }
        if !locked,
           (companion.currentBookID != book.id || companion.currentReaction?.page != currentPage) {
            prepareAIPage()
        }
    }

    private func unlockPDF() {
        guard !passwordDraft.isEmpty else { return }
        didTryPassword = true
        pdfPassword = passwordDraft
    }

    private func togglePageFavorite() {
        guard book.kind != .ebook, !pdfLocked else { return }
        let wasFavorite = pageFavoriteState
        library.togglePageFavorite(bookID: book.id, page: currentPage)
        if !wasFavorite { achievements.recordFavoritedPage() }
        showNotice(wasFavorite ? "已取消单页珍藏" : "已放进珍藏角落")
    }

    private func saveCurrentPage() {
        guard !isSavingPage, book.kind != .ebook, !pdfLocked else { return }
        isSavingPage = true
        Task {
            do {
                try await ReaderPageSaveService.save(
                    book: book,
                    page: currentPage,
                    imageURLs: imageURLs,
                    pdfURL: book.kind == .pdf ? library.contentURL(for: book) : nil,
                    pdfPassword: pdfPassword
                )
                achievements.recordSavedPage()
                showNotice("当前画面已保存到照片")
            } catch {
                readerAlert = ReaderAlert(
                    title: "暂时无法保存",
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
            isSavingPage = false
        }
    }

    private func enhanceCurrentPage() {
        guard !isEnhancingPage, book.kind != .ebook, !pdfLocked else { return }
        let source: SharpPageSource?
        switch book.kind {
        case .archive, .imageCollection:
            source = imageURLs.indices.contains(currentPage) ? .image(imageURLs[currentPage]) : nil
        case .pdf:
            source = .pdf(library.contentURL(for: book), page: currentPage, password: pdfPassword)
        case .ebook:
            source = nil
        }
        guard let source else {
            readerAlert = ReaderAlert(title: "无法清晰化", message: "当前页面还没有准备好，请稍后再试。")
            return
        }

        isEnhancingPage = true
        showNotice("正在设备本地进行 Sharp 清晰化…")
        Task {
            do {
                let outputName = "\(book.title)-第\(currentPage + 1)页.png"
                let result: SharpEnhancementResult
                do {
                    result = try await OnDeviceSharpProcessor.shared.enhance(
                        source: source,
                        outputName: outputName
                    )
                } catch {
                    let address = sharpBridgeAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !address.isEmpty else { throw error }
                    showNotice("本机无法处理，已自动改用你的电脑…")
                    result = try await SharpImageService.shared.enhance(
                        source: source,
                        address: address,
                        outputName: outputName
                    )
                }
                let latest = library.books.first(where: { $0.id == book.id }) ?? book
                library.importFiles(
                    [result.outputURL],
                    cleanupDirectory: result.temporaryRoot,
                    shelfGroupID: latest.shelfGroupID,
                    favoriteOnImport: true
                )
                let location = result.executionLocation == .device ? "设备本地" : "你的电脑"
                showNotice("\(location)完成 · 2x PNG 已放进珍藏")
            } catch {
                readerAlert = ReaderAlert(title: "Sharp 清晰化失败", message: error.localizedDescription)
            }
            isEnhancingPage = false
        }
    }

    private func closeReader() {
        library.endReading(book.id)
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func recordReadingPause() {
        guard let start = activeReadingStartedAt else { return }
        achievements.recordReadingDuration(Date.now.timeIntervalSince(start))
        activeReadingStartedAt = nil
    }

    private func showNotice(_ text: String) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.26)) {
            readerNotice = text
        }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard readerNotice == text else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                readerNotice = nil
            }
        }
    }

    private func toggleLayout() {
        if book.kind == .ebook {
            withAnimation(reduceMotion ? nil : .snappy) {
                ebookFlowRaw = ebookFlow == .paged ? EBookFlow.scroll.rawValue : EBookFlow.paged.rawValue
            }
            showControlsTemporarily()
            return
        }
        withAnimation(reduceMotion ? nil : .snappy) {
            layoutRaw = layout == .single ? ReaderLayout.spread.rawValue : ReaderLayout.single.rawValue
        }
        showControlsTemporarily()
    }

    private func saveComicDefaults() {
        defaultLayoutRaw = layoutRaw
        defaultFlowRaw = flowRaw
        defaultOrderRaw = orderRaw
        defaultBackdropRaw = backdropRaw
        defaultCoverSingle = coverSingle
        showNotice("已设为新读物的默认阅读方式")
    }

    private func toggleControls() {
        hideControlsTask?.cancel()
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            controlsVisible.toggle()
        }
        if controlsVisible { scheduleControlsHide() }
    }

    private func showControlsTemporarily() {
        if !controlsVisible {
            withAnimation(reduceMotion ? nil : .snappy) {
                controlsVisible = true
            }
        }
        scheduleControlsHide()
    }

    private func openAICompanion() {
        if companion.currentBookID != book.id || companion.currentReaction?.page != currentPage {
            prepareAIPage(force: true)
        }
        showAICompanion = true
    }

    private func toggleAI() {
        if aiEnabled {
            aiEnabled = false
            companion.cancelAll()
            showAICompanion = false
            showNotice("AI 陪读已关闭")
            return
        }
        guard companion.hasAPIKey else {
            readerAlert = ReaderAlert(
                title: "还没有连接 AI",
                message: "请先到“设置 → AI 陪读”填写 DeepSeek API 密钥，之后这里一按就能开关。"
            )
            return
        }
        aiEnabled = true
        prepareAIPage(force: true)
        showNotice("AI 陪读已开启 · 正在理解本页")
    }

    private func prepareAIPage(force: Bool = false) {
        guard aiEnabled, companion.hasAPIKey else { return }
        let source: AIPageSource?
        switch book.kind {
        case .pdf:
            guard !pdfLocked else { return }
            source = .pdf(library.contentURL(for: book), password: pdfPassword)
        case .archive, .imageCollection:
            source = imageURLs.indices.contains(currentPage) ? .image(imageURLs[currentPage]) : nil
        case .ebook:
            if let ebookPackage, ebookPackage.chapters.indices.contains(currentPage) {
                source = .ebookText(
                    ebookPackage.chapters[currentPage].searchText,
                    format: ebookPackage.format.rawValue
                )
            } else {
                source = nil
            }
        }
        guard let source else { return }
        companion.preparePage(book: book, page: currentPage, pageCount: pageCount, source: source, force: force)
    }

    private func schedulePrefetchPages(around page: Int) {
        prefetchTask?.cancel()
        guard book.kind == .archive || book.kind == .imageCollection, !imageURLs.isEmpty else { return }
        let neighborIndexes = [page + 1, page - 1, page + 2]
            .filter { imageURLs.indices.contains($0) }
        let urls = neighborIndexes.map { imageURLs[$0] }
        guard !urls.isEmpty else { return }

        // Let the visible cell request its quick preview first. Starting full
        // neighbor decodes synchronously here can otherwise make the current
        // page wait behind background work on very large PNG files.
        prefetchTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            ReaderImagePipeline.shared.prefetch(urls, maxPixelSize: 3_072)
        }
    }

    private func scheduleControlsHide() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("INKSHELF_UI_TEST_SEED") || arguments.contains("INKSHELF_UI_TEST_PICKER") {
            return
        }
#endif
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled,
                  !showSettings,
                  !showThumbnails,
                  !showAICompanion,
                  !showEndComments,
                  !pdfLocked
            else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
                controlsVisible = false
            }
        }
    }
}

private struct AICompactTranslationCard: View {
    let translation: AIPageTranslation

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "character.book.closed.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.coral)
                .frame(width: 30, height: 30)
                .background(AppTheme.coral.opacity(0.13), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("本页翻译")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.coral)
                Text(translation.segments.prefix(2).map(\.translation).joined(separator: "　"))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.up")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: 560)
        .inkGlass(cornerRadius: 20, interactive: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("本页日文翻译，点按查看完整内容")
    }
}

private struct ReaderControls: View {
    let title: String
    let kind: BookKind
    let nightMood: String?
    @Binding var currentPage: Int
    let pageCount: Int
    let layout: ReaderLayout
    let ebookFlow: EBookFlow
    let isEBook: Bool
    let aiEnabled: Bool
    let aiActivity: AICompanionActivity
    let isFavorite: Bool
    let isPageFavorite: Bool
    let canUsePageActions: Bool
    let isSavingPage: Bool
    let isEnhancingPage: Bool
    let dismiss: () -> Void
    let toggleFavorite: () -> Void
    let togglePageFavorite: () -> Void
    let savePage: () -> Void
    let enhancePage: () -> Void
    let toggleLayout: () -> Void
    let toggleAI: () -> Void
    let showThumbnails: () -> Void
    let showSettings: () -> Void
    let onInteraction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AdaptiveGlassContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button { perform(dismiss) } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 34, height: 34)
                    }
                    .adaptiveGlassButton()
                    .accessibilityIdentifier("reader-close")
                    .accessibilityLabel("返回书架")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(nightMood.map { "18+ · \($0)" } ?? kind.label)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(nightMood == nil ? Color.secondary : AppTheme.peach)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .inkGlass(cornerRadius: 22)

                    Spacer(minLength: 4)

                    Button { perform(toggleAI) } label: {
                        ZStack {
                            Image(systemName: aiEnabled ? "sparkles.square.fill" : "sparkles")
                                .foregroundStyle(aiEnabled ? AppTheme.accent : .secondary)
                                .opacity(aiActivity.isBusy ? 0.18 : 1)
                                .contentTransition(.symbolEffect(.replace))
                            if aiEnabled, aiActivity.isBusy {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(AppTheme.accent)
                            }
                        }
                        .frame(width: 34, height: 34)
                    }
                    .adaptiveGlassButton()
                    .accessibilityIdentifier("reader-ai-toggle")
                    .accessibilityLabel(aiActivity.isBusy ? "AI 正在理解当前页，点按关闭" : (aiEnabled ? "关闭 AI 陪读" : "开启 AI 陪读"))

                    Button { perform(toggleFavorite) } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? .yellow : .primary)
                            .frame(width: 34, height: 34)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .adaptiveGlassButton()
                    .accessibilityLabel(isFavorite ? "取消收藏" : "收藏")

                    Button { perform(showSettings) } label: {
                        Image(systemName: "slider.horizontal.3")
                            .frame(width: 34, height: 34)
                    }
                    .adaptiveGlassButton()
                    .accessibilityLabel("阅读设置")
                    .accessibilityIdentifier("reader-settings")
                }
            }
            .padding(.horizontal, 14)
            .safeAreaPadding(.top, 8)

            Spacer()

            VStack(spacing: 12) {
                HStack {
                    Text("\(min(currentPage + 1, pageCount))")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .contentTransition(.numericText())

                    Slider(
                        value: Binding(
                            get: { Double(currentPage) },
                            set: {
                                currentPage = Int($0.rounded())
                                onInteraction()
                            }
                        ),
                        in: 0...Double(max(pageCount - 1, 1)),
                        step: 1
                    )
                    .disabled(pageCount <= 1)
                    .tint(nightMood == nil ? AppTheme.accent : AppTheme.coral)
                    .accessibilityIdentifier("reader-progress")
                    .accessibilityLabel("阅读进度")
                    .accessibilityValue("第 \(min(currentPage + 1, pageCount)) 页，共 \(pageCount) 页")

                    Text("\(pageCount)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                }

                HStack(spacing: 8) {
                    Button { perform(showThumbnails) } label: {
                        Image(systemName: isEBook ? "list.bullet.indent" : "square.grid.3x3")
                    }
                    .readerActionButton()
                    .accessibilityIdentifier("reader-thumbnails")
                    .accessibilityLabel(isEBook ? "目录" : "缩略图")

                    Button { perform(toggleLayout) } label: {
                        Image(systemName: isEBook ? ebookFlow.systemImage : layout.systemImage)
                    }
                    .readerActionButton()
                    .accessibilityIdentifier("reader-layout")
                    .accessibilityLabel(isEBook ? ebookFlow.title : (layout == .single ? "单页" : "双页"))

                    if !isEBook {
                        Button { perform(enhancePage) } label: {
                            if isEnhancingPage {
                                ProgressView().tint(.primary)
                            } else {
                                Image(systemName: "wand.and.stars")
                            }
                        }
                        .readerActionButton()
                        .disabled(!canUsePageActions || isEnhancingPage)
                        .accessibilityIdentifier("reader-sharp-enhance")
                        .accessibilityLabel(isEnhancingPage ? "正在 Sharp 清晰化" : "Sharp 清晰化当前页")

                        Button { perform(savePage) } label: {
                            if isSavingPage {
                                ProgressView().tint(.primary)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                            }
                        }
                        .readerActionButton()
                        .disabled(!canUsePageActions || isSavingPage)
                        .accessibilityIdentifier("reader-save-page")
                        .accessibilityLabel(isSavingPage ? "正在保存当前页" : "保存当前页到照片")

                        Button { perform(togglePageFavorite) } label: {
                            Image(systemName: isPageFavorite ? "heart.fill" : "heart")
                                .foregroundStyle(isPageFavorite ? AppTheme.coral : .primary)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .readerActionButton()
                        .disabled(!canUsePageActions)
                        .accessibilityIdentifier("reader-page-favorite")
                        .accessibilityLabel(isPageFavorite ? "取消收藏当前页" : "收藏当前页")
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
            .inkGlass(cornerRadius: 25)
            .padding(.horizontal, 14)
            .safeAreaPadding(.bottom, 8)
        }
        .foregroundStyle(.primary)
    }

    private func perform(_ action: () -> Void) {
        action()
        onInteraction()
    }
}

private struct ReaderAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct AchievementUnlockToast: View {
    let achievement: ReadingAchievement

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: achievement.systemImage)
                .font(.title2)
                .foregroundStyle(AppTheme.coral)
                .symbolEffect(.bounce)
            VStack(alignment: .leading, spacing: 2) {
                Text("点亮新成就").font(.caption.weight(.bold)).foregroundStyle(AppTheme.coral)
                Text(achievement.title).font(.headline)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .inkGlass(cornerRadius: 22)
        .shadow(color: AppTheme.honey.opacity(0.24), radius: 18, y: 8)
    }
}

private struct ReaderNoticeToast: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .inkGlass(cornerRadius: 22)
            .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
            .accessibilityIdentifier("reader-notice")
    }
}

private extension View {
    func readerActionButton() -> some View {
        frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(Rectangle())
    }
}

private struct PDFPasswordOverlay: View {
    @Binding var password: String
    let showError: Bool
    let submit: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.doc.fill")
                .font(.system(size: 34))
                .foregroundStyle(AppTheme.accent)
            Text("此 PDF 已加密")
                .font(.headline)
            SecureField("输入密码", text: $password)
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit(submit)
                .textFieldStyle(.roundedBorder)
            if showError {
                Text("如果仍未打开，请检查密码后重试")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button("解锁", action: submit)
                .adaptiveProminentButton()
                .disabled(password.isEmpty)
        }
        .padding(24)
        .frame(maxWidth: 340)
        .inkGlass(cornerRadius: 28)
        .padding(24)
    }
}
