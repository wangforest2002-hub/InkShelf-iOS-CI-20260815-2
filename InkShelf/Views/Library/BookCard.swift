import SwiftUI
import UIKit

struct BookCard: View {
    let book: Book
    let coverURL: URL?
    let previewURLs: [URL]
    let knownCoverAspectRatio: CGFloat?
    let onCoverAspectRatio: ((CGFloat) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @State private var detectedCoverAspectRatio: CGFloat?

    init(
        book: Book,
        coverURL: URL?,
        previewURLs: [URL],
        knownCoverAspectRatio: CGFloat? = nil,
        onCoverAspectRatio: ((CGFloat) -> Void)? = nil
    ) {
        self.book = book
        self.coverURL = coverURL
        self.previewURLs = previewURLs
        self.knownCoverAspectRatio = knownCoverAspectRatio
        self.onCoverAspectRatio = onCoverAspectRatio
        _detectedCoverAspectRatio = State(initialValue: nil)
    }

    private var sourceAspectRatio: CGFloat? {
        let ratio = knownCoverAspectRatio
            ?? detectedCoverAspectRatio
            ?? book.coverAspectRatio.map { CGFloat($0) }
        guard let ratio, ratio.isFinite, ratio >= 0.2, ratio <= 5 else { return nil }
        return ratio
    }

    private var isLandscapeCover: Bool {
        (sourceAspectRatio ?? 0) >= ShelfCoverLayout.landscapeThreshold
    }

    private var displayedCoverAspectRatio: CGFloat {
        guard isLandscapeCover, let sourceAspectRatio else { return 0.70 }
        return min(max(sourceAspectRatio, 1.32), 1.82)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                CoverArtwork(
                    book: book,
                    coverURL: coverURL,
                    previewURLs: previewURLs,
                    onAspectRatio: rememberCoverAspectRatio
                )
                    .aspectRatio(displayedCoverAspectRatio, contentMode: .fit)
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
                        .background(.black.opacity(0.42), in: Circle())
                        .overlay { Circle().stroke(.white.opacity(0.18), lineWidth: 0.7) }
                        .padding(7)
                        .accessibilityLabel("已收藏")
                }

                if book.belongsToAfterDark {
                    Label(book.mood?.shortTitle ?? "成年向", systemImage: book.mood?.systemImage ?? "18.circle.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(red: 0.28, green: 0.07, blue: 0.14))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(AppTheme.peach.opacity(0.94), in: Capsule())
                        .padding(7)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .accessibilityLabel("已加入成年向档案")
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

                if book.normalizedHeartRating > 0 || book.normalizedSpiceRating > 0 {
                    HStack(spacing: 8) {
                        if book.normalizedHeartRating > 0 {
                            Label("\(book.normalizedHeartRating)", systemImage: "heart.fill")
                                .foregroundStyle(AppTheme.coral)
                        }
                        if book.normalizedSpiceRating > 0 {
                            Label("\(book.normalizedSpiceRating)", systemImage: "flame.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption2.bold())
                }
            }
        }
        .padding(9)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? Color(red: 0.105, green: 0.095, blue: 0.17).opacity(0.96)
                        : Color.white.opacity(0.88)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("book-\(book.id.uuidString.lowercased())")
        .accessibilityLabel("\(book.title)，\(book.kind.label)，\(book.progressLabel)")
        .accessibilityValue(isLandscapeCover ? "横版封面" : "竖版封面")
        .hoverEffect(.lift)
    }

    private func rememberCoverAspectRatio(_ ratio: CGFloat) {
        guard ratio.isFinite, ratio >= 0.2, ratio <= 5 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            detectedCoverAspectRatio = ratio
            onCoverAspectRatio?(ratio)
        }
    }
}

struct CoverArtwork: View {
    let book: Book
    let coverURL: URL?
    let previewURLs: [URL]
    let onAspectRatio: ((CGFloat) -> Void)?
    @State private var decodedImage: UIImage?

    init(
        book: Book,
        coverURL: URL?,
        previewURLs: [URL],
        onAspectRatio: ((CGFloat) -> Void)? = nil
    ) {
        self.book = book
        self.coverURL = coverURL
        self.previewURLs = previewURLs
        self.onAspectRatio = onAspectRatio
    }

    private var sourceURL: URL? { coverURL ?? previewURLs.first }

    var body: some View {
        Group {
            if let decodedImage {
                AdaptiveCoverImage(image: Image(uiImage: decodedImage))
            } else {
                PlaceholderCover(book: book)
            }
        }
        .background(Color(.secondarySystemBackground))
        .task(id: sourceURL?.standardizedFileURL.path) {
            decodedImage = nil
            guard let sourceURL else { return }
            let image = await CoverImagePipeline.shared.image(for: sourceURL)
            guard !Task.isCancelled else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                decodedImage = image
                if let image, image.size.height > 0 {
                    onAspectRatio?(image.size.width / image.size.height)
                }
            }
        }
    }
}

enum ShelfCoverLayout {
    static let landscapeThreshold: CGFloat = 1.12

    static func isLandscape(_ ratio: CGFloat?) -> Bool {
        guard let ratio, ratio.isFinite else { return false }
        return ratio >= landscapeThreshold
    }
}

/// Keeps every cover's original composition inside the shelf's portrait card.
/// Landscape and unusually narrow artwork is letterboxed over a soft extension
/// of itself, so it never gets stretched or aggressively cropped.
struct AdaptiveCoverImage: View {
    let image: Image
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(red: 0.13, green: 0.12, blue: 0.22), Color(red: 0.08, green: 0.10, blue: 0.16)]
                        : [AppTheme.cream, AppTheme.lilac.opacity(0.24), AppTheme.cyan.opacity(0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .shadow(color: .black.opacity(0.10), radius: 4, y: 1)
            }
        }
        .clipped()
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
