import SwiftUI
import UIKit

struct AfterDarkLoungeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ambientMotionEnabled) private var ambientMotionEnabled
    @State private var selectedMood: BookMood?
    @State private var drawnBook: Book?
    @State private var openedBook: Book?
    @State private var editingBook: Book?
    @State private var aiWritingBook: Book?
    @State private var drawTrigger = 0
    @State private var ritualOffset = 0

    private var candidates: [Book] {
        let readable = library.books.filter { $0.storageState != .coverOnly }
        guard let selectedMood else {
            let nightBooks = readable.filter(\.belongsToAfterDark)
            return nightBooks.isEmpty ? readable : nightBooks
        }
        let matched = readable.filter { $0.mood == selectedMood }
        return matched.isEmpty ? readable : matched
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AfterDarkBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        AfterDarkHero(
                            nightCount: library.afterDarkBooks.count,
                            favoritePages: library.favoritePageItems.count
                        )

                        moodSelector

                        TonightDrawCard(
                            book: drawnBook,
                            coverURL: drawnBook.flatMap { library.coverURL(for: $0) },
                            invitation: selectedMood?.invitation ?? "把选择交给今晚的直觉",
                            draw: drawBook,
                            open: { if let drawnBook { open(drawnBook) } },
                            edit: { editingBook = drawnBook },
                            write: { aiWritingBook = drawnBook }
                        )

                        NightRitualCard(prompt: currentPrompt) {
                            withAnimation(.snappy(duration: 0.35)) {
                                ritualOffset += 1
                            }
                        }

                        if !library.afterDarkBooks.isEmpty {
                            nightShelf
                        } else if !library.books.isEmpty {
                            EmptyNightShelfCard(book: library.books.first) {
                                editingBook = library.books.first
                            }
                        }

                        TasteProfileCard(books: library.afterDarkBooks)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("成年人夜读")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("随机抽一本", systemImage: "shuffle", action: drawBook)
                        if let drawnBook {
                            Button("编辑当前作品档案", systemImage: "heart.text.square") {
                                editingBook = drawnBook
                            }
                        }
                    } label: {
                        Label("夜读菜单", systemImage: "moon.stars.fill")
                    }
                }
            }
            .navigationDestination(item: $openedBook) { book in
                ReaderView(book: book) { openedBook = nil }
            }
        }
        .environment(\.ambientMotionEnabled, ambientMotionEnabled && openedBook == nil)
        .sheet(item: $editingBook) { book in
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
                drawnBook = library.books.first(where: { $0.id == book.id })
            }
        }
        .sheet(item: $aiWritingBook) { book in
            NavigationStack {
                AIWritingStudioView(book: book, initialPurpose: .afterDark)
            }
        }
        .alert(item: alertBinding) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("好")))
        }
        .onAppear {
            guard drawnBook == nil else { return }
            drawnBook = candidates.first
        }
        .onChange(of: selectedMood) { _, _ in drawBook() }
        .sensoryFeedback(.selection, trigger: drawTrigger)
    }

    private var moodSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            NightSectionTitle(title: "今晚想看什么", subtitle: "按此刻的心情挑")
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    MoodChip(title: "随心", systemImage: "wand.and.stars", selected: selectedMood == nil) {
                        selectedMood = nil
                    }
                    ForEach(BookMood.allCases) { mood in
                        MoodChip(
                            title: mood.shortTitle,
                            systemImage: mood.systemImage,
                            selected: selectedMood == mood
                        ) {
                            selectedMood = mood
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var nightShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            NightSectionTitle(
                title: "我的夜读收藏",
                subtitle: "\(library.afterDarkBooks.count) 本只属于今晚"
            )
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(library.afterDarkBooks) { book in
                        Button { open(book) } label: {
                            NightBookCard(book: book, coverURL: library.coverURL(for: book))
                        }
                        .buttonStyle(PressableCardStyle())
                        .contextMenu {
                            Button("编辑心动档案", systemImage: "heart.text.square") {
                                editingBook = book
                            }
                            Button("AI 写夜读私语", systemImage: "text.badge.star") {
                                aiWritingBook = book
                            }
                            Button("移出夜读", systemImage: "moon.stars") {
                                library.toggleAfterDark(book.id)
                                if drawnBook?.id == book.id { drawBook() }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var currentPrompt: NightReadingPrompt {
        let prompts = NightReadingPrompt.collection
        return prompts[abs(ritualOffset) % prompts.count]
    }

    private var alertBinding: Binding<LibraryAlert?> {
        Binding(get: { library.alert }, set: { library.alert = $0 })
    }

    private func drawBook() {
        guard !candidates.isEmpty else {
            drawnBook = nil
            return
        }
        let otherBooks = candidates.filter { $0.id != drawnBook?.id }
        let pool = otherBooks.isEmpty ? candidates : otherBooks
        withAnimation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.76)) {
            drawnBook = pool.randomElement()
            drawTrigger += 1
        }
    }

    private func open(_ book: Book) {
        if let error = library.openingError(for: book) {
            library.alert = error
        } else {
            openedBook = book
        }
    }
}

private struct AfterDarkBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.ambientMotionEnabled) private var ambientMotionEnabled
    @State private var drifting = false

    private var canAnimate: Bool {
        ambientMotionEnabled && scenePhase == .active && !reduceMotion
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.045, blue: 0.12),
                    Color(red: 0.15, green: 0.055, blue: 0.15),
                    Color(red: 0.05, green: 0.055, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppTheme.coral.opacity(0.27), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 220
                    )
                )
                .frame(width: 460, height: 460)
                .offset(x: drifting ? 170 : 80, y: drifting ? -260 : -180)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppTheme.lilac.opacity(0.23), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 250
                    )
                )
                .frame(width: 520, height: 520)
                .offset(x: drifting ? -170 : -80, y: drifting ? 300 : 210)

            LinearGradient(
                colors: [.clear, AppTheme.peach.opacity(0.08), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .rotationEffect(.degrees(-24))
            .offset(x: drifting ? 160 : -180)
        }
        .ignoresSafeArea()
        .task(id: canAnimate) {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { drifting = false }
            guard canAnimate else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true)) {
                drifting = true
            }
        }
        .accessibilityHidden(true)
    }
}

