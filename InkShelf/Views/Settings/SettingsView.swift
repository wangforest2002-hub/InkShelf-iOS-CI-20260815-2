import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AICompanionStore.self) private var companion
    @AppStorage("appearance") private var appearance = AppAppearance.light.rawValue
    @AppStorage("reader.layout") private var layout = ReaderLayout.single.rawValue
    @AppStorage("reader.flow") private var flow = ReaderFlow.horizontal.rawValue
    @AppStorage("reader.order") private var order = ReadingOrder.leftToRight.rawValue
    @AppStorage("reader.backdrop") private var backdrop = ReaderBackdrop.black.rawValue
    @AppStorage("reader.coverSingle") private var coverSingle = true
    @AppStorage("reader.keepAwake") private var keepAwake = true
    @AppStorage("ebook.flow") private var ebookFlow = EBookFlow.paged.rawValue
    @AppStorage("ebook.theme") private var ebookTheme = EBookTheme.paper.rawValue
    @AppStorage("ebook.font") private var ebookFont = EBookFont.serif.rawValue
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = true

    var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Picker("应用外观", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { item in
                            Text(item.title).tag(item.rawValue)
                        }
                    }

                    LabeledContent("界面材质") {
                        Text(materialLabel)
                            .foregroundStyle(.secondary)
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
                }

                Section("存储与隐私") {
                    LabeledContent("源文件占用") {
                        Text(AppFormatters.fileSize(library.storageUsage))
                    }
                    LabeledContent("本地读物") {
                        Text("\(library.books.count) 本")
                    }

                    Label {
                        Text("源文件与阅读记录只保存在本机，封面缓存仅用于书架显示，原文件不会被修改。启用 AI 后，仅将本机识别出的文字和粗略画面标签发送给 DeepSeek。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                }

                Section("关于") {
                    LabeledContent("墨阅", value: "1.0.0")
                    Button("重新查看欢迎页") {
                        hasSeenWelcome = false
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .navigationTitle("设置")
        }
    }

    private var materialLabel: String {
        if #available(iOS 26.0, *) {
            return "Liquid Glass"
        }
        return "系统动态材质"
    }
}
