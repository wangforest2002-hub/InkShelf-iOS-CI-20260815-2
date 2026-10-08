import SwiftUI
import UIKit

struct TranslationPageInput: Identifiable {
    let page: Int
    let source: AIPageSource
    var id: Int { page }
}

struct PageTranslationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let book: Book
    let pages: [TranslationPageInput]
    @State private var store = PageTranslationStore()
    @State private var selectedPage: Int
    @State private var mode: TranslationDisplayMode = .comparison
    @State private var isSelecting = false
    @State private var manualSelection = false
    @State private var editing: TranslationRegion?
    @State private var paragraphEditing: TranslationRegion?
    @State private var showingSettings = false
    @State private var showingParagraph = false
    @State private var showingFullPage = false
    @State private var showingFullPageParagraph = false
    @State private var previewOriginal = false
    @State private var exportURL: URL?
    @State private var exporting = false
    @State private var exportGeneration = UUID()

    init(book: Book, pages: [TranslationPageInput]) {
        self.book = book; self.pages = pages
        _selectedPage = State(initialValue: pages.first?.page ?? 0)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let wide = proxy.size.width >= 850
                VStack(spacing: 0) {
                    controls
                    if let image = store.image {
                        TranslationCanvas(image: image, regions: store.regions,
                                          mode: previewOriginal || isSelecting ? .original : mode,
                                          selectedID: store.selectedID, isSelecting: isSelecting,
                                          onSelect: { id in
                            store.select(id); showingParagraph = true
                        }, onRegion: { box in
                            isSelecting = false
                            if manualSelection {
                                store.addManual(box: box); mode = .comparison
                                editing = store.selectedRegion
                            } else { store.recognize(selection: box) }
                        })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView("日文图片翻译", systemImage: "character.bubble",
                                               description: Text(store.status))
                            .frame(maxHeight: .infinity)
                    }
                    statusBar
                    if !store.regions.isEmpty && !previewOriginal && !isSelecting {
                        VStack(spacing: 0) {
                            HStack {
                                Label(mode == .original ? "本页原文" : "本页完整译文", systemImage: "text.alignleft")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Button("展开") { showingFullPage = true }
                                    .accessibilityIdentifier("translation-full-page")
                            }.padding(.horizontal, 16).padding(.vertical, 10)
                            Divider()
                            regionList()
                        }
                        .frame(height: min(wide ? 340 : 300, max(170, proxy.size.height * 0.40)))
                    }

                }
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("图片翻译")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回阅读") { store.cancel(); dismiss() }
                        .accessibilityIdentifier("translation-close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("翻译与陪读设置", systemImage: "gearshape") { store.cancel(); showingSettings = true }
                        Button("框选并手动添加", systemImage: "pencil.and.outline") {
                            manualSelection = true; isSelecting = true
                        }.disabled(store.image == nil || store.isBusy)
                        Button("导出原图与段落译文", systemImage: "square.and.arrow.up") { exportPreview() }
                            .disabled(store.completedCount == 0 || exporting || store.isBusy)
                        if let exportURL { ShareLink("分享原图与完整译文", items: [exportURL, exportURL.deletingPathExtension().appendingPathExtension("txt")]) }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .task(id: selectedPage) {
                isSelecting = false; showingParagraph = false; showingFullPage = false; editing = nil; exportURL = nil; exporting = false; exportGeneration = UUID()
                guard let input = pages.first(where: { $0.page == selectedPage }) else { return }
                store.open(source: input.source, page: input.page, bookID: book.id)
            }
        }
        .onDisappear { store.cancel() }
        .sheet(isPresented: $showingParagraph) {
            paragraphSheet { showingParagraph = false }
        }
        .sheet(isPresented: $showingFullPage) {
            NavigationStack {
                regionList(expanded: true).navigationTitle("本页完整译文")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingFullPage = false } } }
            }
            .sheet(isPresented: $showingFullPageParagraph) {
                paragraphSheet { showingFullPageParagraph = false }
            }
            .presentationDetents([.large])
        }
        .sheet(item: $editing) { region in
            TranslationEditor(region: region) { source, translated in
                store.edit(id: region.id, source: source, translated: translated)
            }
        }
        .sheet(isPresented: $showingSettings) { NavigationStack { TranslationSettingsView() } }
    }

    private func paragraphSheet(close: @escaping () -> Void) -> some View {
            NavigationStack {
                ScrollView {
                    if let region = store.selectedRegion {
                        paragraphDetail(region).padding(20)
                    }
                }
                .navigationTitle("这段的翻译")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { close() }
                } }
                .safeAreaInset(edge: .bottom) {
                    if let error = store.error { Text(error).font(.footnote).foregroundStyle(.orange).padding() }
                    if store.isBusy { ProgressView("正在翻译这段…").padding() }
                }
                .sheet(item: $paragraphEditing) { region in
                    TranslationEditor(region: region) { source, translated in
                        store.edit(id: region.id, source: source, translated: translated)
                    }
                }
            }.presentationDetents([.medium, .large])
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                if pages.count > 1 {
                    Picker("当前跨页", selection: $selectedPage) {
                        ForEach(pages) { page in Text("第 \(page.page + 1) 页").tag(page.page) }
                    }.pickerStyle(.segmented).frame(maxWidth: 280)
                } else {
                    Text("第 \(selectedPage + 1) 页 · 日语 → 简体中文").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button { previewOriginal.toggle() } label: {
                    Label(previewOriginal ? "返回译文" : "看原图", systemImage: "eye")
                }.font(.caption).buttonStyle(.bordered)
            }
            Picker("显示方式", selection: $mode) {
                ForEach(TranslationDisplayMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("translation-mode")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button("识别本页", systemImage: "viewfinder") { store.recognize() }
                        .disabled(store.image == nil || store.isBusy || !store.regions.isEmpty)
                        .accessibilityIdentifier("translation-recognize")
                    Button(isSelecting ? "取消框选" : "框选识别", systemImage: "crop") {
                        manualSelection = false; isSelecting.toggle()
                    }.disabled(store.image == nil || store.isBusy)
                    Button("翻译本页", systemImage: "character.bubble.fill") { store.translate() }
                        .disabled(store.regions.isEmpty || store.isBusy || store.pendingCount == 0)
                        .accessibilityIdentifier("translation-start")
                    if store.isBusy { Button("暂停", systemImage: "pause.fill") { store.cancel() } }
                }.buttonStyle(.bordered).font(.subheadline)
            }
            if isSelecting {
                Text(manualSelection ? "在原图上拖出文字范围，随后填写原文或中文" : "在原图上拖出范围；想看得更清楚，可先取消框选并双指放大")
                    .font(.caption).foregroundStyle(AppTheme.accent)
            }
        }.padding(12).background(.regularMaterial)
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if store.isBusy { ProgressView().controlSize(.small) }
                Text(store.status).font(.caption)
                Spacer(minLength: 0)
            }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.orange) }
            if let exportURL {
                ShareLink("分享原图与完整译文", items: [exportURL, exportURL.deletingPathExtension().appendingPathExtension("txt")]).font(.caption)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func regionList(expanded: Bool = false) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text(mode == .original ? "点原图中的段落，查看对应译文" : "点原图段落查看译文；这里可连续阅读全页")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(store.regions.enumerated()), id: \.element.id) { index, region in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("段落 \(index + 1)").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                                Spacer()
                                if region.needsRetranslation == true {
                                    Text("已合并 · 建议重译").font(.caption2).foregroundStyle(.orange)
                                } else if !region.isEdited && region.confidence < 0.65 {
                                    Text("请核对原文").font(.caption2).foregroundStyle(.orange)
                                }
                            }
                            if mode != .chinese {
                                Text(region.source.isEmpty ? "尚未填写原文" : region.source)
                                    .font(mode == .original ? .body : .subheadline)
                                    .foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            if mode != .original || expanded {
                                Text(region.translated.isEmpty ? "尚未翻译 · 点此段翻译" : region.translated)
                                    .font(.body).lineSpacing(5).textSelection(.enabled)
                                    .accessibilityIdentifier("translation-text-\(region.id)")
                            }
                            Button("查看这段") {
                                store.select(region.id)
                                if expanded { showingFullPageParagraph = true } else { showingParagraph = true }
                            }
                                .font(.caption).accessibilityIdentifier("translation-detail-\(region.id)")
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).stroke(region.id == store.selectedID ? AppTheme.accent : .clear, lineWidth: 2) }
                        .id(region.id)
                    }
                }.padding(14)
            }
            .accessibilityIdentifier("translation-page-text")
            .onChange(of: store.selectedID) { _, id in
                if let id { withAnimation(reduceMotion ? nil : AppMotion.value) { proxy.scrollTo(id, anchor: .center) } }
            }
        }.background(Color(.systemGroupedBackground))
    }

    private func paragraphDetail(_ region: TranslationRegion) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("日文原文", systemImage: "text.bubble").font(.caption).foregroundStyle(.secondary)
            Text(region.source.isEmpty ? "尚未填写原文" : region.source)
                .font(.body).textSelection(.enabled)
            Divider()
            Label("中文译文", systemImage: "character.bubble.fill").font(.caption).foregroundStyle(AppTheme.accent)
            Text(region.translated.isEmpty ? "尚未翻译，点下方按钮翻译这一段。" : region.translated)
                .font(.title3).lineSpacing(6).textSelection(.enabled)
                .accessibilityIdentifier("translation-selected-text")
            if region.needsRetranslation == true {
                Text("这段由多行合并，旧译文已保留。建议重译，让句意更连贯。")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if !region.isEdited && region.confidence < 0.65 {
                Text("这段识别置信度较低，请先核对日文，避免漏字影响翻译。")
                    .font(.footnote).foregroundStyle(.orange)
            }
            HStack {
                Button(region.translated.isEmpty ? "翻译这段" : "重新翻译", systemImage: "character.bubble") {
                    store.translate(selectedOnly: true)
                }.disabled(region.source.isEmpty || store.isBusy)
                Button("校对", systemImage: "pencil") {
                    paragraphEditing = region
                }.disabled(store.isBusy)
            }.buttonStyle(.bordered)
            if let index = store.regions.firstIndex(where: { $0.id == region.id }) {
                Menu("合并相邻段落", systemImage: "rectangle.3.group") {
                    if index > 0 {
                        Button("与上一段合并") { store.mergeSelected(with: store.regions[index - 1].id) }
                    }
                    if index + 1 < store.regions.count {
                        Button("与下一段合并") { store.mergeSelected(with: store.regions[index + 1].id) }
                    }
                }.disabled(store.isBusy || store.regions.count < 2)
            }
            Button("删除这段", role: .destructive) {
                store.remove(id: region.id); showingParagraph = false; showingFullPageParagraph = false
            }.font(.footnote).disabled(store.isBusy)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exportPreview() {
        guard let image = store.image else { return }
        exporting = true
        let regions = store.regions
        let page = selectedPage
        let token = exportGeneration
        Task {
            let result = await Task.detached(priority: .utility) {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                let width = min(1_600, image.size.width)
                let pageHeight = image.size.height * width / image.size.width
                let font = UIFont.systemFont(ofSize: max(24, width * 0.028))
                let style = NSMutableParagraphStyle(); style.lineSpacing = font.pointSize * 0.25
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black, .paragraphStyle: style]
                let paragraphs = regions.enumerated().map { index, region in
                    "段落 \(index + 1)\n\(region.translated.isEmpty ? "尚未翻译" : region.translated)"
                }
                let heights = paragraphs.map {
                    ceil(($0 as NSString).boundingRect(with: CGSize(width: width - 64, height: .greatestFiniteMagnitude),
                                                       options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                       attributes: attributes, context: nil).height) + 32
                }
                // The image export gets a readable transcript below the source,
                // never number-only substitutes. The TXT always contains all text.
                let appendix = min(6_000, heights.reduce(64, +))
                let rendered = UIGraphicsImageRenderer(size: CGSize(width: width, height: pageHeight + appendix), format: format).image { context in
                    UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: pageHeight + appendix))
                    image.draw(in: CGRect(x: 0, y: 0, width: width, height: pageHeight))
                    var y = pageHeight + 32
                    for index in paragraphs.indices {
                        guard y + heights[index] < pageHeight + appendix - 16 else {
                            ("更多内容请查看随附的完整译文 TXT" as NSString).draw(at: CGPoint(x: 32, y: y), withAttributes: attributes)
                            break
                        }
                        (paragraphs[index] as NSString).draw(in: CGRect(x: 32, y: y, width: width - 64, height: heights[index]), withAttributes: attributes)
                        y += heights[index]
                    }
                }
                guard let data = rendered.pngData() else { return Optional<URL>.none }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("中文预览-第\(page + 1)页-\(UUID().uuidString.prefix(6)).png")
                do {
                    try data.write(to: url)
                    let text = regions.enumerated().map {
                        "[\($0.offset + 1)] \($0.element.source)\n\($0.element.translated)"
                    }.joined(separator: "\n\n")
                    try text.write(to: url.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
                    return url
                } catch { return nil }
            }.value
            guard exportGeneration == token, selectedPage == page else { return }
            exportURL = result; exporting = false
        }
    }
}

