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
                            imageURL: imageURL(for: item),
                            pdfURL: item.book.kind == .pdf ? library.contentURL(for: item.book) : nil
                        )
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityIdentifier("favorite-page-\(item.book.id.uuidString)-\(item.page)")
                }
            }
        }
    }

    private func imageURL(for item: FavoritePageItem) -> URL? {
        let pages = library.pageURLs(for: item.book)
        return pages.indices.contains(item.page) ? pages[item.page] : nil
    }
}

private struct FavoritePageCard: View {
    let item: FavoritePageItem
    let imageURL: URL?
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
        .inkGlass(cornerRadius: 20, interactive: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.book.title)，第 \(item.page + 1) 页")
        .task(id: item.id) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        if let imageURL {
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
