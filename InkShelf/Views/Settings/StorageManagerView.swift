import SwiftUI
import UIKit

struct StorageManagerView: View {
    @Environment(LibraryStore.self) private var library
    @State private var pendingAction: StorageAction?
    @State private var showsRedundantCleanupConfirmation = false

    var body: some View {
        List {
            Section {
                LabeledContent("本地总占用") {
                    Text(AppFormatters.fileSize(library.storageUsage))
                        .font(.headline.monospacedDigit())
                }
                if let available = library.availableStorageCapacity {
                    LabeledContent("设备当前可用") {
                        Text(AppFormatters.fileSize(available))
                            .font(.headline.monospacedDigit())
                    }
                }
                Text("高清页面按屏幕所需尺寸即时解码，缩略图和阅读页只在内存中短暂缓存，不会再生成一套磁盘页面缓存。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if library.redundantSourceCopiesSize > 0 {
                Section("可安全清理") {
                    Button {
                        showsRedundantCleanupConfirmation = true
                    } label: {
                        LabeledContent {
                            Text(AppFormatters.fileSize(library.redundantSourceCopiesSize))
                                .foregroundStyle(AppTheme.accent)
                        } label: {
                            Label("旧版压缩包副本", systemImage: "archivebox.fill")
                        }
                    }
                    .disabled(library.isReclaimingRedundantSources)

                    Text("这些旧版 CBZ/电子书已拥有完整可读内容。清理只移除应用内部重复保留的封装文件，不降低图片画质，也不删除“文件”或 iCloud 中的原文件。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("每本读物") {
                ForEach(library.books.sorted { library.storageSize(for: $0) > library.storageSize(for: $1) }) { book in
                    StorageBookRow(
                        book: book,
                        measuredSize: library.storageSize(for: book),
                        coverURL: library.coverURL(for: book),
                        isWorking: library.optimizingBookID == book.id,
                        progress: library.optimizingBookID == book.id ? library.storageOptimizationProgress : nil,
                        preview: { pendingAction = StorageAction(book: book, kind: .preview) },
                        coverOnly: { pendingAction = StorageAction(book: book, kind: .coverOnly) },
                        delete: { pendingAction = StorageAction(book: book, kind: .delete) }
                    )
                }
            }
        }
        .overlay {
            if library.books.isEmpty {
                ContentUnavailableView("还没有本地读物", systemImage: "externaldrive.fill")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AuroraBackground())
        .navigationTitle("本地存储管家")
        .task { await library.refreshStorageMeasurements() }
        .confirmationDialog(
            "清理旧版重复副本？",
            isPresented: $showsRedundantCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button("释放 \(AppFormatters.fileSize(library.redundantSourceCopiesSize))", role: .destructive) {
                Task { await library.reclaimRedundantSourceCopies() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("完整高清页面会继续保留；清理后应用内将不能导出原 CBZ/电子书封装，需要时请从原来的“文件”或 iCloud 位置取用。")
        }
        .confirmationDialog(
            pendingAction?.title ?? "整理本地空间",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(action.confirmTitle, role: .destructive) { perform(action) }
            Button("取消", role: .cancel) { pendingAction = nil }
        } message: { action in
            Text(action.message)
        }
        .alert(item: Binding(get: { library.alert }, set: { library.alert = $0 })) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("好")))
        }
    }

    private func perform(_ action: StorageAction) {
        pendingAction = nil
        switch action.kind {
        case .preview:
            Task { await library.optimizeStorage(bookID: action.book.id, mode: .previewOnly) }
        case .coverOnly:
            Task { await library.optimizeStorage(bookID: action.book.id, mode: .coverOnly) }
        case .delete:
            library.delete(action.book)
        }
    }
}

private struct StorageBookRow: View {
    let book: Book
    let measuredSize: Int64
    let coverURL: URL?
    let isWorking: Bool
    let progress: Double?
    let preview: () -> Void
    let coverOnly: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Group {
                if let coverURL {
                    CoverArtwork(book: book, coverURL: coverURL, previewURLs: [])
                } else {
                    Image(systemName: book.kind.systemImage)
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .frame(width: 48, height: 64)
            .background(AppTheme.cream.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(book.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Label(book.storageState.title, systemImage: storageSymbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(AppFormatters.fileSize(measuredSize))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 6)

            if isWorking {
                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.circular)
                        .accessibilityLabel("正在整理 \(book.title)")
                        .accessibilityValue("\(Int(progress * 100))%")
                } else {
                    ProgressView()
                }
            } else {
                Menu {
                    if book.kind != .ebook && book.storageState == .full {
                        Button(action: preview) {
                            Label("保留低清预览", systemImage: "photo.badge.arrow.down")
                        }
                    }
                    if book.storageState != .coverOnly {
                        Button(action: coverOnly) {
                            Label("仅保留封面", systemImage: "rectangle.portrait")
                        }
                    }
                    Button(role: .destructive, action: delete) {
                        Label("从书架彻底删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("管理 \(book.title) 的本地存储")
            }
        }
        .padding(.vertical, 4)
    }

    private var storageSymbol: String {
        switch book.storageState {
        case .full: "checkmark.circle.fill"
        case .previewOnly: "photo.on.rectangle.angled"
        case .coverOnly: "rectangle.portrait"
        }
    }
}

private struct StorageAction: Identifiable {
    enum Kind { case preview, coverOnly, delete }
    let id = UUID()
    let book: Book
    let kind: Kind

    var title: String {
        switch kind {
        case .preview: "把“\(book.title)”换成低清预览？"
        case .coverOnly: "“\(book.title)”只保留封面？"
        case .delete: "从书架彻底删除“\(book.title)”？"
        }
    }
    var confirmTitle: String {
        switch kind {
        case .preview: "删除原稿并生成预览"
        case .coverOnly: "删除内容，仅留封面"
        case .delete: "彻底删除"
        }
    }
    var message: String {
        switch kind {
        case .preview: "应用会先生成最长边约 1400 像素的完整预览，成功后才删除本机原稿。此操作不可撤销，恢复原画需要重新导入。"
        case .coverOnly: "阅读内容和原稿会从本机删除，书名、封面、进度与珍藏记录仍留在书架。恢复阅读需要重新导入。"
        case .delete: "封面、阅读进度、珍藏记录和本地内容都会删除，此操作不可撤销。"
        }
    }
}