private struct AfterDarkHero: View {
    let nightCount: Int
    let favoritePages: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.ambientMotionEnabled) private var ambientMotionEnabled
    @State private var breathing = false

    private var canAnimate: Bool {
        ambientMotionEnabled && scenePhase == .active && !reduceMotion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AFTER DARK · 18+")
                        .font(.caption2.weight(.black))
                        .tracking(1.5)
                        .foregroundStyle(AppTheme.peach)
                    Text("今晚，只看让你\n心动的那一页")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Text("为成年人准备的二次元夜读空间")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                }
                Spacer(minLength: 12)
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 34, weight: .light))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(AppTheme.peach, AppTheme.lilac)
                    .padding(16)
                    .background(.white.opacity(breathing ? 0.12 : 0.07), in: Circle())
                    .scaleEffect(breathing ? 1.035 : 0.985)
                    .shadow(color: AppTheme.coral.opacity(0.26), radius: 14)
            }

            HStack(spacing: 10) {
                NightStatChip(symbol: "moon.fill", value: "\(nightCount)", title: "夜读藏品")
                NightStatChip(symbol: "heart.fill", value: "\(favoritePages)", title: "心动单页")
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.12), AppTheme.coral.opacity(0.09), AppTheme.lilac.opacity(0.11)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.30), radius: 28, y: 14)
        .task(id: canAnimate) {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { breathing = false }
            guard canAnimate else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("after-dark-hero")
    }
}

private struct NightStatChip: View {
    let symbol: String
    let value: String
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).foregroundStyle(AppTheme.peach)
            Text(value).font(.subheadline.monospacedDigit().bold())
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.64))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.black.opacity(0.16), in: Capsule())
    }
}

private struct MoodChip: View {
    let title: String
    let systemImage: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? Color(red: 0.25, green: 0.08, blue: 0.12) : .white.opacity(0.76))
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(
                    selected
                        ? AnyShapeStyle(LinearGradient(colors: [AppTheme.peach, AppTheme.coral.opacity(0.88)], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.white.opacity(0.08)),
                    in: Capsule()
                )
                .overlay { Capsule().stroke(.white.opacity(selected ? 0.28 : 0.10), lineWidth: 0.8) }
        }
        .buttonStyle(.plain)
    }
}

private struct TonightDrawCard: View {
    let book: Book?
    let coverURL: URL?
    let invitation: String
    let draw: () -> Void
    let open: () -> Void
    let edit: () -> Void
    let write: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NightSectionTitle(title: "今晚翻牌", subtitle: invitation)

            if let book {
                HStack(spacing: 17) {
                    CoverArtwork(book: book, coverURL: coverURL, previewURLs: [])
                        .frame(width: 104, height: 146)
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.42), radius: 16, y: 9)

