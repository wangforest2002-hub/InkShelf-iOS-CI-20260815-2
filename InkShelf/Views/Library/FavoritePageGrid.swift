import PDFKit
import SwiftUI
import UIKit

struct FavoritePageGrid: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let items: [FavoritePageItem]
    var showsHeading = true
    let onOpen: (FavoritePageItem) -> Void

    private var columns: [GridItem] {
        if horizontalSizeClass == .compact {
            return [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        }
        return [GridItem(.adaptive(minimum: 152, maximum: 230), spacing: 16)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if showsHeading {
                HStack {
                    Label("收藏的画面", systemImage: "photo.stack.fill")
                        .font(.headline)
                    Spacer()
                    Text("\(items.count) 张")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
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
    @State private var thumbnailLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? AppTheme.lilac.opacity(0.10) : AppTheme.cream)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                } else {
                    Image(systemName: thumbnailLoaded ? "photo" : "photo.on.rectangle.angled")
                        .font(.title2.weight(.light))
                        .foregroundStyle(AppTheme.accent.opacity(0.45))
                }
            }
            .aspectRatio(0.72, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Text("第 \(item.page + 1) 页")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.48), in: Capsule())
                    .padding(8)
                    .accessibilityHidden(true)
            }

            Text(item.book.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        }
        .padding(9)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            colorScheme == .dark
                ? Color(red: 0.105, green: 0.095, blue: 0.17).opacity(0.96)
                : Color.white.opacity(0.88),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [.white.opacity(0.16), .white.opacity(0.045)]
                            : [.white.opacity(0.90), AppTheme.wood.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.book.title)，第 \(item.page + 1) 页")
        .task(id: item.id) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        let loadedImage: UIImage?
        if item.book.kind == .archive || item.book.kind == .imageCollection {
            let pages = await library.loadPageURLs(for: item.book)
            guard !Task.isCancelled, pages.indices.contains(item.page) else { return }
            let imageURL = pages[item.page]
            loadedImage = await CoverImagePipeline.shared.image(for: imageURL, maxPixelSize: 640)
        } else if let pdfURL {
            let pageIndex = item.page
            loadedImage = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let document = PDFDocument(url: pdfURL),
                      let page = document.page(at: pageIndex)
                else { return nil }
                return page.thumbnail(of: CGSize(width: 520, height: 720), for: .mediaBox)
            }.value
        } else {
            loadedImage = nil
        }
        guard !Task.isCancelled else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            image = loadedImage
            thumbnailLoaded = true
        }
    }
}