private struct TranslationEditor: View {
    @Environment(\.dismiss) private var dismiss
    let region: TranslationRegion
    let save: (String, String) -> Void
    @State private var source: String
    @State private var translated: String
    init(region: TranslationRegion, save: @escaping (String, String) -> Void) {
        self.region = region; self.save = save
        _source = State(initialValue: region.source); _translated = State(initialValue: region.translated)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("日文原文") { TextEditor(text: $source).frame(minHeight: 100) }
                Section("中文译文") { TextEditor(text: $translated).frame(minHeight: 140) }
                Text("修改会保存在这一页。只修改原文时，旧译文会清空，可再点“翻译此处”。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("校对这段文字")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save(source, translated); dismiss() } }
            }
        }
    }
}

struct TranslationSettingsView: View {
    @AppStorage("translation.model") private var model = AIModelChoice.pro.rawValue
    @AppStorage("ai.includeOCRText") private var uploadText = true
    @AppStorage("ai.allowsCellular") private var allowsCellular = true
    var body: some View {
        Form {
            Section {
                Label("日语图片 → 简体中文", systemImage: "character.bubble.fill")
                Text("在漫画、图片和 PDF 阅读页点“译”。识别在本机完成；翻译仅发送识别文字，不上传原图。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("翻译服务") {
                Picker("翻译模型", selection: $model) {
                    ForEach(AIModelChoice.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("允许上传识别文字", isOn: $uploadText)
                Toggle("允许使用蜂窝网络", isOn: $allowsCellular)
                NavigationLink("密钥与连接设置") { AISettingsView() }
            }
            Section("译文与原图") {
                Text("识别结果、译文和手动校对自动保存。图片内容改变后会建立新的翻译记录。")
                Text("点击原图中的段落查看对应译文；下方始终可查看整页文字。中文模式连续显示中文，对照模式同时显示日文与中文，长译文不会因识别框太小而隐藏。导出附带完整原文与译文文本。")
                Text("竖排、小字、振假名或拟声字可能需要框选重识别和校对。")
            }.font(.footnote)
        }.navigationTitle("图片翻译").navigationBarTitleDisplayMode(.inline)
    }
}