                    VStack(alignment: .leading, spacing: 9) {
                        if let mood = book.mood {
                            Label(mood.title, systemImage: mood.systemImage)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.peach)
                        }
                        Text(book.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                        Text(book.progressLabel)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.60))
                        RatingMiniature(book: book)

                        HStack(spacing: 9) {
                            Button("打开", action: open)
                                .buttonStyle(NightPrimaryButtonStyle())
                            Button(action: edit) {
                                Image(systemName: "heart.text.square")
                                    .frame(width: 34, height: 34)
                            }
                            .buttonStyle(NightRoundButtonStyle())
                            Button(action: write) {
                                Image(systemName: "text.badge.star")
                                    .frame(width: 34, height: 34)
                            }
                            .buttonStyle(NightRoundButtonStyle())
                        }
                    }
                }
                .padding(16)
                .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .stroke(.white.opacity(0.11), lineWidth: 1)
                }
                .id(book.id)
                .transition(.asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity), removal: .opacity))

                Button(action: draw) {
                    Label("换一本，再心动一次", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NightSecondaryButtonStyle())
            } else {
                ContentUnavailableView(
                    "书架还是空的",
                    systemImage: "books.vertical",
                    description: Text("先导入画集或漫画，今晚的翻牌才会开始。")
                )
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .accessibilityIdentifier("after-dark-draw")
    }
}

private struct NightRitualCard: View {
    let prompt: NightReadingPrompt
    let next: () -> Void

    var body: some View {
        Button(action: next) {
            HStack(spacing: 14) {
                Image(systemName: prompt.systemImage)
                    .font(.title2)
                    .foregroundStyle(AppTheme.peach)
                    .frame(width: 50, height: 50)
                    .background(AppTheme.coral.opacity(0.13), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("今晚的小玩法")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.peach)
                    Text(prompt.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(prompt.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.white.opacity(0.52))
            }
            .padding(16)
            .background(
                LinearGradient(colors: [AppTheme.lilac.opacity(0.16), Color.white.opacity(0.06)], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay { RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.10), lineWidth: 1) }
        }
        .buttonStyle(PressableCardStyle())
        .id(prompt.id)
        .transition(.push(from: .trailing).combined(with: .opacity))
    }
}

private struct NightBookCard: View {
    let book: Book
    let coverURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverArtwork(book: book, coverURL: coverURL, previewURLs: [])
                .frame(width: 126, height: 178)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if let mood = book.mood {
                        Image(systemName: mood.systemImage)
                            .font(.caption.bold())
                            .foregroundStyle(Color(red: 0.25, green: 0.07, blue: 0.12))
                            .padding(8)
                            .background(AppTheme.peach, in: Circle())
                            .padding(7)
                    }
                }
            Text(book.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(width: 126, alignment: .leading)
            RatingMiniature(book: book)
        }
    }
}

private struct EmptyNightShelfCard: View {
    let book: Book?
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NightSectionTitle(title: "建立你的夜读收藏", subtitle: "给喜欢的成年向作品加上心动档案")
            Button(action: edit) {
                HStack(spacing: 14) {
                    Image(systemName: "moon.stars.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.peach)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(book.map { "从“\($0.title)”开始" } ?? "先从书架导入作品")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text("标记氛围、标签、心动和涩气指数")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.45))
                }
                .padding(16)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
            }
            .buttonStyle(PressableCardStyle())
            .disabled(book == nil)
        }
    }
}

private struct TasteProfileCard: View {
    let books: [Book]

    private var topMood: BookMood? {
        Dictionary(grouping: books.compactMap(\.mood), by: { $0 })
            .max { $0.value.count < $1.value.count }?.key
    }

    private var rated: [Book] { books.filter { $0.normalizedHeartRating > 0 || $0.normalizedSpiceRating > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NightSectionTitle(title: "我的心动偏好", subtitle: rated.isEmpty ? "评分后会慢慢长出来" : "从你的评分里读懂偏好")
            HStack(spacing: 12) {
                TasteMetric(
                    symbol: topMood?.systemImage ?? "sparkles",
                    value: topMood?.shortTitle ?? "待发现",
                    title: "常看氛围",
                    tint: AppTheme.lilac
                )
                TasteMetric(
                    symbol: "heart.fill",
                    value: average(\.normalizedHeartRating),
                    title: "平均心动",
                    tint: AppTheme.coral
                )
                TasteMetric(
                    symbol: "flame.fill",
                    value: average(\.normalizedSpiceRating),
                    title: "平均涩气",
                    tint: AppTheme.peach
                )
            }
        }
    }

    private func average(_ keyPath: KeyPath<Book, Int>) -> String {
        let values = books.map { $0[keyPath: keyPath] }.filter { $0 > 0 }
        guard !values.isEmpty else { return "—" }
        return String(format: "%.1f", Double(values.reduce(0, +)) / Double(values.count))
    }
}

private struct TasteMetric: View {
    let symbol: String
    let value: String
    let title: String
    let tint: Color

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.52))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct RatingMiniature: View {
    let book: Book

    var body: some View {
        HStack(spacing: 8) {
            if book.normalizedHeartRating > 0 {
                Label("\(book.normalizedHeartRating)", systemImage: "heart.fill")
                    .foregroundStyle(AppTheme.coral)
            }
            if book.normalizedSpiceRating > 0 {
                Label("\(book.normalizedSpiceRating)", systemImage: "flame.fill")
                    .foregroundStyle(AppTheme.peach)
            }
        }
        .font(.caption2.bold())
    }
}

