import Foundation
import Observation
import UIKit

@MainActor @Observable
final class PageTranslationStore {
    private(set) var image: UIImage?
    private(set) var regions: [TranslationRegion] = []
    private(set) var isBusy = false
    private(set) var status = "正在准备画面…"
    private(set) var error: String?
    private(set) var selectedID: String?
    @ObservationIgnored private var key: String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var modelID: String?

    var completedCount: Int { regions.filter { !$0.translated.isEmpty }.count }
    var pendingCount: Int { regions.filter { !$0.source.isEmpty && ($0.translated.isEmpty || $0.needsRetranslation == true) }.count }
    var selectedRegion: TranslationRegion? { regions.first { $0.id == selectedID } }

    func open(source: AIPageSource, page: Int, bookID: UUID, automaticallyTranslate: Bool = false) {
        cancel()
        let token = generation
        image = nil; regions = []; key = nil; selectedID = nil; error = nil; modelID = nil
        isBusy = true; status = "正在准备画面…"
        task = Task {
            do {
                let prepared = try await PageTranslationService.shared.prepare(source: source, page: page, bookID: bookID)
                guard isCurrent(token) else { return }
                image = prepared.image; key = prepared.key
                await saveTask?.value
                guard isCurrent(token) else { return }
#if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_APPEARANCE") {
                    regions = AppearancePreviewFixture.translationRegions
                    if ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_TRANSLATION_EMPTY") {
                        regions = []
                        isBusy = false; status = "准备翻译本页"
                        if automaticallyTranslate { translatePage() }
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_TRANSLATION_TIGHT_BOXES") {
                        // Reproduce a real line-height OCR box that could not fit
                        // Chinese in 3.0.0. These are UI fixtures, not cloud results.
                        regions[0].box = TranslationBox(CGRect(x: 0.13, y: 0.16, width: 0.70, height: 0.012))
                    }
                    isBusy = false; status = "示例译文 · 用于界面预览"
                    return
                }
#endif
                if let saved = await PageTranslationService.shared.load(key: prepared.key) {
                    guard isCurrent(token) else { return }
                    regions = saved.schema == 1
                        ? TranslationParagraphs.group(saved.regions, imageSize: prepared.image.size)
                        : saved.regions
                    modelID = saved.modelID
                    status = "已恢复 \(completedCount) / \(regions.count) 处译文"
                    if saved.schema == 1 { persist() }
                } else {
                    status = "点“翻译本页”，自动识别并翻译"
                }
                isBusy = false
                if automaticallyTranslate && (regions.isEmpty || pendingCount > 0) { translatePage() }
            } catch {
                guard isCurrent(token) else { return }
                self.error = error.localizedDescription; isBusy = false; status = "画面准备失败"
            }
        }
    }

    /// One action owns the complete pipeline. Cached translations are reused;
    /// stopping or changing page invalidates recognition before it can start AI.
    func translatePage() {
        guard image != nil, !isBusy else { return }
        if regions.isEmpty { recognize(translateAfter: true) }
        else { translate() }
    }

    func recognize(selection: TranslationBox? = nil, translateAfter: Bool = false) {
        guard let image, !isBusy else { return }
        begin(status: selection == nil ? "正在识别本页日文…" : "正在识别框选区域…")
        let token = generation
        task = Task {
            do {
                let found = try await PageTranslationService.shared.recognize(image: image, selection: selection)
                guard isCurrent(token) else { return }
                if selection != nil {
                    // Never silently erase a translated or manually corrected region.
                    regions.removeAll { old in
                        !old.isEdited && old.translated.isEmpty && selection!.rect.intersects(old.box.rect)
                    }
                    regions = TranslationParagraphs.ordered(regions + found)
                } else if regions.isEmpty {
                    regions = found
                }
                selectedID = nil
                status = found.isEmpty ? "没有识别到可翻译的文字，请检查页面清晰度后重试" : "已识别 \(regions.count) 段文字"
                isBusy = false
                persist()
                if translateAfter && !found.isEmpty { translate() }
            } catch {
                guard isCurrent(token) else { return }
                self.error = error.localizedDescription; isBusy = false; status = "识别未完成"
            }
        }
    }

    func translate(selectedOnly: Bool = false) {
        guard !isBusy else { return }
        let candidates = regions.filter {
            !$0.source.isEmpty && (selectedOnly ? $0.id == selectedID : $0.translated.isEmpty || $0.needsRetranslation == true)
        }
        guard !candidates.isEmpty else { status = "没有待翻译的文字"; return }
        guard candidates.allSatisfy({ $0.source.count <= 4_000 }) else {
            error = "某段文字过长，请在校对中缩短为完整段落后重译。"; return
        }
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "ai.includeOCRText") as? Bool ?? true else {
            error = "文字上传已关闭。可先本机识别和校对；在翻译与陪读设置中开启文字上传后再翻译。"; return
        }
        guard let apiKey = KeychainStore.read(account: "deepseek-api-key"), !apiKey.isEmpty else {
            error = "请先在翻译与陪读设置中填写 API 密钥。识别文字可以离线使用。"; return
        }
        let model = AIModelChoice(rawValue: defaults.string(forKey: "translation.model") ?? "") ?? .pro
        let cellular = defaults.object(forKey: "ai.allowsCellular") as? Bool ?? true
        begin(status: "正在翻译日文…")
        let token = generation
        task = Task {
            do {
                // Bound text as well as paragraph count: a dense paragraph is
                // larger than the old line-level records.
                var remaining = candidates[...]
                while !remaining.isEmpty {
                    guard isCurrent(token) else { return }
                    var batch: [TranslationRegion] = []
                    var characters = 0
                    while let next = remaining.first, batch.count < 6 {
                        if !batch.isEmpty && characters + next.source.count > 1_800 { break }
                        batch.append(next); characters += next.source.count; remaining = remaining.dropFirst()
                    }
                    let translated = try await DeepSeekService.shared.translateRegions(
                        batch, pageContext: regions, apiKey: apiKey, model: model, allowsCellularAccess: cellular
                    )
                    guard isCurrent(token) else { return }
                    for index in regions.indices {
                        if let value = translated[regions[index].id] {
                            regions[index].translated = value; regions[index].needsRetranslation = false
                        }
                    }
                    modelID = model.modelID
                    status = "已完成 \(completedCount) / \(regions.count) 处"
                    persist()
                }
                isBusy = false
                status = pendingCount == 0 ? "本页翻译完成 · 点击段落查看译文" : "部分段落未返回译文，可继续翻译"
            } catch {
                guard isCurrent(token) else { return }
                self.error = error.localizedDescription; isBusy = false
                status = "已保留 \(completedCount) 处译文，可重试剩余文字"
            }
        }
    }

    func select(_ id: String?) {
        if selectedID != id { error = nil }
        selectedID = id
    }

    func edit(id: String, source: String, translated: String) {
        guard !isBusy, let index = regions.firstIndex(where: { $0.id == id }) else { return }
        let cleanedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTranslation = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        let changedOnlySource = cleanedSource != regions[index].source && cleanedTranslation == regions[index].translated
        regions[index].source = cleanedSource
        regions[index].translated = changedOnlySource ? "" : cleanedTranslation
        regions[index].isEdited = true
        regions[index].needsRetranslation = false
        persist()
    }

    func mergeSelected(with id: String) {
        guard !isBusy, let selectedID, selectedID != id,
              let first = regions.firstIndex(where: { $0.id == selectedID }),
              let second = regions.firstIndex(where: { $0.id == id }) else { return }
        let lower = min(first, second), upper = max(first, second)
        let merged = TranslationParagraphs.merge([regions[lower], regions[upper]])
        regions[lower] = merged; regions.remove(at: upper)
        self.selectedID = merged.id
        status = "已合并为完整段落，原有译文已保留，可重译此段"
        persist()
    }

    func remove(id: String) {
        guard !isBusy else { return }
        regions.removeAll { $0.id == id }; selectedID = nil; persist()
    }

    func addManual(box: TranslationBox) {
        guard !isBusy else { return }
        let region = TranslationRegion(id: UUID().uuidString, box: box, source: "", confidence: 0, isVertical: false, isEdited: true)
        regions.append(region); selectedID = region.id; persist()
    }

    func cancel() {
        task?.cancel(); generation = UUID(); isBusy = false
        status = "已暂停，已完成的结果会保留"
    }

    private func begin(status: String) {
        cancel(); error = nil; isBusy = true; self.status = status
    }

    private func isCurrent(_ token: UUID) -> Bool { generation == token && !Task.isCancelled }

    private func persist() {
        guard let key else { return }
        let document = PageTranslationDocument(regions: regions, modelID: modelID)
        let previous = saveTask
        // Writes are chained, so an older correction cannot overwrite a newer one.
        saveTask = Task {
            await previous?.value
            do { try await PageTranslationService.shared.save(document, key: key) }
            catch { if self.key == key { self.error = "译文暂未保存：\(error.localizedDescription)" } }
        }
    }
}
