import SwiftUI

struct UpdateCenterView: View {
    @Environment(AppUpdateStore.self) private var updates
    @Environment(LibraryStore.self) private var library
    @Environment(\.openURL) private var openURL
    @State private var confirmingRelease: AppUpdateRelease?
    @State private var installFailure: String?

    var body: some View {
        Form {
            Section {
                UpdateStatusHero(
                    status: updates.statusText,
                    hasUpdate: updates.availableRelease != nil,
                    isChecking: updates.isChecking
                )
            }

            Section("当前安装") {
                LabeledContent("版本", value: AppIdentity.version)
                LabeledContent("构建", value: "\(AppIdentity.build)")
                LabeledContent("应用身份", value: AppIdentity.bundleIdentifier)
                    .font(.footnote)
            }

            if let release = updates.availableRelease {
                Section("可用更新") {
                    LabeledContent("版本", value: "\(release.version)（\(release.build)）")
                    LabeledContent("发布日期") {
                        Text(release.publishedAt, format: .dateTime.year().month().day())
                    }
                    if let size = release.packageSize {
                        LabeledContent("下载大小", value: AppFormatters.fileSize(size))
                    }
                    ForEach(release.notes, id: \.self) { note in
                        Label(note, systemImage: "sparkles")
                            .font(.subheadline)
                    }

                    Button {
                        confirmingRelease = release
                    } label: {
                        Label(
                            release.installURL == nil ? "等待签名发布" : "备份书架并在线更新",
                            systemImage: "arrow.down.app.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(release.installURL == nil)
                    .accessibilityIdentifier("update-install")
                }
            }

            Section("书库保护") {
                SafetyRow(symbol: "books.vertical.fill", text: "画册、PDF、电子书和页面缓存不会参与更新")
                SafetyRow(symbol: "externaldrive.fill", text: "安装前自动备份书架索引与分组")
                SafetyRow(symbol: "arrow.triangle.2.circlepath", text: "使用相同 Bundle ID 覆盖安装，不卸载旧版本")
                Text("更新期间请勿在系统桌面删除“二次元小家”。删除应用会同时删除它的本地数据容器。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task { await updates.checkForUpdates() }
                } label: {
                    HStack {
                        Label("检查更新", systemImage: "arrow.clockwise")
                        Spacer()
                        if updates.isChecking { ProgressView() }
                    }
                }
                .disabled(updates.isChecking)
                .accessibilityIdentifier("update-check")

                if let checked = updates.lastCheckedAt {
                    LabeledContent("上次检查") {
                        Text(checked, format: .dateTime.month().day().hour().minute())
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = updates.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AuroraBackground())
        .navigationTitle("应用更新")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !updates.didCheckThisLaunch {
                await updates.checkForUpdates()
            }
        }
        .confirmationDialog(
            "覆盖更新并保留书库？",
            isPresented: confirmationPresented,
            titleVisibility: .visible,
            presenting: confirmingRelease
        ) { release in
            Button("开始更新") { install(release) }
            Button("取消", role: .cancel) { confirmingRelease = nil }
        } message: { _ in
            Text("应用会先保存书架索引，再交给 iOS 覆盖安装。请不要删除当前应用。")
        }
        .alert("无法开始更新", isPresented: failurePresented) {
            Button("好", role: .cancel) { installFailure = nil }
        } message: {
            Text(installFailure ?? "请稍后再试。")
        }
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(
            get: { confirmingRelease != nil },
            set: { if !$0 { confirmingRelease = nil } }
        )
    }

    private var failurePresented: Binding<Bool> {
        Binding(
            get: { installFailure != nil },
            set: { if !$0 { installFailure = nil } }
        )
    }

    private func install(_ release: AppUpdateRelease) {
        confirmingRelease = nil
        guard release.supports(systemVersion: AppIdentity.systemVersion) else {
            installFailure = AppUpdateError.incompatibleSystem(release.minimumIOS).localizedDescription
            return
        }
        guard let installURL = release.installURL else {
            installFailure = AppUpdateError.releaseNotReady.localizedDescription
            return
        }
        do {
            try library.prepareForAppUpdate(targetVersion: release.version, targetBuild: release.build)
            openURL(installURL) { accepted in
                if !accepted { installFailure = "系统没有接受安装请求，请确认网络和证书仍然有效。" }
            }
        } catch {
            installFailure = "书架备份没有完成，已安全取消更新：\(error.localizedDescription)"
        }
    }
}

struct AppUpdatePromptView: View {
    @Environment(AppUpdateStore.self) private var updates
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let release: AppUpdateRelease
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "house.and.flag.fill")
                    .font(.system(size: 46))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(AppTheme.accent, AppTheme.honey)
                    .frame(width: 92, height: 92)
                    .inkGlass(cornerRadius: 30)

                VStack(spacing: 8) {
                    Text(release.title)
                        .font(.title2.bold())
                    Text("二次元小家 \(release.version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 11) {
                    ForEach(release.notes, id: \.self) { note in
                        Label(note, systemImage: "sparkles")
                    }
                    Label("书籍与缓存完整保留", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(AppTheme.mint)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .inkGlass(cornerRadius: 24)

                Spacer(minLength: 4)

                Button(action: install) {
                    Label("备份书架并在线更新", systemImage: "arrow.down.app.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if !release.mandatory {
                    Button("稍后再说") {
                        updates.dismissCurrentPrompt()
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(22)
            .background(AuroraBackground())
            .navigationTitle("家的新布置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(release.mandatory)
        .alert("无法开始更新", isPresented: failurePresented) {
            Button("好", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "请稍后再试。")
        }
    }

    private var failurePresented: Binding<Bool> {
        Binding(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }
        )
    }

    private func install() {
        guard release.supports(systemVersion: AppIdentity.systemVersion) else {
            failure = AppUpdateError.incompatibleSystem(release.minimumIOS).localizedDescription
            return
        }
        guard let installURL = release.installURL else {
            failure = AppUpdateError.releaseNotReady.localizedDescription
            return
        }
        do {
            try library.prepareForAppUpdate(targetVersion: release.version, targetBuild: release.build)
            openURL(installURL) { accepted in
                if !accepted { failure = "系统没有接受安装请求，请确认网络和证书仍然有效。" }
            }
        } catch {
            failure = "书架备份没有完成，已安全取消更新：\(error.localizedDescription)"
        }
    }
}

private struct UpdateStatusHero: View {
    let status: String
    let hasUpdate: Bool
    let isChecking: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: hasUpdate ? "arrow.down.app.fill" : "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(hasUpdate ? AppTheme.accent : AppTheme.mint)
                .frame(width: 54, height: 54)
                .background((hasUpdate ? AppTheme.accent : AppTheme.mint).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(hasUpdate ? "小家有新布置" : "应用更新")
                    .font(.headline)
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            if isChecking { ProgressView() }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct SafetyRow: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(.primary)
    }
}
