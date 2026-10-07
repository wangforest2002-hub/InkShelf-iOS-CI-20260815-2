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
    var selectedRegion: TranslationRegion? { regions.first { $0.id == selectedID } }

    func open(source: AIPageSource, page: Int, bookID: UUID) {
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
                    isBusy = false; status = "示例译文 · 用于界面预览"
                    return
                }
#endif
                if let saved = await PageTranslationService.shared.load(key: prepared.key) {
                    guard isCurrent(token) else { return }
                    regions = saved.regions; modelID = saved.modelID
                    status = "已恢复 \(completedCount) / \(regions.count) 处译文"
                } else {
                    status = "点“识别本页”或框选一处日文"
                }
                isBusy = false
            } catch {
                guard isCurrent(token) else { return }
                self.error = error.localizedDescription; isBusy = false; status = "画面准备失败"
            }
        }
    }

    func recognize(selection: TranslationBox? = nil) {
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
                    regions.append(contentsOf: found)
                } else if regions.isEmpty {
                    regions = found
                }
                selectedID = found.first?.id
                status = found.isEmpty ? "没有识别到文字，可扩大框选范围或手动添加" : "已识别 \(regions.count) 处文字，可以校对或翻译"
                isBusy = false
                persist()
            } catch {
                guard isCurrent(token) else { return }
                self.error = error.localizedDescription; isBusy = false; status = "识别未完成"
            }
        }
    }

    func translate(selectedOnly: Bool = false) {
        guard !isBusy else { return }
        let candidates = regions.filter {
            !$0.source.isEmpty && (selectedOnly ? $0.id == selectedID : $0.translated.isEmpty)
        }
        guard !candidates.isEmpty else { status = "没有待翻译的文字"; return }
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
                // Small batches keep dense pages complete without one oversized response.
                for start in stride(from: 0, to: candidates.count, by: 6) {
                    guard isCurrent(token) else { return }
                    let batch = Array(candidates[start..<min(start + 6, candidates.count)])
                    let translated = try await DeepSeekService.shared.translateRegions(
                        batch, apiKey: apiKey, model: model, allowsCellularAccess: cellular
                    )
                    guard isCurrent(token) else { return }
                    for index in regions.indices {
                        if let value = translated[regions[index].id] { regions[index].translated = value }
                    }
                    modelID = model.modelID
                    status = "已完成 \(completedCount) / \(regions.count) 处"
                    persist()
                }
                isBusy = false
                status = completedCount == regions.count ? "本页翻译完成 · 点击文字可校对" : "部分文字未返回译文，可继续翻译"
            } catch {
                guard isCurrent(token) else { return }
                self.error = error.localizedDescription; isBusy = false
                status = "已保留 \(completedCount) 处译文，可重试剩余文字"
            }
        }
    }

    func select(_ id: String?) { selectedID = id }

    func edit(id: String, source: String, translated: String) {
        guard !isBusy, let index = regions.firstIndex(where: { $0.id == id }) else { return }
        let cleanedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTranslation = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        let changedOnlySource = cleanedSource != regions[index].source && cleanedTranslation == regions[index].translated
        regions[index].source = cleanedSource
        regions[index].translated = changedOnlySource ? "" : cleanedTranslation
        regions[index].isEdited = true
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
