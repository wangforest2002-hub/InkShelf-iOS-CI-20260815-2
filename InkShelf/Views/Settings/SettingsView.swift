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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    homeOverview
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                }

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

                Section {
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

                Section {
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
                    SettingsSectionHeading(title: "AI 陪读", symbol: "sparkles", tint: AppTheme.lilac)
                }

                Section {
                    NavigationLink {
                        AchievementsView()
                    } label: {
                        SettingsRowLabel(title: "回家足迹与成就", symbol: "medal.star.fill", tint: AppTheme.honey)
                    }
                    .accessibilityIdentifier("settings-achievements")

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
                } header: {
                    SettingsSectionHeading(title: "小家记录", symbol: "house.fill", tint: AppTheme.wood)
                }

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

                Section {
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

                Section {
                    LabeledContent("二次元小家", value: "2.5.3 · 正式版")

                    LabeledContent("界面材质") {
                        Text(materialLabel)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showingWelcome = true
                    } label: {
                        SettingsRowLabel(title: "查看 2.5 正式版欢迎页", symbol: "sparkles.rectangle.stack.fill", tint: AppTheme.coral)
                    }
                    .accessibilityIdentifier("settings-welcome-tour")

                    Toggle("大版本更新时展示欢迎页", isOn: $showWelcomeOnMajorUpdate)

                } header: {
                    SettingsSectionHeading(title: "欢迎与版本", symbol: "heart.text.square.fill", tint: AppTheme.coral)
                } footer: {
                    Text("只在 2.5 这类大版本首次启动时展示；普通修复更新不会反复打扰。也可以随时从这里重新查看。")
                }
            }
            .listSectionSpacing(22)
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .navigationTitle("小家设置")
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
                .foregroundStyle(.secondary)
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
