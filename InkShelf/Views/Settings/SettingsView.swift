import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AICompanionStore.self) private var companion
    @Environment(AppUpdateStore.self) private var updates
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        CozyWindowView()
                            .frame(width: 84, height: 62)
                        VStack(alignment: .leading, spacing: 5) {
                            Label("把这里布置成喜欢的样子", systemImage: "house.fill")
                                .font(.headline)
                            Text("阅读习惯、收藏和陪读伙伴都安放在这里。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                }

                Section("模式与外观") {
                    Picker("显示模式", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { item in
                            Text(item.title).tag(item.rawValue)
                        }
                    }

                    LabeledContent("界面材质") {
                        Text(materialLabel)
                            .foregroundStyle(.secondary)
                    }

                    Label {
                        Text("夜间模式只切换全局色彩与阅读氛围，不再建立另一套书架；全部书籍、搜索、分组和最近阅读都能照常使用，成年向档案也会保留。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "moon.stars.fill")
                            .foregroundStyle(AppTheme.lilac)
                    }
                }

                Section("默认阅读方式") {
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
                }

                Section("电子书") {
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
                }

                Section("AI 陪读") {
                    NavigationLink {
                        AISettingsView()
                    } label: {
                        LabeledContent("DeepSeek 陪读") {
                            Text(companion.hasAPIKey ? "已配置" : "未配置")
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        AIWritingStudioView(book: nil)
                    } label: {
                        Label("AI 创作室", systemImage: "text.badge.star")
                    }
                }

                Section("小家记录") {
                    NavigationLink {
                        AchievementsView()
                    } label: {
                        Label("回家足迹与成就", systemImage: "medal.star.fill")
                    }
                    .accessibilityIdentifier("settings-achievements")

                    NavigationLink {
                        StorageManagerView()
                    } label: {
                        LabeledContent {
                            Text(AppFormatters.fileSize(library.storageUsage))
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("本地存储管家", systemImage: "externaldrive.fill")
                        }
                    }
                }

                Section("图片工具") {
                    NavigationLink {
                        SharpImageSettingsView()
                    } label: {
                        Label("Sharp 图片清晰化", systemImage: "wand.and.stars.inverse")
                    }
                    .accessibilityIdentifier("settings-sharp")
                }

                Section("应用更新") {
                    NavigationLink {
                        UpdateCenterView()
                    } label: {
                        LabeledContent {
                            Text(updates.statusText)
                                .foregroundStyle(updates.availableRelease == nil ? Color.secondary : AppTheme.accent)
                        } label: {
                            Label("在线更新", systemImage: "arrow.down.app.fill")
                        }
                    }
                    .accessibilityIdentifier("settings-online-update")

                    Label {
                        Text("覆盖安装只替换应用本体，不删除书架、画册缓存、收藏和阅读记录。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(AppTheme.mint)
                    }
                }

                Section("存储与隐私") {
                    LabeledContent("源文件占用") {
                        Text(AppFormatters.fileSize(library.storageUsage))
                    }
                    LabeledContent("本地读物") {
                        Text("\(library.books.count) 本")
                    }

                    Toggle("导入重复内容时提醒", isOn: $warnOnDuplicateImport)

                    NavigationLink {
                        DuplicateContentView()
                    } label: {
                        LabeledContent {
                            Text("扫描书架")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("重复内容检测", systemImage: "doc.on.doc.fill")
                        }
                    }
                    .accessibilityIdentifier("settings-duplicate-content")

                    Label {
                        Text("从“文件”App 导入时可以直接选择 iCloud Drive 中的读物，应用只保存自己的本地副本，不会修改 iCloud 原文件。启用 AI 后，仅将本机识别出的文字和粗略画面标签发送给 DeepSeek，不上传整页原图。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                }

                Section("关于") {
                    LabeledContent("二次元小家", value: "2.4.4 · 书架焕新版")
                    Button("重新查看欢迎页") {
                        hasSeenWelcome = false
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .navigationTitle("小家设置")
        }
    }

    private var materialLabel: String {
        if #available(iOS 26.0, *) {
            return "Liquid Glass"
        }
        return "系统动态材质"
    }
}
