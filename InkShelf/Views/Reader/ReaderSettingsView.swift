import SwiftUI

struct ReaderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var layoutRaw: String
    @Binding var flowRaw: String
    @Binding var orderRaw: String
    @Binding var backdropRaw: String
    @Binding var coverSingle: Bool
    @Binding var keepAwake: Bool
    let isEBook: Bool
    @Binding var ebookFlowRaw: String
    @Binding var ebookThemeRaw: String
    @Binding var ebookFontRaw: String
    @Binding var ebookFontSize: Double
    @Binding var ebookLineHeight: Double
    @Binding var ebookMargin: Double
    let saveComicDefaults: () -> Void
    @AppStorage("ai.enabled") private var aiEnabled = false
    @AppStorage("ai.autoDanmaku") private var autoDanmaku = true
    @AppStorage("ai.density") private var aiDensity = AIDanmakuDensity.balanced.rawValue
    @AppStorage("ai.endComments") private var aiEndComments = true
    @State private var didSaveComicDefaults = false

    var body: some View {
        NavigationStack {
            Form {
                if isEBook {
                    Section("电子书排版") {
                        Picker("阅读方式", selection: $ebookFlowRaw) {
                            ForEach(EBookFlow.allCases) { item in
                                Label(item.title, systemImage: item.systemImage).tag(item.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("字体", selection: $ebookFontRaw) {
                            ForEach(EBookFont.allCases) { item in
                                Text(item.title).tag(item.rawValue)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("字号", value: "\(Int(ebookFontSize))")
                            Slider(value: $ebookFontSize, in: 14...32, step: 1)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("行距", value: ebookLineHeight.formatted(.number.precision(.fractionLength(1))))
                            Slider(value: $ebookLineHeight, in: 1.2...2.2, step: 0.1)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("页边距", value: "\(Int(ebookMargin))")
                            Slider(value: $ebookMargin, in: 12...48, step: 2)
                        }
                    }

                    Section("阅读主题") {
                        Picker("主题", selection: $ebookThemeRaw) {
                            ForEach(EBookTheme.allCases) { item in
                                Text(item.title).tag(item.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        Toggle("保持屏幕常亮", isOn: $keepAwake)
                    }
                } else {
                    Section("页面布局") {
                        Picker("页面布局", selection: $layoutRaw) {
                            ForEach(ReaderLayout.allCases) { item in
                                Label(item.title, systemImage: item.systemImage).tag(item.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)

                        Toggle("双页时封面单独显示", isOn: $coverSingle)
                    }

                    Section("翻页") {
                        Picker("方向", selection: $flowRaw) {
                            ForEach(ReaderFlow.allCases) { item in
                                Label(item.title, systemImage: item.systemImage).tag(item.rawValue)
                            }
                        }
                        .accessibilityIdentifier("reader-flow")

                        Picker("顺序", selection: $orderRaw) {
                            ForEach(ReadingOrder.allCases) { item in
                                Label(item.title, systemImage: item.systemImage).tag(item.rawValue)
                            }
                        }
                    }

                    Section("显示") {
                        Picker("背景", selection: $backdropRaw) {
                            ForEach(ReaderBackdrop.allCases) { item in
                                Text(item.title).tag(item.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)

                        Toggle("保持屏幕常亮", isOn: $keepAwake)
                    }

                    Section("阅读预设") {
                        LabeledContent("当前设置", value: "自动记住到本书")
                        Button {
                            saveComicDefaults()
                            withAnimation(.snappy) { didSaveComicDefaults = true }
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                withAnimation(.easeOut) { didSaveComicDefaults = false }
                            }
                        } label: {
                            Label(
                                didSaveComicDefaults ? "已设为新读物默认" : "设为新读物默认",
                                systemImage: didSaveComicDefaults ? "checkmark.circle.fill" : "square.and.arrow.down"
                            )
                        }
                        .accessibilityIdentifier("reader-save-defaults")
                        Text("每本漫画和画集会分别记住布局、方向、顺序与背景，切换作品时不再互相影响。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("AI 陪读") {
                    Toggle("启用 AI 陪读", isOn: $aiEnabled)
                    Toggle("翻页后显示滚动弹幕", isOn: $autoDanmaku)
                        .disabled(!aiEnabled)
                    Picker("弹幕密度", selection: $aiDensity) {
                        ForEach(AIDanmakuDensity.allCases) { density in
                            Text(density.title).tag(density.rawValue)
                        }
                    }
                    .disabled(!aiEnabled || !autoDanmaku)
                    Toggle("读完后生成模拟评论", isOn: $aiEndComments)
                        .disabled(!aiEnabled)
                }

                Section {
                    Label(
                        isEBook ? "从屏幕边缘继续滑动可切换章节；单击正文可隐藏控制栏。" : "双击页面可快速放大，再次双击恢复；单击页面可隐藏控制栏。",
                        systemImage: "hand.tap.fill"
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
