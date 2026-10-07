import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AICompanionStore.self) private var companion
    @Environment(AppUpdateStore.self) private var updates
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearance") private var appearance = AppAppearance.light.rawValue
    @AppStorage("reader.layout") private var layout = ReaderLayout.single.rawValue
    @AppStorage("reader.flow") private var flow = ReaderFlow.horizontal.rawValue
    @AppStorage("reader.pageTransition") private var pageTransition = ReaderPageTransition.book.rawValue
    @AppStorage("reader.order") private var order = ReadingOrder.leftToRight.rawValue
    @AppStorage("reader.backdrop") private var backdrop = ReaderBackdrop.black.rawValue
    @AppStorage("reader.coverSingle") private var coverSingle = true
    @AppStorage("reader.keepAwake") private var keepAwake = true
    @AppStorage("ebook.flow") private var ebookFlow = EBookFlow.paged.rawValue
    @AppStorage("ebook.theme") private var ebookTheme = EBookTheme.paper.rawValue
    @AppStorage("ebook.font") private var ebookFont = EBookFont.serif.rawValue
    @AppStorage("duplicates.warnOnImport") private var warnOnDuplicateImport = true
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = true
    @AppStorage("welcome.lastSeenRelease") private var lastSeenWelcomeRelease = ""
    @AppStorage("welcome.showOnMajorUpdate") private var showWelcomeOnMajorUpdate = true
    @State private var showingWelcome = false
    @State private var query = ""
    @State private var category: SettingsCategory = .all
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        NavigationStack {
            Form {
                if !query.isEmpty && !hasSearchResults {
                    ContentUnavailableView.search(text: query)
                }
                if query.isEmpty && category == .all { overviewSection }
                if matches(.appearance, keywords: "显示 模式 日间 夜间 外观 主题") { appearanceSection }
                if matches(.reading, keywords: "阅读 默认 双页 单页 布局 翻页 方向 顺序 动效 背景 常亮 封面") { readerSection }
                if matches(.reading, keywords: "电子书 字体 主题 阅读 方式") { ebookSection }
                if matches(.ai, keywords: "日语 中文 图片 翻译 AI 陪读 DeepSeek 密钥 创作") { aiSection }
                if matches(.collection, keywords: "成就 足迹 记录") { recordsSection }
                if matches(.ai, keywords: "清晰化 Sharp 图片") { imageToolsSection }
                if matches(.about, keywords: "应用 更新 版本 在线") { updatesSection }
                if matches(.storage, keywords: "存储 空间 缓存 重复 检测 隐私 导入") { storageSection }
                if matches(.about, keywords: "欢迎 版本 材质 正式版") { aboutSection }
            }
            .listSectionSpacing(22)
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .safeAreaInset(edge: .leading, spacing: 0) {
                if availableWidth >= 900 { categoryRail.frame(width: 190) }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            .safeAreaInset(edge: .top, spacing: 0) {
                if availableWidth < 900 { categoryStrip }
            }
            .navigationTitle("小家设置")
            .searchable(text: $query, prompt: "搜索设置，例如翻译、背景、缓存")
            .sensoryFeedback(.selection, trigger: appearance)
        }
        .fullScreenCover(isPresented: $showingWelcome) {
            WelcomeView {
                hasSeenWelcome = true
                lastSeenWelcomeRelease = WelcomeRelease.current
                showingWelcome = false
            }
        }
    }

    private var overviewSection: some View {
        Section {
                    homeOverview
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                }
    }

    private var appearanceSection: some View {
        Section {
                    Picker("显示模式", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { item in
                            Text(item.title).tag(item.rawValue)
                        }
                    }

                } header: {
                    SettingsSectionHeading(title: "模式与外观", symbol: "paintpalette.fill", tint: AppTheme.lilac)
                } footer: {
                    Text("日间与夜间沿用同一个小家，书籍、分组、最近阅读和成年向档案始终相伴。")
                }
    }

    private var readerSection: some View {
        Section {
                    readingPreview
                    Picker("页面布局", selection: $layout) {
                        ForEach(ReaderLayout.allCases) { item in
                            Label(item.title, systemImage: item.systemImage).tag(item.rawValue)
                        }
                    }

                    Picker("翻页方向", selection: $flow) {
                        ForEach(ReaderFlow.allCases) { item in
                            Label(item.title, systemImage: item.systemImage).tag(item.rawValue)
                        }
                    }

                    Picker("翻页动效", selection: $pageTransition) {
                        ForEach(ReaderPageTransition.allCases) { item in
                            Label(item.title, systemImage: item.systemImage).tag(item.rawValue)
                        }
                    }

                    Picker("阅读顺序", selection: $order) {
                        ForEach(ReadingOrder.allCases) { item in
                            Text(item.title).tag(item.rawValue)
                        }
                    }

                    Picker("阅读背景", selection: $backdrop) {
                        ForEach(ReaderBackdrop.allCases) { item in
                            Text(item.title).tag(item.rawValue)
                        }
                    }

                    Toggle("双页时封面单独显示", isOn: $coverSingle)
                    Toggle("阅读时保持屏幕常亮", isOn: $keepAwake)
                } header: {
                    SettingsSectionHeading(title: "默认阅读方式", symbol: "book.pages.fill", tint: AppTheme.accent)
                }
    }

    private var ebookSection: some View {
        Section {
                    Picker("阅读方式", selection: $ebookFlow) {
                        ForEach(EBookFlow.allCases) { item in
                            Label(item.title, systemImage: item.systemImage).tag(item.rawValue)
                        }
                    }
                    Picker("默认字体", selection: $ebookFont) {
                        ForEach(EBookFont.allCases) { item in
                            Text(item.title).tag(item.rawValue)
                        }
                    }
                    Picker("默认主题", selection: $ebookTheme) {
                        ForEach(EBookTheme.allCases) { item in
                            Text(item.title).tag(item.rawValue)
                        }
                    }
                } header: {
                    SettingsSectionHeading(title: "电子书", symbol: "text.book.closed.fill", tint: AppTheme.wood)
                }
    }

    private var aiSection: some View {
        Section {
                    NavigationLink { TranslationSettingsView() } label: {
                        SettingsRowLabel(title: "日语图片翻译", symbol: "character.bubble.fill", tint: AppTheme.accent)
                    }
                    .accessibilityIdentifier("settings-translation")
                    NavigationLink {
                        AISettingsView()
                    } label: {
                        LabeledContent {
                            Text(companion.hasAPIKey ? "已配置" : "未配置")
                                .foregroundStyle(.secondary)
                        } label: {
                            SettingsRowLabel(title: "DeepSeek 陪读", symbol: "bubble.left.and.text.bubble.right.fill", tint: AppTheme.lilac)
                        }
                    }

                    NavigationLink {
                        AIWritingStudioView(book: nil)
                    } label: {
                        SettingsRowLabel(title: "AI 创作室", symbol: "text.badge.star", tint: AppTheme.coral)
                    }
                } header: {
                    SettingsSectionHeading(title: "翻译与陪读", symbol: "sparkles", tint: AppTheme.lilac)
                }
    }

    private var recordsSection: some View {
        Section {
                    NavigationLink {
                        AchievementsView()
                    } label: {
                        SettingsRowLabel(title: "回家足迹与成就", symbol: "medal.star.fill", tint: AppTheme.honey)
                    }
                    .accessibilityIdentifier("settings-achievements")


                } header: {
                    SettingsSectionHeading(title: "小家记录", symbol: "house.fill", tint: AppTheme.wood)
                }
    }

    private var imageToolsSection: some View {
        Section {
                    NavigationLink {
                        SharpImageSettingsView()
                    } label: {
                        SettingsRowLabel(title: "Sharp 图片清晰化", symbol: "wand.and.stars.inverse", tint: AppTheme.lilac)
                    }
                    .accessibilityIdentifier("settings-sharp")
                } header: {
                    SettingsSectionHeading(title: "图片工具", symbol: "photo.on.rectangle.angled", tint: AppTheme.coral)
                }
    }

    private var updatesSection: some View {
        Section {
                    NavigationLink {
                        UpdateCenterView()
                    } label: {
                        LabeledContent {
                            Text(updates.statusText)
                                .foregroundStyle(updates.availableRelease == nil ? Color.secondary : AppTheme.accent)
                        } label: {
                            SettingsRowLabel(title: "在线更新", symbol: "arrow.down.app.fill", tint: AppTheme.accent)
                        }
                    }
                    .accessibilityIdentifier("settings-online-update")

                } header: {
                    SettingsSectionHeading(title: "应用更新", symbol: "arrow.down.circle.fill", tint: AppTheme.accent)
                } footer: {
                    Text("覆盖安装保留书架、画册缓存、收藏和阅读记录。")
                }
    }

    private var storageSection: some View {
        Section {
                    NavigationLink {
                        StorageManagerView()
                    } label: {
                        LabeledContent {
                            Text(AppFormatters.fileSize(library.storageUsage))
                                .foregroundStyle(.secondary)
                        } label: {
                            SettingsRowLabel(title: "本地存储管家", symbol: "externaldrive.fill", tint: AppTheme.accent)
                        }
                    }
                    LabeledContent("源文件占用") {
                        Text(AppFormatters.fileSize(library.storageUsage))
                    }
                    LabeledContent("本地读物") {
                        Text("\(library.books.count) 本")
                            .monospacedDigit()
                    }

                    Toggle("导入重复内容时提醒", isOn: $warnOnDuplicateImport)

                    NavigationLink {
                        DuplicateContentView()
                    } label: {
                        LabeledContent {
                            Text("扫描书架")
                                .foregroundStyle(.secondary)
                        } label: {
                            SettingsRowLabel(title: "重复内容检测", symbol: "doc.on.doc.fill", tint: AppTheme.wood)
                        }
                    }
                    .accessibilityIdentifier("settings-duplicate-content")

                } header: {
                    SettingsSectionHeading(title: "存储与隐私", symbol: "hand.raised.fill", tint: AppTheme.mint)
                } footer: {
                    Text("从“文件”App 导入时可以直接选择 iCloud Drive 中的读物，应用只保存自己的本地副本，不会修改 iCloud 原文件。启用 AI 后，仅将本机识别出的文字和粗略画面标签发送给 DeepSeek，不上传整页原图。")
                }
    }

    private var aboutSection: some View {
        Section {
                    LabeledContent("二次元小家", value: "3.0.0 · 正式版")

                    LabeledContent("界面材质") {
                        Text(materialLabel)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showingWelcome = true
                    } label: {
                        SettingsRowLabel(title: "查看 3.0 正式版欢迎页", symbol: "sparkles.rectangle.stack.fill", tint: AppTheme.coral)
                    }
                    .accessibilityIdentifier("settings-welcome-tour")

                    Toggle("大版本更新时展示欢迎页", isOn: $showWelcomeOnMajorUpdate)

                } header: {
                    SettingsSectionHeading(title: "欢迎与版本", symbol: "heart.text.square.fill", tint: AppTheme.coral)
                } footer: {
                    Text("只在 3.0 这类大版本首次启动时展示；普通修复更新不会反复打扰。也可以随时从这里重新查看。")
                }
    }

    private var hasSearchResults: Bool {
        ["显示 模式 日间 夜间 外观 主题", "阅读 默认 双页 单页 布局 翻页 方向 顺序 动效 背景 常亮 封面",
         "电子书 字体 主题 阅读 方式", "日语 中文 图片 翻译 AI 陪读 DeepSeek 密钥 创作", "成就 足迹 记录",
         "清晰化 Sharp 图片", "应用 更新 版本 在线", "存储 空间 缓存 重复 检测 隐私 导入", "欢迎 版本 材质 正式版"]
            .contains { $0.localizedStandardContains(query.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func matches(_ target: SettingsCategory, keywords: String) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty { return keywords.localizedStandardContains(term) }
        return category == .all || category == target
    }

    private var categoryRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("布置我的小家").font(.headline).padding(.vertical, 18)
                ForEach(SettingsCategory.allCases) { item in categoryButton(item) }
            }.padding(14)
        }.background(.thinMaterial)
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SettingsCategory.allCases) { item in categoryButton(item) }
            }.padding(.horizontal, 14).padding(.vertical, 8)
        }.background(.regularMaterial)
    }

    private func categoryButton(_ item: SettingsCategory) -> some View {
        Button { category = item; query = "" } label: {
            Label(item.rawValue, systemImage: item.symbol)
                .font(.subheadline.weight(.medium)).padding(11).frame(minHeight: 44)
                .background(category == item ? AppTheme.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).foregroundStyle(category == item ? AppTheme.accent : .primary)
    }

    private var readingPreview: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(0..<(layout == ReaderLayout.spread.rawValue ? 2 : 1), id: \.self) { index in
                    RoundedRectangle(cornerRadius: 6).fill(AppTheme.cream)
                        .overlay {
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: "sun.haze.fill").foregroundStyle(AppTheme.wood)
                                ForEach(0..<3) { _ in Capsule().fill(AppTheme.wood.opacity(0.16)).frame(height: 3) }
                                Text("\(index + 1)").font(.caption2).foregroundStyle(AppTheme.wood)
                            }.padding(14)
                        }
                }
            }.frame(width: layout == ReaderLayout.spread.rawValue ? 200 : 100, height: 120)
                .frame(maxWidth: .infinity).padding(16)
                .background((ReaderBackdrop(rawValue: backdrop) ?? .black).color, in: RoundedRectangle(cornerRadius: 16))
            Text("布局与背景预览 · 新打开的读物使用这些默认值")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 6)
            .animation(reduceMotion ? nil : AppMotion.value, value: layout)
    }

    private var homeOverview: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("我的阅读小家", systemImage: "house.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colorScheme == .dark ? AppTheme.peach : AppTheme.wood)
                    Text("把这里布置成喜欢的样子")
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("阅读习惯、收藏和陪读伙伴，都有自己的位置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !dynamicTypeSize.isAccessibilitySize {
                    CozyWindowView()
                        .frame(width: 66, height: 60)
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize >= .xxxLarge ? 1 : 3),
                alignment: .leading,
                spacing: 8
            ) {
                overviewItem(
                    title: "本地读物",
                    value: "\(library.books.count) 本",
                    symbol: "books.vertical.fill",
                    tint: AppTheme.accent
                )
                overviewItem(
                    title: "显示模式",
                    value: (AppAppearance(rawValue: appearance) ?? .light).title,
                    symbol: colorScheme == .dark ? "moon.stars.fill" : "sun.max.fill",
                    tint: colorScheme == .dark ? AppTheme.lilac : AppTheme.wood
                )
                overviewItem(
                    title: "AI 陪读",
                    value: companion.hasAPIKey ? "已配置" : "待配置",
                    symbol: "sparkles",
                    tint: AppTheme.coral
                )
            }
        }
        .padding(18)
        .inkGlass(cornerRadius: 24)
        .animation(reduceMotion ? nil : AppMotion.value, value: library.books.count)
    }

    private func overviewItem(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(tint.opacity(colorScheme == .dark ? 0.13 : 0.065), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var materialLabel: String {
        if #available(iOS 26.0, *) {
            return "Liquid Glass"
        }
        return "系统动态材质"
    }
}

private struct SettingsSectionHeading: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(Color.primary.opacity(0.82))
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
        .font(.caption.weight(.semibold))
        .textCase(nil)
    }
}

private struct SettingsRowLabel: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case all = "全部"
    case appearance = "外观"
    case reading = "阅读"
    case ai = "翻译与工具"
    case collection = "足迹"
    case storage = "存储"
    case about = "关于"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .all: "house"
        case .appearance: "paintpalette"
        case .reading: "book"
        case .ai: "character.bubble"
        case .collection: "medal"
        case .storage: "externaldrive"
        case .about: "info.circle"
        }
    }
}
