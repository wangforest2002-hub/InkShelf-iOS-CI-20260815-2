import SwiftUI
import UIKit

struct StorageManagerView: View {
    @Environment(LibraryStore.self) private var library
    @State private var pendingAction: StorageAction?

    var body: some View {
        List {
            Section {
                LabeledContent("本地总占用") {
                    Text(AppFormatters.fileSize(library.storageUsage))
                        .font(.headline.monospacedDigit())
                }
                Text("“低清预览”会保留完整页数并删除本机原稿；“仅保留封面”只留下书架记忆。以后想恢复原画，需要重新导入原文件。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                if let coverURL, let image = UIImage(contentsOfFile: coverURL.path) {
                    AdaptiveCoverImage(image: Image(uiImage: image))
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
