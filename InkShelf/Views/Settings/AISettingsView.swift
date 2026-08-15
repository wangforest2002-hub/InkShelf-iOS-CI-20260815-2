import SwiftUI

struct AISettingsView: View {
    @Environment(AICompanionStore.self) private var companion
    @State private var keyDraft = ""
    @State private var showKey = false
    @State private var showRemoveConfirmation = false

    @AppStorage("ai.enabled") private var enabled = false
    @AppStorage("ai.model") private var modelRaw = AIModelChoice.pro.rawValue
    @AppStorage("ai.persona") private var personaRaw = AICompanionPersona.friend.rawValue
    @AppStorage("ai.density") private var densityRaw = AIDanmakuDensity.balanced.rawValue
    @AppStorage("ai.autoDanmaku") private var autoDanmaku = true
    @AppStorage("ai.endComments") private var endComments = true
    @AppStorage("ai.autoShowEnd") private var autoShowEnd = true
    @AppStorage("ai.strictSpoilers") private var strictSpoilers = true
    @AppStorage("ai.includeOCRText") private var includeOCRText = true
    @AppStorage("ai.allowsCellular") private var allowsCellular = true

    var body: some View {
        Form {
            Section {
                Toggle("启用 AI 陪读", isOn: $enabled)
                    .disabled(!companion.hasAPIKey)

                HStack {
                    Label(companion.hasAPIKey ? "DeepSeek 已连接" : "尚未配置密钥", systemImage: companion.hasAPIKey ? "checkmark.shield.fill" : "key.horizontal")
                    Spacer()
                    Circle()
                        .fill(companion.hasAPIKey ? .green : .orange)
                        .frame(width: 9, height: 9)
                }
            } footer: {
                Text("AI 功能需要你自己的 DeepSeek API 额度。模型不会收到 PDF 或原图，只会收到本机识别出的少量文字和画面标签。")
            }

            Section("DeepSeek 密钥") {
                Group {
                    if showKey {
                        TextField(companion.hasAPIKey ? "输入新密钥可替换" : "sk-…", text: $keyDraft)
                    } else {
                        SecureField(companion.hasAPIKey ? "输入新密钥可替换" : "sk-…", text: $keyDraft)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Toggle("显示输入内容", isOn: $showKey)

                Button("保存到钥匙串") {
                    do {
                        try companion.saveAPIKey(keyDraft)
                        keyDraft = ""
                    } catch {
                        companion.errorMessage = error.localizedDescription
                    }
                }
                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("测试连接") {
                    Task { await companion.testConnection() }
                }
                .disabled(!companion.hasAPIKey)

                if let message = companion.connectionMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                if let error = companion.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Link("打开 DeepSeek API 控制台", destination: URL(string: "https://platform.deepseek.com/api_keys")!)

                if companion.hasAPIKey {
                    Button("移除本机密钥", role: .destructive) {
                        showRemoveConfirmation = true
                    }
                }
            }

            Section("陪读方式") {
                Picker("模型", selection: $modelRaw) {
                    ForEach(AIModelChoice.allCases) { model in
                        VStack(alignment: .leading) {
                            Text(model.title)
                            Text(model.detail).font(.caption)
                        }
                        .tag(model.rawValue)
                    }
                }

                Picker("陪读性格", selection: $personaRaw) {
                    ForEach(AICompanionPersona.allCases) { persona in
                        Label(persona.title, systemImage: persona.systemImage).tag(persona.rawValue)
                    }
                }

                Picker("弹幕密度", selection: $densityRaw) {
                    ForEach(AIDanmakuDensity.allCases) { density in
                        Text(density.title).tag(density.rawValue)
                    }
                }

                Toggle("翻页后自动生成弹幕", isOn: $autoDanmaku)
                Toggle("读完后生成模拟评论", isOn: $endComments)
                Toggle("自动打开片尾评论", isOn: $autoShowEnd)
                    .disabled(!endComments)
                Toggle("严格防止后续剧透", isOn: $strictSpoilers)
            }

            Section("隐私与网络") {
                Toggle("允许发送识别到的文字", isOn: $includeOCRText)
                Toggle("允许使用蜂窝网络", isOn: $allowsCellular)

                Label {
                    Text("API 密钥只保存在 iPhone 钥匙串。图片与 PDF 原文件不会发送给 DeepSeek；页面文字由 Apple Vision 在本机识别。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(AppTheme.accent)
                }

                Button("清除 AI 评论与缓存", role: .destructive) {
                    Task { await companion.clearCachedContent() }
                }
            }
        }
        .navigationTitle("AI 陪读")
        .confirmationDialog("移除 DeepSeek 密钥？", isPresented: $showRemoveConfirmation) {
            Button("移除", role: .destructive) {
                do { try companion.removeAPIKey() }
                catch { companion.errorMessage = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        }
    }
}
