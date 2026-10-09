import SwiftUI
import UIKit

struct TranslationPageInput: Identifiable {
    let page: Int
    let source: AIPageSource
    var id: Int { page }
}

private enum TranslationPanelScope: String, CaseIterable, Identifiable {
    case page = "整页译文"
    case paragraph = "当前段落"
    var id: Self { self }
}

struct PageTranslationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let book: Book
    let pages: [TranslationPageInput]
    @State private var store = PageTranslationStore()
    @State private var selectedPage: Int
    @State private var scope: TranslationPanelScope = .page
    @State private var editing: TranslationRegion?
    @State private var showingSettings = false
    @State private var showingFullPage = false
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
                VStack(spacing: 0) {
                    controls
                    if let image = store.image {
                        TranslationCanvas(image: image, regions: store.regions, mode: .comparison,
                                          selectedID: store.selectedID, isSelecting: false,
                                          onSelect: selectParagraph, onRegion: { _ in })
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(alignment: .top) {
                                if !store.regions.isEmpty {
                                    Text("点图中文字，查看对应译文")
                                        .font(.caption).padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(.regularMaterial, in: Capsule()).padding(10)
                                        .allowsHitTesting(false)
                                }
                            }
                    } else if store.isBusy {
                        ProgressView(store.status).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView("暂时无法读取本页", systemImage: "doc.questionmark",
                                               description: Text("点“重试翻译”重新打开，或返回阅读器。"))
                            .frame(maxHeight: .infinity)
                    }
                    statusBar
                    if !store.regions.isEmpty {
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Picker("译文范围", selection: $scope) {
                                    Text("整页译文").tag(TranslationPanelScope.page)
                                    Text("当前段落").tag(TranslationPanelScope.paragraph)
                                }.pickerStyle(.segmented)
                                    .accessibilityIdentifier("translation-scope")
                                Button("放大阅读", systemImage: "arrow.up.left.and.arrow.down.right") { showingFullPage = true }
                                    .labelStyle(.iconOnly).accessibilityIdentifier("translation-full-page")
                            }.padding(12)
                            Divider()
                            if scope == .paragraph, let region = store.selectedRegion {
                                ScrollView { paragraphDetail(region).padding(16) }
                                    .accessibilityIdentifier("translation-paragraph-panel")
                            } else {
                                regionList()
                            }
                        }
                        .frame(height: min(340, max(170, proxy.size.height * 0.38)))
                    }
                }
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("翻译本页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回阅读") { store.cancel(); dismiss() }
                        .accessibilityIdentifier("translation-close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("翻译设置", systemImage: "gearshape") { store.cancel(); showingSettings = true }
                        Button("导出原图与译文", systemImage: "square.and.arrow.up") { exportPreview() }
                            .disabled(store.completedCount == 0 || exporting || store.isBusy)
                        if let exportURL { ShareLink("分享原图与完整译文", items: [exportURL, exportURL.deletingPathExtension().appendingPathExtension("txt")]) }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityIdentifier("translation-more")
                }
            }
            .task(id: selectedPage) {
                scope = .page; showingFullPage = false; editing = nil
                exportURL = nil; exporting = false; exportGeneration = UUID()
                openPage()
            }
        }
        .onDisappear { store.cancel() }
        .sheet(isPresented: $showingFullPage) {
            NavigationStack {
                regionList(expanded: true)
                    .navigationTitle("整页译文").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("返回图片") { showingFullPage = false }.accessibilityIdentifier("translation-full-close")
                    } }
            }.presentationDetents([.large])
        }
        .sheet(item: $editing) { region in
            TranslationEditor(region: region) { source, translated in
                store.edit(id: region.id, source: source, translated: translated)
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                TranslationSettingsView().toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("返回翻译") { showingSettings = false }
                        .accessibilityIdentifier("translation-settings-close")
                } }
            }
        }
        .onChange(of: scope) { _, newValue in
            if newValue == .paragraph && store.selectedID == nil, let first = store.regions.first { store.select(first.id) }
        }
    }

    private var complete: Bool {
        !store.regions.isEmpty && store.completedCount == store.regions.count && store.pendingCount == 0
    }

    private var actionTitle: String {
        if store.isBusy { return "停止翻译" }
        if complete { return "翻译完成" }
        if store.error != nil { return "重试翻译" }
        if store.regions.isEmpty { return "翻译本页" }
        return store.completedCount > 0 ? "继续翻译" : "翻译本页"
    }

    private var controls: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if pages.count > 1 {
                    Picker("当前页", selection: $selectedPage) {
                        ForEach(pages) { page in Text("第 \(page.page + 1) 页").tag(page.page) }
                    }.pickerStyle(.menu)
                } else { Text("第 \(selectedPage + 1) 页").font(.subheadline.weight(.semibold)) }
                Text("日语 → 中文 · 自动识别整页").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                if store.isBusy { store.cancel() }
                else if store.image == nil { openPage() }
                else { store.translatePage() }
            } label: {
                HStack(spacing: 8) {
                    if store.isBusy { ProgressView().tint(.white) }
                    else { Image(systemName: complete ? "checkmark" : "character.bubble.fill") }
                    Text(actionTitle)
                }.frame(minHeight: 28)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(complete && !store.isBusy)
            .accessibilityLabel(actionTitle)
            .accessibilityIdentifier("translation-start")
        }.padding(12).background(.regularMaterial)
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.status).font(.caption).foregroundStyle(.secondary)
            if let error = store.error {
                HStack(alignment: .top, spacing: 12) {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                    Spacer(minLength: 0)
                    Button("翻译设置") { showingSettings = true }
                        .font(.footnote.weight(.semibold))
                        .accessibilityIdentifier("translation-error-settings")
                }
            }
            if let exportURL {
                ShareLink("分享原图与完整译文", items: [exportURL, exportURL.deletingPathExtension().appendingPathExtension("txt")]).font(.caption)
            }
        }.padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openPage() {
        guard let input = pages.first(where: { $0.page == selectedPage }) else { return }
        store.open(source: input.source, page: input.page, bookID: book.id, automaticallyTranslate: true)
    }

    private func selectParagraph(_ id: String) {
        store.select(id)
        withAnimation(reduceMotion ? nil : AppMotion.value) { scope = .paragraph }
        // An untranslated paragraph also works with a single tap, after a pause
        // or partial result. Completed and corrected translations are reused.
        if !store.isBusy, let region = store.selectedRegion,
           region.translated.isEmpty || region.needsRetranslation == true {
            store.translate(selectedOnly: true)
        }
    }

    private func regionList(expanded: Bool = false) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(store.regions.enumerated()), id: \.element.id) { index, region in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("第 \(index + 1) 段").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                                Spacer()
                                if region.needsRetranslation == true {
                                    Text("建议重译").font(.caption2).foregroundStyle(.orange)
                                } else if region.isEdited {
                                    Text("已校对").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Text(region.translated.isEmpty ? (store.isBusy ? "正在翻译…" : "暂未完成，点“翻译本页”重试") : region.translated)
                                .font(.body).lineSpacing(5)
                                .accessibilityIdentifier(expanded ? "translation-full-text-\(region.id)" : "translation-text-\(region.id)")
                            Label("查看对应位置", systemImage: "scope").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).stroke(region.id == store.selectedID ? AppTheme.accent : .clear, lineWidth: 2) }
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                        .onTapGesture {
                            if expanded { showingFullPage = false }
                            selectParagraph(region.id)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            if expanded { showingFullPage = false }
                            selectParagraph(region.id)
                        }
                        .accessibilityIdentifier(expanded ? "translation-full-detail-\(region.id)" : "translation-detail-\(region.id)")
                        .id(region.id)
                    }
                }.padding(12)
            }
            .accessibilityIdentifier(expanded ? "translation-full-page-text" : "translation-page-text")
            .onChange(of: store.selectedID) { _, id in
                if let id { withAnimation(reduceMotion ? nil : AppMotion.value) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    private func paragraphDetail(_ region: TranslationRegion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let index = store.regions.firstIndex(where: { $0.id == region.id }) {
                HStack {
                    Text("第 \(index + 1) / \(store.regions.count) 段").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button("上一段", systemImage: "chevron.left") { selectParagraph(store.regions[index - 1].id) }
                        .labelStyle(.iconOnly).disabled(index == 0)
                        .accessibilityIdentifier("translation-previous-paragraph")
                    Button("下一段", systemImage: "chevron.right") { selectParagraph(store.regions[index + 1].id) }
                        .labelStyle(.iconOnly).disabled(index + 1 >= store.regions.count)
                        .accessibilityIdentifier("translation-next-paragraph")
                }.buttonStyle(.bordered)
            }
            Text(region.translated.isEmpty ? (store.isBusy ? "正在翻译这一段…" : "点“翻译本页”继续翻译") : region.translated)
                .font(.title3).lineSpacing(6).textSelection(.enabled)
                .accessibilityIdentifier("translation-selected-text")
            if region.needsRetranslation == true {
                Text("旧译文已保留，合并后的段落正在等待重译。")
                    .font(.footnote).foregroundStyle(.orange)
            }
            HStack {
                Button(region.translated.isEmpty ? "翻译这段" : "重译这段", systemImage: "arrow.clockwise") {
                    store.translate(selectedOnly: true)
                }.disabled(store.isBusy || region.source.isEmpty)
                    .accessibilityIdentifier("translation-retranslate-paragraph")
                Spacer()
                Menu("校对与整理", systemImage: "ellipsis.circle") {
                    Button("校对原文与译文", systemImage: "pencil") { editing = region }
                    if let index = store.regions.firstIndex(where: { $0.id == region.id }) {
                        if index > 0 { Button("与上一段合并") { store.mergeSelected(with: store.regions[index - 1].id) } }
                        if index + 1 < store.regions.count { Button("与下一段合并") { store.mergeSelected(with: store.regions[index + 1].id) } }
                    }
                    Button("删除这段", role: .destructive) { store.remove(id: region.id); scope = .page }
                }.disabled(store.isBusy)
                    .accessibilityIdentifier("translation-paragraph-tools")
            }.font(.caption).buttonStyle(.bordered)
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
                Section("日文原文") { TextEditor(text: $source).frame(minHeight: 100).accessibilityIdentifier("translation-editor-source") }
                Section("中文译文") { TextEditor(text: $translated).frame(minHeight: 140).accessibilityIdentifier("translation-editor-translation") }
                Text("修改会保存在这一页。只修改原文时，旧译文会清空，可再点“翻译本页”。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("校对这段文字")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.accessibilityIdentifier("translation-editor-cancel") }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save(source, translated); dismiss() }.accessibilityIdentifier("translation-editor-save") }
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
                Text("点阅读器的“翻译”就会自动识别当前整页并翻译，无需选择显示方式或框选位置。已有译文会直接恢复。点图中文字或译文卡片可查看对应段落，下方可连续阅读整页译文；日文原文在校对入口查看。")
                Text("竖排、小字、振假名或拟声字可能需要校对原文，或合并相邻段落后重译。")
            }.font(.footnote)
        }.navigationTitle("翻译设置").navigationBarTitleDisplayMode(.inline)
    }
}
