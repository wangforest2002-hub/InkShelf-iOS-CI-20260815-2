import SwiftUI
import UIKit

struct DuplicateContentView: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage("duplicates.warnOnImport") private var warnOnDuplicateImport = true
    @State private var pendingDeletion: Book?

    var body: some View {
        List {
            Section {
                Toggle("导入时自动提醒", isOn: $warnOnDuplicateImport)
                Text("检测会核对实际文件内容，而不是只看名称。PDF 与电子书比较源文件；CBZ、压缩包和图片画集比较按顺序排列的页面，因此改名不会被误认为新画册。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await library.scanForDuplicateContent() }
                } label: {
                    Label(
                        library.duplicateScanCompletedAt == nil ? "开始扫描书架" : "重新扫描书架",
                        systemImage: "magnifyingglass.circle.fill"
                    )
                }
                .disabled(library.isScanningDuplicates)
                .accessibilityIdentifier("duplicate-scan-start")

                if library.isScanningDuplicates {
                    ProgressView(value: library.duplicateScanProgress ?? 0) {
                        Text("正在逐本核对内容…")
                    } currentValueLabel: {
                        Text("\(Int((library.duplicateScanProgress ?? 0) * 100))%")
                    }
                }
            }

            if let completedAt = library.duplicateScanCompletedAt, !library.isScanningDuplicates {
                if library.duplicateGroups.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "没有发现重复画册",
                            systemImage: "checkmark.seal.fill",
                            description: Text("截至 \(completedAt.formatted(date: .omitted, time: .shortened))，可读取内容均不重复。")
                        )
                    }
                } else {
                    Section {
                        Label(
                            "发现 \(library.duplicateGroups.count) 组完全一致的内容",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(AppTheme.honey)
                    }

                    ForEach(library.duplicateGroups) { group in
                        Section("完全一致 · \(group.books.count) 本") {
                            ForEach(group.books) { book in
                                DuplicateBookRow(
                                    book: book,
                                    coverURL: library.coverURL(for: book),
                                    delete: { pendingDeletion = book }
                                )
                            }
                        }
                    }
                }

                if library.duplicateScanUnavailableCount > 0 {
                    Section {
                        Label(
                            "有 \(library.duplicateScanUnavailableCount) 本仅剩封面且没有旧指纹，暂时无法核对；重新导入后即可参与检测。",
                            systemImage: "info.circle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("重复内容检测")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if library.duplicateScanCompletedAt == nil {
                await library.scanForDuplicateContent()
            }
        }
        .confirmationDialog(
            "删除这一本重复画册？",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { book in
            Button("删除“\(book.title)”", role: .destructive) {
                library.delete(book)
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: { book in
            Text("只删除你选中的这一份；同组中的其他副本不会受到影响。此操作不可撤销。")
        }
    }
}

private struct DuplicateBookRow: View {
    let book: Book
    let coverURL: URL?
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let coverURL {
                    CoverArtwork(book: book, coverURL: coverURL, previewURLs: [])
                } else {
                    Image(systemName: book.kind.systemImage)
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .frame(width: 44, height: 58)
            .background(AppTheme.cream.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text("\(book.pageCount) 页 · \(AppFormatters.fileSize(book.fileSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(book.importedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("删除重复副本 \(book.title)")
        }
        .padding(.vertical, 3)
    }
}