private struct NightSectionTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline).foregroundStyle(.white)
            Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.54))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct NightPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color(red: 0.25, green: 0.07, blue: 0.12))
            .padding(.horizontal, 18)
            .frame(height: 35)
            .background(AppTheme.peach, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

private struct NightSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.82))
            .padding(.vertical, 12)
            .background(.white.opacity(configuration.isPressed ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct NightRoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(0.78))
            .background(.white.opacity(configuration.isPressed ? 0.16 : 0.08), in: Circle())
    }
}

struct BookProfileDraft {
    let isAfterDark: Bool
    let mood: BookMood?
    let tags: [String]
    let personalNote: String
    let heartRating: Int
    let spiceRating: Int
}

struct BookProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let book: Book
    let onSave: (BookProfileDraft) -> Void

    @State private var isAfterDark: Bool
    @State private var mood: BookMood?
    @State private var tags: Set<String>
    @State private var customTag = ""
    @State private var personalNote: String
    @State private var heartRating: Int
    @State private var spiceRating: Int

    init(book: Book, onSave: @escaping (BookProfileDraft) -> Void) {
        self.book = book
        self.onSave = onSave
        _isAfterDark = State(initialValue: book.belongsToAfterDark)
        _mood = State(initialValue: book.mood)
        _tags = State(initialValue: Set(book.normalizedTags))
        _personalNote = State(initialValue: book.personalNote ?? "")
        _heartRating = State(initialValue: book.normalizedHeartRating)
        _spiceRating = State(initialValue: book.normalizedSpiceRating)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("加入成年向特色", isOn: $isAfterDark)
                        .tint(AppTheme.coral)
                    Label {
                        Text("成年向特色只用于明确为成年角色的作品，不收录或性化未成年、年龄不明角色。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "18.circle.fill").foregroundStyle(AppTheme.coral)
                    }
                }

                Section("今晚的氛围") {
                    Picker("主要氛围", selection: $mood) {
                        Text("暂不分类").tag(BookMood?.none)
                        ForEach(BookMood.allCases) { item in
                            Label(item.title, systemImage: item.systemImage).tag(BookMood?.some(item))
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("心动档案") {
                    StarRatingRow(title: "心动指数", systemImage: "heart.fill", tint: AppTheme.coral, value: $heartRating)
                    StarRatingRow(title: "涩气指数", systemImage: "flame.fill", tint: .orange, value: $spiceRating)
                }

                Section("标签") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                        ForEach(AfterDarkTagCatalog.suggestions, id: \.self) { tag in
                            Button {
                                if !tags.insert(tag).inserted { tags.remove(tag) }
                            } label: {
                                Text(tag)
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(tags.contains(tag) ? .white : .secondary)
                                    .background(tags.contains(tag) ? AppTheme.coral : Color.secondary.opacity(0.10), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        TextField("自定义标签", text: $customTag)
                            .submitLabel(.done)
                            .onSubmit(addCustomTag)
                        Button("添加", action: addCustomTag)
                            .disabled(customTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if !extraTags.isEmpty {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(extraTags, id: \.self) { tag in
                                    Button { tags.remove(tag) } label: {
                                        Label(tag, systemImage: "xmark.circle.fill")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }

                Section("只写给自己的话") {
                    TextEditor(text: $personalNote)
                        .frame(minHeight: 110)
                        .overlay(alignment: .topLeading) {
                            if personalNote.isEmpty {
                                Text("记下最心动的画面、角色魅力或读完后的余韵……")
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .navigationTitle("心动档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                }
            }
        }
    }

    private var extraTags: [String] {
        tags.subtracting(Set(AfterDarkTagCatalog.suggestions)).sorted()
    }

    private func addCustomTag() {
        let cleaned = String(customTag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
        guard !cleaned.isEmpty else { return }
        tags.insert(cleaned)
        customTag = ""
    }

    private func save() {
        onSave(BookProfileDraft(
            isAfterDark: isAfterDark,
            mood: mood,
            tags: tags.sorted(),
            personalNote: personalNote,
            heartRating: heartRating,
            spiceRating: spiceRating
        ))
        dismiss()
    }
}

private struct StarRatingRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    @Binding var value: Int

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            HStack(spacing: 5) {
                ForEach(1...5, id: \.self) { score in
                    Button {
                        value = value == score ? 0 : score
                    } label: {
                        Image(systemName: score <= value ? systemImage : outlineSymbol)
                            .foregroundStyle(score <= value ? tint : Color.secondary.opacity(0.34))
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(score) 分")
                }
            }
        }
    }

    private var outlineSymbol: String {
        systemImage == "heart.fill" ? "heart" : "flame"
    }
}
