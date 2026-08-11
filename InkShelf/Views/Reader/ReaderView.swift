import SwiftUI
import UIKit

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(LibraryStore.self) private var library
    let book: Book

    @State private var currentPage: Int
    @State private var pageCount: Int
    @State private var imageURLs: [URL] = []
    @State private var controlsVisible = true
    @State private var showSettings = false
    @State private var showThumbnails = false
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

    init(book: Book) {
        self.book = book
        _currentPage = State(initialValue: min(max(0, book.currentPage), max(0, book.pageCount - 1)))
        _pageCount = State(initialValue: max(1, book.pageCount))
    }

    private var layout: ReaderLayout { ReaderLayout(rawValue: layoutRaw) ?? .single }
    private var flow: ReaderFlow { ReaderFlow(rawValue: flowRaw) ?? .horizontal }
    private var order: ReadingOrder { ReadingOrder(rawValue: orderRaw) ?? .leftToRight }
    private var backdrop: ReaderBackdrop { ReaderBackdrop(rawValue: backdropRaw) ?? .black }

    var body: some View {
        ZStack {
            backdrop.color.ignoresSafeArea()

            readerContent
                .ignoresSafeArea()

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
                    isFavorite: favoriteState,
                    dismiss: { dismiss() },
                    toggleFavorite: { library.toggleFavorite(book.id) },
                    toggleLayout: toggleLayout,
                    showThumbnails: { showThumbnails = true },
                    showSettings: { showSettings = true }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(controlsVisible ? .automatic : .hidden)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: currentPage)
        .onAppear {
            library.markOpened(book.id)
            if book.kind != .pdf {
                imageURLs = library.pageURLs(for: book)
                pageCount = max(1, imageURLs.count)
            }
            UIApplication.shared.isIdleTimerDisabled = keepAwake
            scheduleControlsHide()
        }
        .onChange(of: currentPage) { _, newPage in
            library.updateProgress(bookID: book.id, page: newPage)
            if controlsVisible { scheduleControlsHide() }
        }
        .onChange(of: keepAwake) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
        .onDisappear {
            hideControlsTask?.cancel()
            library.flushProgress()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsView(
                layoutRaw: $layoutRaw,
                flowRaw: $flowRaw,
                orderRaw: $orderRaw,
                backdropRaw: $backdropRaw,
                coverSingle: $coverSingle,
                keepAwake: $keepAwake
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showThumbnails) {
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

    @ViewBuilder
    private var readerContent: some View {
        if book.kind == .pdf {
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
    }

    private func unlockPDF() {
        guard !passwordDraft.isEmpty else { return }
        didTryPassword = true
        pdfPassword = passwordDraft
    }

    private func toggleLayout() {
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

    private func scheduleControlsHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, !showSettings, !showThumbnails, !pdfLocked else { return }
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
    let isFavorite: Bool
    let dismiss: () -> Void
    let toggleFavorite: () -> Void
    let toggleLayout: () -> Void
    let showThumbnails: () -> Void
    let showSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AdaptiveGlassContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button(action: dismiss) {
                        Image(systemName: "chevron.left")
                            .frame(width: 34, height: 34)
                    }
                    .adaptiveGlassButton()
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

                    Button(action: toggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? .yellow : .primary)
                            .frame(width: 34, height: 34)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .adaptiveGlassButton()
                    .accessibilityLabel(isFavorite ? "取消收藏" : "收藏")

                    Button(action: showSettings) {
                        Image(systemName: "ellipsis")
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
                            set: { currentPage = Int($0.rounded()) }
                        ),
                        in: 0...Double(max(pageCount - 1, 1)),
                        step: 1
                    )
                    .disabled(pageCount <= 1)
                    .tint(AppTheme.accent)
                    .accessibilityLabel("阅读进度")
                    .accessibilityValue("第 \(min(currentPage + 1, pageCount)) 页，共 \(pageCount) 页")

                    Text("\(pageCount)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                }

                HStack(spacing: 14) {
                    Button(action: showThumbnails) {
                        Label("缩略图", systemImage: "square.grid.3x3")
                    }
                    .frame(maxWidth: .infinity)

                    Divider().frame(height: 22)

                    Button(action: toggleLayout) {
                        Label(layout == .single ? "单页" : "双页", systemImage: layout.systemImage)
                    }
                    .frame(maxWidth: .infinity)

                    Divider().frame(height: 22)

                    Button(action: showSettings) {
                        Label("设置", systemImage: "slider.horizontal.3")
                    }
                    .frame(maxWidth: .infinity)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .inkGlass(cornerRadius: 25, interactive: true)
            .padding(.horizontal, 14)
            .safeAreaPadding(.bottom, 8)
        }
        .foregroundStyle(.primary)
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
