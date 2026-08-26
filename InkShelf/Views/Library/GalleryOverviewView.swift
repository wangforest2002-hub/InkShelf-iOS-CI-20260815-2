import QuickLook
import SwiftUI
import UIKit

struct GalleryOverviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    let book: Book
    @State private var imageURLs: [URL] = []
    @State private var didLoad = false
    @State private var previewSelection: ImagePreviewSelection?

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if !didLoad {
                    ProgressView("正在整理预览…")
                        .frame(maxWidth: .infinity, minHeight: 320)
                } else if imageURLs.isEmpty {
                    ContentUnavailableView(
                        "没有可预览的图片",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text("画册页面可能已经损坏，请重新导入原文件。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(imageURLs.indices, id: \.self) { index in
                            Button {
                                previewSelection = ImagePreviewSelection(index: index)
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    ImageFileThumbnail(url: imageURLs[index], maxPixelSize: 520)
                                        .aspectRatio(0.72, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    Text("\(index + 1)")
                                        .font(.caption2.monospacedDigit().weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(.black.opacity(0.52), in: Capsule())
                                        .padding(6)
                                }
                            }
                            .buttonStyle(PressableCardStyle())
                            .accessibilityLabel("预览第 \(index + 1) 页")
                        }
                    }
                }
            }
            .contentMargins(12, for: .scrollContent)
            .background(AuroraBackground())
            .navigationTitle(book.title)
            .adaptiveNavigationSubtitle("\(imageURLs.count) 张图片 · 点击可全屏预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .sheet(item: $previewSelection) { selection in
            ImageQuickLookSheet(urls: imageURLs, initialIndex: selection.index)
        }
        .task(id: book.id) {
            imageURLs = await library.loadPageURLs(for: book)
            guard !Task.isCancelled else { return }
            didLoad = true
        }
    }
}

struct ImageFileThumbnail: View {
    let url: URL
    var maxPixelSize = 420
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
                    .tint(AppTheme.accent)
            }
        }
        .clipped()
        .task(id: "\(url.path)-\(maxPixelSize)") {
            image = await CoverImagePipeline.shared.image(for: url, maxPixelSize: maxPixelSize)
        }
    }
}

private struct ImagePreviewSelection: Identifiable {
    let id = UUID()
    let index: Int
}

private struct ImageQuickLookSheet: View {
    @Environment(\.dismiss) private var dismiss
    let urls: [URL]
    let initialIndex: Int

    var body: some View {
        NavigationStack {
            QuickLookPreviewController(urls: urls, initialIndex: initialIndex)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("图片预览")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
        }
    }
}

private struct QuickLookPreviewController: UIViewControllerRepresentable {
    let urls: [URL]
    let initialIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(urls: urls)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.currentPreviewItemIndex = min(max(0, initialIndex), max(0, urls.count - 1))
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.urls = urls
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var urls: [URL]

        init(urls: [URL]) {
            self.urls = urls
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            urls.count
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            urls[index] as NSURL
        }
    }
}
