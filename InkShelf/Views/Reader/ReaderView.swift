import SwiftUI
import UIKit

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(LibraryStore.self) private var library
    @Environment(AICompanionStore.self) private var companion
    @Environment(RemoteLibraryStore.self) private var remoteLibrary
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

    @AppStorage("reader.layout") private var layoutRaw = ReaderLayout.single.rawValue
    @AppStorage("reader.flow") private var flowRaw = ReaderFlow.horizontal.rawValue
    @AppStorage("reader.order") private var orderRaw = ReadingOrder.leftToRight.rawValue
    @AppStorage("reader.backdrop") private var backdropRaw = ReaderBackdrop.black.rawValue
    @AppStorage("reader.coverSingle") private var coverSingle = true
    @AppStorage("reader.keepAwake") private var keepAwake = true
    @AppStorage("ai.enabled") private var aiEnabled = false
    @AppStorage("ai.autoDanmaku") private var autoDanmaku = true
    @AppStorage("ai.autoShowEnd") private var autoShowEnd = true
    @AppStorage("ebook.flow") private var ebookFlowRaw = EBookFlow.paged.rawValue
    @AppStorage("ebook.theme") private var ebookThemeRaw = EBookTheme.paper.rawValue
    @AppStorage("ebook.font") private var ebookFontRaw = EBookFont.serif.rawValue
    @AppStorage("ebook.fontSize") private var ebookFontSize = 19.0
    @AppStorage("ebook.lineHeight") private var ebookLineHeight = 1.72
    @AppStorage("ebook.margin") private var ebookMargin = 24.0

    init(book: Book, onClose: (() -> Void)? = nil) {
        self.book = book
        self.onClose = onClose
        _currentPage = State(initialValue: min(max(0, book.currentPage), max(0, book.pageCount - 1)))
        _pageCount = State(initialValue: max(1, book.pageCount))
        _ebookProgress = State(initialValue: book.ebookChapterProgress ?? 0)
    }

    private var layout: ReaderLayout { ReaderLayout(rawValue: layoutRaw) ?? .single }
    private var flow: ReaderFlow { ReaderFlow(rawValue: flowRaw) ?? .horizontal }
    private var order: ReadingOrder { ReadingOrder(rawValue: orderRaw) ?? .leftToRight }
    private var backdrop: ReaderBackdrop { ReaderBackdrop(rawValue: backdropRaw) ?? .black }
    private var ebookFlow: EBookFlow { EBookFlow(rawValue: ebookFlowRaw) ?? .paged }
    private var ebookTheme: EBookTheme { EBookTheme(rawValue: ebookThemeRaw) ?? .paper }
    private var ebookFont: EBookFont { EBookFont(rawValue: ebookFontRaw) ?? .serif }

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
                    currentPage: $currentPage,
                    pageCount: pageCount,
                    layout: layout,
                    ebookFlow: ebookFlow,
                    isEBook: book.kind == .ebook,
                    aiEnabled: aiEnabled && companion.hasAPIKey,
                    isFavorite: favoriteState,
                    dismiss: closeReader,
                    toggleFavorite: { library.toggleFavorite(book.id) },
                    toggleLayout: toggleLayout,
                    showAICompanion: openAICompanion,
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
        .onAppear {
            library.beginReading(book.id)
            if book.kind == .ebook {
                ebookPackage = library.ebookPackage(for: book)
                pageCount = max(1, ebookPackage?.chapters.count ?? book.pageCount)
            } else if book.kind != .pdf {
                imageURLs = library.pageURLs(for: book)
                pageCount = max(1, imageURLs.count)
                prefetchPages(around: currentPage)
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
            remoteLibrary.scheduleProgress(book: book, position: newPage, progress: readingProgress)
            if controlsVisible { scheduleControlsHide() }
            prefetchPages(around: newPage)
            prepareAIPage()
        }
        .onChange(of: ebookProgress) { _, newValue in
            guard book.kind == .ebook else { return }
            library.updateEBookProgress(bookID: book.id, chapter: currentPage, progression: newValue)
            remoteLibrary.scheduleProgress(book: book, position: currentPage, progress: readingProgress)
        }
        .onChange(of: keepAwake) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase != .active else { return }
            library.flushProgress()
            remoteLibrary.flushProgress(book: book, position: currentPage, progress: readingProgress)
        }
        .onDisappear {
            hideControlsTask?.cancel()
            companion.cancelAll()
            library.flushProgress()
            remoteLibrary.flushProgress(book: book, position: currentPage, progress: readingProgress)
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
                ebookMargin: $ebookMargin
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

    private var readingProgress: Double {
        if book.kind == .ebook, pageCount > 0 {
            return min(max((Double(currentPage) + ebookProgress) / Double(pageCount), 0), 1)
        }
        guard pageCount > 1 else { return currentPage > 0 ? 1 : 0 }
        return min(max(Double(currentPage) / Double(pageCount - 1), 0), 1)
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

    private func closeReader() {
        library.endReading(book.id)
        if let onClose {
            onClose()
        } else {
            dismiss()
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

    private func prepareAIPage(force: Bool = false) {
        guard aiEnabled, companion.hasAPIKey, force || autoDanmaku else { return }
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

    private func prefetchPages(around page: Int) {
        guard book.kind == .archive || book.kind == .imageCollection, !imageURLs.isEmpty else { return }
        let lowerBound = max(0, page - 1)
        let upperBound = min(imageURLs.count - 1, page + 2)
        guard lowerBound <= upperBound else { return }
        ReaderImagePipeline.shared.prefetch(
            Array(imageURLs[lowerBound...upperBound]),
            maxPixelSize: 3_072
        )
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

private struct ReaderControls: View {
    let title: String
    let kind: BookKind
    @Binding var currentPage: Int
    let pageCount: Int
    let layout: ReaderLayout
    let ebookFlow: EBookFlow
    let isEBook: Bool
    let aiEnabled: Bool
    let isFavorite: Bool
    let dismiss: () -> Void
    let toggleFavorite: () -> Void
    let toggleLayout: () -> Void
    let showAICompanion: () -> Void
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
                        Text(kind.label)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .inkGlass(cornerRadius: 22)

                    Spacer(minLength: 4)

                    Button { perform(showAICompanion) } label: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(aiEnabled ? AppTheme.accent : .secondary)
                            .frame(width: 34, height: 34)
                    }
                    .adaptiveGlassButton()
                    .accessibilityLabel(aiEnabled ? "打开 AI 陪读" : "配置 AI 陪读")

                    Button { perform(toggleFavorite) } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? .yellow : .primary)
                            .frame(width: 34, height: 34)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .adaptiveGlassButton()
                    .accessibilityLabel(isFavorite ? "取消收藏" : "收藏")

                    Button { perform(showSettings) } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 34, height: 34)
                    }
                    .adaptiveGlassButton()
                    .accessibilityLabel("阅读设置")
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
                    .tint(AppTheme.accent)
                    .accessibilityIdentifier("reader-progress")
                    .accessibilityLabel("阅读进度")
                    .accessibilityValue("第 \(min(currentPage + 1, pageCount)) 页，共 \(pageCount) 页")

                    Text("\(pageCount)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                }

                HStack(spacing: 14) {
                    Button { perform(showThumbnails) } label: {
                        Label(isEBook ? "目录" : "缩略图", systemImage: isEBook ? "list.bullet.indent" : "square.grid.3x3")
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("reader-thumbnails")

                    Divider().frame(height: 22)

                    Button { perform(toggleLayout) } label: {
                        Label(
                            isEBook ? ebookFlow.title : (layout == .single ? "单页" : "双页"),
                            systemImage: isEBook ? ebookFlow.systemImage : layout.systemImage
                        )
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("reader-layout")

                    Divider().frame(height: 22)

                    Button { perform(showSettings) } label: {
                        Label("设置", systemImage: "slider.horizontal.3")
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("reader-settings")
                }
                .font(.caption.weight(.semibold))
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
