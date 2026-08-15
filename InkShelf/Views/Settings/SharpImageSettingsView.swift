import SwiftUI

struct SharpImageSettingsView: View {
    @AppStorage("sharp.bridgeAddress") private var bridgeAddress = ""
    @State private var isChecking = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var localStatus = "正在检查内置模型…"
    @State private var localStatusIsError = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Sharp 锐化", systemImage: "wand.and.stars.inverse")
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.coral)
                    Text("动漫模型先放大 4 倍，再用 Lanczos 高质量缩回 2 倍，输出无损 PNG。应用会核验模型、Profile 和倍率，不接受替代方案。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("设备本地处理") {
                Label(localStatus, systemImage: localStatusIsError ? "exclamationmark.triangle.fill" : "iphone.gen3.radiowaves.left.and.right")
                    .foregroundStyle(localStatusIsError ? .orange : AppTheme.mint)
                Text("默认直接使用 iPhone 或 iPad 的 Core ML 与 Metal 分块处理。原图不会上传，处理时可继续留在应用内，完成后会自动进入珍藏。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("备用电脑桥（可选）") {
                TextField("http://192.168.1.8:8765", text: $bridgeAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                Button {
                    checkConnection()
                } label: {
                    HStack {
                        if isChecking { ProgressView() }
                        Label(isChecking ? "正在检查…" : "测试 Sharp 电脑桥", systemImage: "network")
                    }
                }
                .disabled(bridgeAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isChecking)

                if let statusMessage {
                    Label(statusMessage, systemImage: statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(statusIsError ? .red : AppTheme.mint)
                }
            }

            Section("超大图片备用方案") {
                Text("只有图片大到设备内存无法承受时，才会自动尝试这里填写的电脑桥。运行项目 scripts 文件夹中的 Start-InkShelfSharpBridge.ps1，窗口会显示局域网地址。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                LabeledContent("模型", value: "realesrgan-x4plus-anime")
                LabeledContent("Profile", value: "sharp")
                LabeledContent("最终输出", value: "2x · PNG")
            }

            Section {
                Label("内置模型和电脑桥都只接受 realesrgan-x4plus-anime → 4x → Lanczos 2x → PNG。服务器不会用普通增强或 animevideov3 冒充。", systemImage: "checkmark.shield.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AuroraBackground())
        .navigationTitle("图片清晰化")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let status = try await OnDeviceSharpProcessor.shared.status()
                localStatus = "已就绪 · \(status.model) · \(status.finalScale)x PNG"
                localStatusIsError = false
            } catch {
                localStatus = error.localizedDescription
                localStatusIsError = true
            }
        }
    }

    private func checkConnection() {
        isChecking = true
        statusMessage = nil
        Task {
            do {
                let status = try await SharpImageService.shared.check(address: bridgeAddress)
                statusMessage = "已连接 · \(status.model) · \(status.finalScale)x PNG"
                statusIsError = false
            } catch {
                statusMessage = error.localizedDescription
                statusIsError = true
            }
            isChecking = false
        }
    }
}
