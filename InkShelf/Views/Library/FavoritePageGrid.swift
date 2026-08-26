import PDFKit
import SwiftUI
import UIKit

struct FavoritePageGrid: View {
    @Environment(LibraryStore.self) private var library
    let items: [FavoritePageItem]
    let onOpen: (FavoritePageItem) -> Void

    private let columns = [GridItem(.adaptive(minimum: 112, maximum: 160), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("收藏的画面", systemImage: "photo.stack.fill")
                    .font(.headline)
                Spacer()
                Text("\(items.count) 张")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    Button { onOpen(item) } label: {
                        FavoritePageCard(
                            item: item,
                            pdfURL: item.book.kind == .pdf ? library.contentURL(for: item.book) : nil
                        )
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityIdentifier("favorite-page-\(item.book.id.uuidString)-\(item.page)")
                }
            }
        }
    }

}

private struct FavoritePageCard: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.colorScheme) private var colorScheme
    let item: FavoritePageItem
    let pdfURL: URL?
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.cream.opacity(0.36))
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                } else {
                    ProgressView().tint(AppTheme.accent)
                }
            }
            .aspectRatio(0.72, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(item.book.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text("第 \(item.page + 1) 页")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            colorScheme == .dark
                ? Color(red: 0.105, green: 0.095, blue: 0.17).opacity(0.96)
                : Color.white.opacity(0.88),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.book.title)，第 \(item.page + 1) 页")
        .task(id: item.id) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        if item.book.kind == .archive || item.book.kind == .imageCollection {
            let pages = await library.loadPageURLs(for: item.book)
            guard !Task.isCancelled, pages.indices.contains(item.page) else { return }
            let imageURL = pages[item.page]
            image = await CoverImagePipeline.shared.image(for: imageURL, maxPixelSize: 640)
        } else if let pdfURL {
            image = await Task.detached(priority: .utility) {
                guard let document = PDFDocument(url: pdfURL),
                      let page = document.page(at: item.page)
                else { return nil }
                return page.thumbnail(of: CGSize(width: 520, height: 720), for: .mediaBox)
            }.value
        }
    }
}
