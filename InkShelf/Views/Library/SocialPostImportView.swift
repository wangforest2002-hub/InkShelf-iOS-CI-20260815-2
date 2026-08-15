import SwiftUI
import UIKit

struct SocialPostImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    let shelfGroupID: UUID?
    let favoriteOnImport: Bool
    var initialURL = ""

    @State private var link = ""
    @State private var preview: SocialPostPreview?
    @State private var selectedImageIDs: Set<String> = []
    @State private var isResolving = false
    @State private var isDownloading = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 118, maximum: 190), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    introCard
                    linkCard

                    if let preview {
                        postHeader(preview)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(preview.images) { image in
                                imageTile(image)
                            }
                        }
                        Button(action: importSelection) {
                            HStack {
                                if isDownloading { ProgressView().tint(.white) }
                                Label(
                                    isDownloading ? "正在下载原图…" : "导入选中的 \(selectedImageIDs.count) 张原图",
                                    systemImage: "square.and.arrow.down.fill"
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .adaptiveProminentButton()
                        .disabled(selectedImageIDs.isEmpty || isDownloading)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(18)
            }
            .background(AuroraBackground())
            .navigationTitle("从 X 收藏图片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                guard link.isEmpty else { return }
                link = initialURL
                if !initialURL.isEmpty { resolve() }
            }
        }
    }

    private var introCard: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "heart.text.square.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.coral)
            VStack(alignment: .leading, spacing: 5) {
                Text("把喜欢的画面带回家")
                    .font(.headline)
                Text("粘贴公开帖子链接，预览后按原图尺寸导入。仅保存你选中的图片，不保存账号登录信息。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .inkGlass(cornerRadius: 20)
    }

    private var linkCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("https://x.com/…/status/…", text: $link)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .padding(13)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15))

            HStack {
                Button {
                    if let value = UIPasteboard.general.string { link = value }
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: resolve) {
                    HStack {
                        if isResolving { ProgressView() }
                        Text(isResolving ? "读取中" : "预览帖子")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResolving)
            }
        }
        .padding(16)
        .inkGlass(cornerRadius: 20)
    }

    private func postHeader(_ post: SocialPostPreview) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(post.authorName)
                .font(.headline)
            Text("@\(post.username) · \(post.images.count) 张图片")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !post.text.isEmpty {
                Text(post.text)
                    .font(.subheadline)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func imageTile(_ item: SocialPostImage) -> some View {
        let selected = selectedImageIDs.contains(item.id)
        return Button {
            if !selectedImageIDs.insert(item.id).inserted { selectedImageIDs.remove(item.id) }
        } label: {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: item.previewURL, transaction: Transaction(animation: .smooth)) { phase in
                    if case .success(let image) = phase {
                        AdaptiveCoverImage(image: image)
                    } else {
                        ZStack {
                            AppTheme.cream.opacity(0.35)
                            ProgressView().tint(AppTheme.accent)
                        }
                    }
                }
                .aspectRatio(0.82, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, selected ? AppTheme.accent : .black.opacity(0.42))
                    .padding(7)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? AppTheme.accent : .clear, lineWidth: 3)
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("第 \(item.id) 张图片，\(selected ? "已选择" : "未选择")")
    }

    private func resolve() {
        isResolving = true
        preview = nil
        selectedImageIDs = []
        errorMessage = nil
        Task {
            do {
                let result = try await SocialPostImportService.shared.resolve(link)
                preview = result
                selectedImageIDs = Set(result.images.map(\.id))
            } catch {
                errorMessage = error.localizedDescription
            }
            isResolving = false
        }
    }

    private func importSelection() {
        guard let preview else { return }
        isDownloading = true
        errorMessage = nil
        Task {
            do {
                let downloaded = try await SocialPostImportService.shared.download(
                    preview: preview,
                    imageIDs: selectedImageIDs
                )
                library.importFiles(
                    [downloaded.galleryFolder],
                    cleanupDirectory: downloaded.temporaryRoot,
                    shelfGroupID: shelfGroupID,
                    favoriteOnImport: favoriteOnImport
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isDownloading = false
            }
        }
    }
}
