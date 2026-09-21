import PDFKit
import SwiftUI
import UIKit

struct ThumbnailBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let book: Book
    let pdfURL: URL?
    let imageURLs: [URL]
    let password: String
    let totalPageCount: Int
    @Binding var currentPage: Int
    @State private var pdfRenderer: PDFThumbnailRenderer?

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(0..<pageCount, id: \.self) { index in
                            Button {
                                currentPage = index
                                dismiss()
                            } label: {
                                VStack(spacing: 8) {
                                    thumbnail(index: index)
                                        .aspectRatio(0.70, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                .strokeBorder(index == currentPage ? AppTheme.accent : Color.primary.opacity(0.08), lineWidth: index == currentPage ? 3 : 1)
                                        }
                                        .overlay(alignment: .topTrailing) {
                                            if index == currentPage {
                                                Image(systemName: "bookmark.fill")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(.white)
                                                    .padding(8)
                                                    .background(AppTheme.accent, in: Circle())
                                                    .padding(7)
                                            }
                                        }
                                    Text(index == currentPage ? "正在读 · \(index + 1)" : "\(index + 1)")
                                        .font(.caption.monospacedDigit().weight(index == currentPage ? .bold : .medium))
                                        .foregroundStyle(index == currentPage ? AppTheme.accent : .secondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(PressableCardStyle())
                            .accessibilityLabel("第 \(index + 1) 页")
                            .accessibilityValue(index == currentPage ? "当前阅读页" : "")
                            .accessibilityHint("打开此页并返回阅读")
                            .accessibilityAddTraits(index == currentPage ? [.isSelected] : [])
                            .id(index)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 1_080)
                    .frame(maxWidth: .infinity)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("共 \(pageCount) 页 · 轻点画面前往")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button {
                            withAnimation(reduceMotion ? nil : AppMotion.panel) {
                                proxy.scrollTo(currentPage, anchor: .center)
                            }
                        } label: {
                            Label("当前页", systemImage: "bookmark.fill")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(PressableCardStyle())
                        .background(AppTheme.accent.opacity(0.10), in: Capsule())
                        .accessibilityLabel("回到当前阅读的第 \(currentPage + 1) 页")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                }
                .onAppear {
                    proxy.scrollTo(currentPage, anchor: .center)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("页面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task(id: "\(pdfURL?.path ?? "images")-\(password)") {
                pdfRenderer = pdfURL.map { PDFThumbnailRenderer(url: $0, password: password) }
            }
        }
    }

    private var pageCount: Int {
        pdfURL == nil ? imageURLs.count : max(totalPageCount, 1)
    }

    @ViewBuilder
    private func thumbnail(index: Int) -> some View {
        if pdfURL != nil, let pdfRenderer {
            PDFPageThumbnail(renderer: pdfRenderer, pageIndex: index)
        } else if pdfURL != nil {
            PageThumbnailSurface(image: nil, didFinishLoading: false)
        } else if imageURLs.indices.contains(index) {
            ImagePageThumbnail(url: imageURLs[index])
        } else {
            PageThumbnailSurface(image: nil, didFinishLoading: true)
        }
    }
}

private struct PageThumbnailSurface: View {
    let image: UIImage?
    let didFinishLoading: Bool

    var body: some View {
        ZStack {
            Color(.secondarySystemGroupedBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if didFinishLoading {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(AppTheme.accent)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct PDFPageThumbnail: View {
    let renderer: PDFThumbnailRenderer
    let pageIndex: Int
    @State private var image: UIImage?
    @State private var didFinishLoading = false

    var body: some View {
        PageThumbnailSurface(image: image, didFinishLoading: didFinishLoading)
            .task(id: "\(renderer.id)-\(pageIndex)") {
                image = nil
                didFinishLoading = false
                let loaded = await renderer.image(for: pageIndex)
                guard !Task.isCancelled else { return }
                image = loaded
                didFinishLoading = true
            }
    }
}

private struct ImagePageThumbnail: View {
    let url: URL
    @State private var image: UIImage?
    @State private var didFinishLoading = false

    var body: some View {
        PageThumbnailSurface(image: image, didFinishLoading: didFinishLoading)
            .task(id: url) {
                image = nil
                didFinishLoading = false
                // A page overview must not evict the reader's small working
                // set of full-size pages while the user browses thumbnails.
                let loaded = await CoverImagePipeline.shared.image(for: url, maxPixelSize: 512)
                guard !Task.isCancelled else { return }
                image = loaded
                didFinishLoading = true
            }
    }
}

/// Owns a separate document used only on this serial queue. PDF thumbnail
/// generation never touches the live reader's document or the main thread.
private final class PDFThumbnailRenderer: @unchecked Sendable {
    let id = UUID()
    private let url: URL
    private let password: String
    private let queue = DispatchQueue(label: "com.inkshelf.pdf-thumbnail", qos: .userInitiated)
    private var document: PDFDocument?
    private var didOpenDocument = false
    private let cache = NSCache<NSNumber, UIImage>()

    init(url: URL, password: String) {
        self.url = url
        self.password = password
        cache.countLimit = 40
        cache.totalCostLimit = 20 * 1_024 * 1_024
    }

    func image(for pageIndex: Int) async -> UIImage? {
        let request = PDFThumbnailRequest()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async { [self] in
                    guard !request.isCancelled else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let image: UIImage? = autoreleasepool {
                        if let cached = cache.object(forKey: NSNumber(value: pageIndex)) {
                            return cached
                        }
                        if !didOpenDocument {
                            didOpenDocument = true
                            let opened = PDFDocument(url: url)
                            if let opened, opened.isLocked, !password.isEmpty {
                                _ = opened.unlock(withPassword: password)
                            }
                            document = opened?.isLocked == false ? opened : nil
                        }
                        guard !request.isCancelled,
                              let page = document?.page(at: pageIndex)
                        else { return nil }
                        let rendered = page.thumbnail(of: CGSize(width: 300, height: 430), for: .cropBox)
                        if let cgImage = rendered.cgImage {
                            cache.setObject(rendered, forKey: NSNumber(value: pageIndex), cost: cgImage.bytesPerRow * cgImage.height)
                        }
                        return rendered
                    }
                    continuation.resume(returning: request.isCancelled ? nil : image)
                }
            }
        } onCancel: {
            request.cancel()
        }
    }
}

private final class PDFThumbnailRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
