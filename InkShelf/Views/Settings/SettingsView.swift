import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AICompanionStore.self) private var companion
    @Environment(RemoteLibraryStore.self) private var remoteLibrary
    @Environment(ICloudLibraryStore.self) private var iCloudLibrary
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

                Section("云书库") {
                    LabeledContent("iCloud Drive") {
                        Text(iCloudLibrary.folders.isEmpty ? "未连接" : "已连接")
                            .foregroundStyle(iCloudLibrary.folders.isEmpty ? .secondary : .green)
                    }
                    if !iCloudLibrary.folders.isEmpty {
                        LabeledContent("云端索引") {
                            Text("\(iCloudLibrary.books.count) 本 · \(AppFormatters.fileSize(iCloudLibrary.totalCloudSize))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("独立服务器") {
                        Text(remoteLibrary.isOnline ? "已连接" : "未连接")
                            .foregroundStyle(remoteLibrary.isOnline ? .green : .secondary)
                    }
                    Text("默认可连接“文件”App 中的 iCloud Drive 文件夹：只索引书名和大小，首次打开才下载，之后可离线阅读。独立服务器仍作为备用来源。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("存储与隐私") {
                    LabeledContent("源文件占用") {
                        Text(AppFormatters.fileSize(library.storageUsage))
                    }
                    LabeledContent("本地读物") {
                        Text("\(library.books.count) 本")
                    }

                    Label {
                        Text("本地导入与云端缓存不会修改原文件。删除 iCloud 本地副本或断开文件夹不会删除 iCloud 原书；独立服务器不设密码，知道地址的人都能管理其中的书籍。启用 AI 后，仅将本机识别出的文字和粗略画面标签发送给 DeepSeek，不上传整页原图。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                }

                Section("关于") {
                    LabeledContent("墨阅", value: "1.3.0")
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
