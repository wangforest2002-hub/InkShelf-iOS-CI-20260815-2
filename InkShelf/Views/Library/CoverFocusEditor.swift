import SwiftUI

struct CoverFocusEditor: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let book: Book
    @State private var focus: String
    init(book: Book) {
        self.book = book
        _focus = State(initialValue: book.coverFocus ?? "center")
    }
    private var preview: Book {
        var copy = book; copy.coverFocus = focus; return copy
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    BookCard(book: preview, coverURL: library.coverURL(for: book), previewURLs: library.previewURLs(for: book))
                        .frame(width: (book.coverAspectRatio ?? 0) >= 1.12 ? 320 : 220)
                    Text("选择封面重点显示的位置。只影响书架封面，阅读时仍显示完整画面。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Picker("封面位置", selection: $focus) {
                        Text("居中").tag("center")
                        Text("上方").tag("top")
                        Text("下方").tag("bottom")
                        Text("左侧").tag("leading")
                        Text("右侧").tag("trailing")
                    }.pickerStyle(.segmented)
                }.padding(24).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }.background(AuroraBackground()).navigationTitle("调整封面")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { library.setCoverFocus(focus, bookID: book.id); dismiss() }
                    }
                }
        }
    }
}
