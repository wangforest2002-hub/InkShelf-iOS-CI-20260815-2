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
    @State private var showingSettings = false
    @State private var compactPanel = false
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
                        HStack(spacing: 0) {
                            TranslationCanvas(image: image, regions: store.regions,
                                              mode: previewOriginal || isSelecting ? .original : mode,
                                              selectedID: store.selectedID, isSelecting: isSelecting,
                                              onSelect: { id in
                                store.select(id)
                                if !wide { compactPanel = true }
                            }, onRegion: { box in
                                isSelecting = false
                                if manualSelection {
                                    store.addManual(box: box); mode = .comparison
                                    if !wide { compactPanel = true }
                                } else { store.recognize(selection: box) }
                            })
                            if wide && mode != .original {
                                regionList.frame(width: min(360, proxy.size.width * 0.32))
                            }
                        }
                    } else {
                        ContentUnavailableView("日文图片翻译", systemImage: "character.bubble",
                                               description: Text(store.status))
                            .frame(maxHeight: .infinity)
                    }
                    statusBar
                    if !wide && !store.regions.isEmpty {
                        Button { compactPanel = true } label: {
                            Label("原文与译文 · \(store.completedCount)/\(store.regions.count)", systemImage: "text.bubble")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal)
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
                        Button("导出当前中文预览", systemImage: "square.and.arrow.up") { exportPreview() }
                            .disabled(store.completedCount == 0 || exporting || store.isBusy)
                        if let exportURL { ShareLink("分享图片与完整译文", items: [exportURL, exportURL.deletingPathExtension().appendingPathExtension("txt")]) }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .task(id: selectedPage) {
                isSelecting = false; exportURL = nil; exporting = false; exportGeneration = UUID()
                guard let input = pages.first(where: { $0.page == selectedPage }) else { return }
                store.open(source: input.source, page: input.page, bookID: book.id)
            }
        }
        .onDisappear { store.cancel() }
        .sheet(isPresented: $compactPanel) {
            NavigationStack {
                regionList.navigationTitle("原文与译文")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { compactPanel = false } } }
            }.presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSettings) { NavigationStack { TranslationSettingsView() } }
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
                    Button("翻译未完成文字", systemImage: "character.bubble.fill") { store.translate() }
                        .disabled(store.regions.isEmpty || store.isBusy || store.completedCount == store.regions.count)
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
                ShareLink("分享中文预览与完整译文", items: [exportURL, exportURL.deletingPathExtension().appendingPathExtension("txt")]).font(.caption)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var regionList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("原图不改写 · 点选区域进行校对")
                        .font(.caption).foregroundStyle(.secondary)
                    if store.regions.isEmpty {
                        ContentUnavailableView("先识别日文", systemImage: "viewfinder",
                                               description: Text("文字会按区域列在这里。遇到小字或竖排漏字，可以框选重识别。"))
                    }
                    ForEach(Array(store.regions.enumerated()), id: \.element.id) { index, region in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Button { store.select(region.id) } label: {
                                    Label("区域 \(index + 1)", systemImage: "scope")
                                }
                                Spacer()
                                if region.isEdited { Text("已校对").font(.caption2).foregroundStyle(AppTheme.mint) }
                                else if region.confidence < 0.65 { Text("请核对原文").font(.caption2).foregroundStyle(.orange) }
                            }.font(.caption.weight(.semibold))
                            Text(region.source.isEmpty ? "尚未填写原文" : region.source)
                                .font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                            Text(region.translated.isEmpty ? "等待翻译" : region.translated)
                                .font(.body).textSelection(.enabled)
                            HStack {
                                Button("校对") { editing = region }
                                Button(region.translated.isEmpty ? "翻译此处" : "重译") {
                                    store.select(region.id); store.translate(selectedOnly: true)
                                }.disabled(region.source.isEmpty)
                                Spacer()
                                Button(role: .destructive) { store.remove(id: region.id) } label: { Image(systemName: "trash") }
                            }.font(.caption).buttonStyle(.bordered).disabled(store.isBusy)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).stroke(region.id == store.selectedID ? AppTheme.accent : .clear, lineWidth: 2) }
                        .id(region.id)
                    }
                }.padding(14)
            }
            .onChange(of: store.selectedID) { _, id in
                if let id { withAnimation(reduceMotion ? nil : AppMotion.value) { proxy.scrollTo(id, anchor: .center) } }
            }
        }.background(Color(.systemGroupedBackground))
        .sheet(item: $editing) { region in
            TranslationEditor(region: region) { source, translated in
                store.edit(id: region.id, source: source, translated: translated)
            }
        }
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
                // Keep the export bounded. Long translations are also included as a
                // UTF-8 companion file through the share sheet below.
                let rendered = UIGraphicsImageRenderer(size: image.size, format: format).image { context in
                    image.draw(in: CGRect(origin: .zero, size: image.size))
                    for (index, region) in regions.enumerated() where !region.translated.isEmpty {
                        let rect = region.box.pixels(in: image.size)
                        let font = TranslationTypography.font(for: region.translated, in: rect.size, imageWidth: image.size.width)
                        let style = NSMutableParagraphStyle(); style.alignment = .center
                        if let font {
                            UIColor.white.setFill(); context.fill(rect)
                            (region.translated as NSString).draw(in: rect.insetBy(dx: 6, dy: 6), withAttributes: [
                                .font: font, .foregroundColor: UIColor.black, .paragraphStyle: style
                            ])
                        } else {
                            let side = max(30, image.size.width * 0.04)
                            let badge = CGRect(x: rect.minX, y: rect.minY, width: side, height: side)
                            UIColor.systemBlue.setFill(); context.fill(badge)
                            ("\(index + 1)" as NSString).draw(in: badge, withAttributes: [
                                .font: UIFont.systemFont(ofSize: side * 0.7), .foregroundColor: UIColor.white, .paragraphStyle: style
                            ])
                        }
                    }
                }
                guard let data = rendered.pngData() else { return Optional<URL>.none }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("中文预览-第\(page + 1)页-\(UUID().uuidString.prefix(6)).png")
                do {
                    try data.write(to: url)
                    let text = regions.enumerated().filter { !$0.element.translated.isEmpty }.map {
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
                Text("中文模式是可关闭的文字覆盖层；复杂背景建议使用对照模式。放不下的长句以编号标记，完整译文可在对照面板查看；导出包含当前清晰预览与完整译文文本，原文件始终保留。")
                Text("竖排、小字、振假名或拟声字可能需要框选重识别和校对。")
            }.font(.footnote)
        }.navigationTitle("图片翻译").navigationBarTitleDisplayMode(.inline)
    }
}
