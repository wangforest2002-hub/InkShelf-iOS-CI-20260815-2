import SwiftUI
import UIKit

struct BookCard: View {
    let book: Book
    let coverURL: URL?
    let previewURLs: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                CoverArtwork(book: book, coverURL: coverURL, previewURLs: previewURLs)
                    .aspectRatio(0.70, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: AppTheme.wood.opacity(0.20), radius: 10, y: 7)
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.wood.opacity(0.72), AppTheme.honey.opacity(0.56)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 6)
                            .padding(.horizontal, 7)
                            .offset(y: 5)
                            .shadow(color: AppTheme.wood.opacity(0.18), radius: 4, y: 3)
                            .accessibilityHidden(true)
                    }

                if book.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.yellow)
                        .padding(8)
                        .inkGlass(cornerRadius: 14)
                        .padding(7)
                        .accessibilityLabel("已收藏")
                }

                Text(book.kind == .ebook ? "\(book.pageCount)章" : "\(book.pageCount)P")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.46), in: Capsule())
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 5) {
                    Text(book.kind.label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.accent)
                    Text("·")
                    Text(book.progressLabel)
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                ProgressView(value: book.progress)
                    .tint(book.progress > 0 ? AppTheme.coral : AppTheme.accent)
                    .scaleEffect(x: 1, y: 0.72, anchor: .center)
            }
        }
        .padding(9)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.thinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title)，\(book.kind.label)，\(book.progressLabel)")
        .hoverEffect(.lift)
    }
}

struct CoverArtwork: View {
    let book: Book
    let coverURL: URL?
    let previewURLs: [URL]

    var body: some View {
        Group {
            if previewURLs.count > 1, book.kind != .pdf {
                MosaicArtwork(urls: previewURLs)
            } else if let coverURL, let image = UIImage(contentsOfFile: coverURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                PlaceholderCover(book: book)
            }
        }
        .background(Color(.secondarySystemBackground))
    }
}

private struct PlaceholderCover: View {
    let book: Book

    var body: some View {
        ZStack {
            LinearGradient(
                colors: placeholderColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.11))
                .frame(width: 150)
                .blur(radius: 2)
                .offset(x: 45, y: -80)

            VStack(spacing: 16) {
                Image(systemName: book.kind.systemImage)
                    .font(.system(size: 46, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                Text(book.title)
                    .font(.headline)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color(red: 0.13, green: 0.16, blue: 0.30))
            .padding(18)
        }
    }

    private var placeholderColors: [Color] {
        switch book.kind {
        case .pdf: [Color(red: 0.78, green: 0.91, blue: 1), Color(red: 0.86, green: 0.81, blue: 1)]
        case .archive: [Color(red: 1, green: 0.84, blue: 0.82), Color(red: 0.88, green: 0.82, blue: 1)]
        case .imageCollection: [Color(red: 0.75, green: 0.96, blue: 0.89), Color(red: 0.76, green: 0.90, blue: 1)]
        case .ebook: [Color(red: 1.0, green: 0.91, blue: 0.72), Color(red: 0.78, green: 0.91, blue: 1.0)]
        }
    }
}

struct BookPreview: View {
    let book: Book
    let coverURL: URL?
    let previewURLs: [URL]

    var body: some View {
        VStack(spacing: 12) {
            CoverArtwork(book: book, coverURL: coverURL, previewURLs: previewURLs)
                .frame(width: 220, height: 314)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(book.title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(book.progressLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Label(book.kind.label, systemImage: book.kind.systemImage)
                Text(book.kind == .ebook ? "\(book.pageCount) 章" : "\(book.pageCount) 页")
                Text(AppFormatters.fileSize(book.fileSize))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(16)
    }
}

private struct MosaicArtwork: View {
    let urls: [URL]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let gap: CGFloat = 2
            let visible = Array(urls.prefix(4))

            ZStack(alignment: .topLeading) {
                ForEach(visible.indices, id: \.self) { index in
                    let url = visible[index]
                    if let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: frame(for: index, count: visible.count, size: size, gap: gap).width,
                                height: frame(for: index, count: visible.count, size: size, gap: gap).height
                            )
                            .clipped()
                            .offset(
                                x: frame(for: index, count: visible.count, size: size, gap: gap).minX,
                                y: frame(for: index, count: visible.count, size: size, gap: gap).minY
                            )
                    }
                }
            }
            .background(Color(.secondarySystemBackground))
        }
    }

    private func frame(for index: Int, count: Int, size: CGSize, gap: CGFloat) -> CGRect {
        if count == 2 {
            let width = (size.width - gap) / 2
            return CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: size.height)
        }

        if count == 3 {
            let halfWidth = (size.width - gap) / 2
            if index == 0 {
                return CGRect(x: 0, y: 0, width: halfWidth, height: size.height)
            }
            let halfHeight = (size.height - gap) / 2
            return CGRect(x: halfWidth + gap, y: CGFloat(index - 1) * (halfHeight + gap), width: halfWidth, height: halfHeight)
        }

        let width = (size.width - gap) / 2
        let height = (size.height - gap) / 2
        return CGRect(
            x: CGFloat(index % 2) * (width + gap),
            y: CGFloat(index / 2) * (height + gap),
            width: width,
            height: height
        )
    }
}
