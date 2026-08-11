import SwiftUI

struct ReaderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var layoutRaw: String
    @Binding var flowRaw: String
    @Binding var orderRaw: String
    @Binding var backdropRaw: String
    @Binding var coverSingle: Bool
    @Binding var keepAwake: Bool

    var body: some View {
        NavigationStack {
            Form {
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

                Section {
                    Label("双击页面可快速放大，再次双击恢复；单击页面可隐藏控制栏。", systemImage: "hand.tap.fill")
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

