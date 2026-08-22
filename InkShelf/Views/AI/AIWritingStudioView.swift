import SwiftUI
import UIKit

struct AIWritingStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AICompanionStore.self) private var companion
    let book: Book?

    @State private var subject: String
    @State private var purpose: AIWritingPurpose
    @State private var notes = ""
    @State private var copied = false

    init(book: Book?, initialPurpose: AIWritingPurpose = .recommendation) {
        self.book = book
        _subject = State(initialValue: book?.title ?? "")
        _purpose = State(initialValue: initialPurpose)
    }

    var body: some View {
        Form {
            Section {
                TextField("画集、作品或主题名称", text: $subject)
                TextEditor(text: $notes)
                    .frame(minHeight: 92)
                    .overlay(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("可选：写下作者、画风、感受、想强调的内容……")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            } header: {
                Text("想写什么")
            } footer: {
                Text("AI 只会依据你填写的内容写作，不会读取或上传整本画集。")
            }

            Section("文案类型") {
                Picker("类型", selection: $purpose) {
                    ForEach(AIWritingPurpose.allCases) { item in
                        Label(item.title, systemImage: item.systemImage).tag(item)
                    }
                }
                .pickerStyle(.navigationLink)

                Label(purpose.promptDescription, systemImage: purpose.systemImage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                if companion.hasAPIKey {
                    Button {
                        Task {
                            copied = false
                            await companion.generateWriting(subject: subject, purpose: purpose, notes: notes)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if companion.isWriting {
                                ProgressView().padding(.trailing, 6)
                                Text("正在写…")
                            } else {
                                Label("用 DeepSeek Pro 生成", systemImage: "sparkles")
                            }
                            Spacer()
                        }
                    }
                    .disabled(subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || companion.isWriting)
                } else {
                    ContentUnavailableView(
                        "还没有配置 DeepSeek",
                        systemImage: "key.fill",
                        description: Text("请先到设置中的 DeepSeek 陪读保存 API 密钥。")
                    )
                }
            }

            if let result = companion.writingResult, !result.isEmpty {
                Section("成稿") {
                    Text(result)
                        .font(.body)
                        .textSelection(.enabled)

                    HStack {
                        Button {
                            UIPasteboard.general.string = result
                            copied = true
                        } label: {
                            Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }

                        Spacer()

                        ShareLink(item: result) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }

            if let error = companion.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AuroraBackground())
        .navigationTitle("AI 创作室")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .onDisappear { companion.clearWritingResult() }
    }
}
