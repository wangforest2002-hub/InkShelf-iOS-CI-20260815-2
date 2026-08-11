import ImageIO
import PDFKit
import SwiftUI
import UIKit

struct ThumbnailBrowser: View {
    @Environment(\.dismiss) private var dismiss
    let book: Book
    let pdfURL: URL?
    let imageURLs: [URL]
    let password: String
    let totalPageCount: Int
    @Binding var currentPage: Int
    @State private var pdfDocument: PDFDocument?

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(0..<pageCount, id: \.self) { index in
                            Button {
                                currentPage = index
                                dismiss()
                            } label: {
                                VStack(spacing: 7) {
                                    thumbnail(index: index)
                                        .aspectRatio(0.70, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(index == currentPage ? AppTheme.accent : .clear, lineWidth: 3)
                                        }
                                    Text("\(index + 1)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(index == currentPage ? AppTheme.accent : .secondary)
                                }
                            }
                            .buttonStyle(PressableCardStyle())
                            .id(index)
                        }
                    }
                    .padding(16)
                }
                .onAppear {
                    proxy.scrollTo(currentPage, anchor: .center)
                }
            }
            .navigationTitle("页面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task(id: "\(pdfURL?.path ?? "images")-\(password)") {
                guard let pdfURL, let document = PDFDocument(url: pdfURL) else { return }
                if document.isLocked, !password.isEmpty {
                    _ = document.unlock(withPassword: password)
                }
                pdfDocument = document.isLocked ? nil : document
            }
        }
    }

    private var pageCount: Int {
        pdfURL == nil ? imageURLs.count : max(totalPageCount, 1)
    }

    @ViewBuilder
    private func thumbnail(index: Int) -> some View {
        if pdfURL != nil, let pdfDocument {
            PDFPageThumbnail(document: pdfDocument, pageIndex: index)
        } else if pdfURL != nil {
            thumbnailPlaceholder
        } else if index < imageURLs.count {
            ImagePageThumbnail(url: imageURLs[index])
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }
}

private struct PDFPageThumbnail: View {
    let document: PDFDocument
    let pageIndex: Int
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
            }
        }
        .task(id: pageIndex) {
            guard let page = document.page(at: pageIndex) else { return }
            image = page.thumbnail(of: CGSize(width: 300, height: 430), for: .cropBox)
        }
    }
}

private struct ImagePageThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 360,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return }
            image = UIImage(cgImage: thumbnail)
        }
    }
}
