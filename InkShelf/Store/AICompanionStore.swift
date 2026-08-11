import Foundation
import Observation

@MainActor
@Observable
final class AICompanionStore {
    private(set) var hasAPIKey: Bool
    private(set) var activity: AICompanionActivity = .idle
    private(set) var currentBookID: UUID?
    private(set) var currentPage = 0
    private(set) var currentInsight: AIPageInsight?
    private(set) var currentReaction: AIPageReaction?
    private(set) var endDiscussion: AIEndDiscussion?
    private(set) var chatMessages: [AIChatMessage] = []
    private(set) var connectionMessage: String?
    var errorMessage: String?

    @ObservationIgnored private static let keyAccount = "deepseek-api-key"
    @ObservationIgnored private var pageTask: Task<Void, Never>?
    @ObservationIgnored private var discussionTask: Task<Void, Never>?
    @ObservationIgnored private var requestContext: RequestContext?
    @ObservationIgnored private var reactions: [String: AIPageReaction] = [:]

    init() {
        hasAPIKey = !(KeychainStore.read(account: Self.keyAccount) ?? "").isEmpty
    }

    func saveAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DeepSeekError.missingKey }
        try KeychainStore.save(trimmed, account: Self.keyAccount)
        hasAPIKey = true
        UserDefaults.standard.set(true, forKey: "ai.enabled")
        connectionMessage = "已安全保存到本机钥匙串"
        errorMessage = nil
    }

    func removeAPIKey() throws {
        try KeychainStore.delete(account: Self.keyAccount)
        hasAPIKey = false
        UserDefaults.standard.set(false, forKey: "ai.enabled")
        connectionMessage = nil
        cancelAll()
    }

    func testConnection() async {
        guard let key = apiKey else {
            errorMessage = DeepSeekError.missingKey.localizedDescription
            return
        }
        connectionMessage = "正在连接…"
        errorMessage = nil
        do {
            let settings = requestSettings
            try await DeepSeekService.shared.validate(
                apiKey: key,
                model: settings.model,
                allowsCellularAccess: settings.allowsCellularAccess
            )
            connectionMessage = "连接成功 · \(settings.model.title)"
        } catch {
            connectionMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    func preparePage(
        book: Book,
        page: Int,
        pageCount: Int,
        source: AIPageSource,
        force: Bool = false
    ) {
        currentBookID = book.id
        currentPage = page
        currentReaction = nil
        currentInsight = nil
        endDiscussion = page >= pageCount - 1 ? endDiscussion : nil
        errorMessage = nil
        requestContext = RequestContext(book: book, page: page, pageCount: pageCount, source: source)
        pageTask?.cancel()
        discussionTask?.cancel()

        guard UserDefaults.standard.bool(forKey: "ai.enabled"), hasAPIKey else {
            activity = .idle
            return
        }

        pageTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(force ? 80 : 850))
            guard !Task.isCancelled, let self else { return }
            await self.loadOrGeneratePage(force: force)
        }
    }

    func regenerateCurrentPage() {
        guard let context = requestContext else { return }
        preparePage(
            book: context.book,
            page: context.page,
            pageCount: context.pageCount,
            source: context.source,
            force: true
        )
    }

    func generateEndDiscussion(force: Bool = false) {
        guard let context = requestContext,
              context.page >= context.pageCount - 1,
              UserDefaults.standard.bool(forKey: "ai.endComments"),
              hasAPIKey
        else { return }

        discussionTask?.cancel()
        discussionTask = Task { [weak self] in
            guard let self else { return }
            await self.loadOrGenerateDiscussion(context: context, force: force)
        }
    }

    func ask(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let context = requestContext, let key = apiKey else { return }
        chatMessages.append(AIChatMessage(role: .user, text: trimmed))
        activity = .answering
        errorMessage = nil
        do {
            let answer = try await DeepSeekService.shared.answer(
                apiKey: key,
                question: trimmed,
                bookTitle: context.book.title,
                insight: currentInsight,
                reaction: currentReaction,
                conversation: chatMessages,
                settings: requestSettings
            )
            guard currentBookID == context.book.id else { return }
            chatMessages.append(AIChatMessage(role: .companion, text: answer))
        } catch {
            errorMessage = error.localizedDescription
        }
        activity = .idle
    }

    func clearConversation() {
        chatMessages = []
    }

    func clearCachedContent() async {
        do {
            try await AIResponseCache.shared.clear()
            reactions = [:]
            currentReaction = nil
            currentInsight = nil
            endDiscussion = nil
            chatMessages = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelAll() {
        pageTask?.cancel()
        discussionTask?.cancel()
        activity = .idle
    }

    private func loadOrGeneratePage(force: Bool) async {
        guard let context = requestContext,
              let key = apiKey,
              currentBookID == context.book.id,
              currentPage == context.page
        else { return }

        let settings = requestSettings
        let memoryKey = reactionKey(bookID: context.book.id, page: context.page, variant: settings.cacheVariant)
        if !force {
            let memoryReaction = reactions[memoryKey]
            var diskReaction: AIPageReaction?
            if memoryReaction == nil {
                diskReaction = await AIResponseCache.shared.pageReaction(
                    bookID: context.book.id,
                    page: context.page,
                    variant: settings.cacheVariant
                )
            }
            if let cached = memoryReaction ?? diskReaction {
                guard currentBookID == context.book.id, currentPage == context.page else { return }
                reactions[memoryKey] = cached
                currentReaction = cached
                currentInsight = AIPageInsight(
                    page: context.page,
                    pageCount: context.pageCount,
                    recognizedText: "",
                    visualLabels: [],
                    faceCount: 0,
                    sourceKind: context.book.kind.label
                )
                activity = .idle
                if context.page >= context.pageCount - 1 { generateEndDiscussion() }
                return
            }
        }

        activity = .readingPage(context.page)
        do {
            let insight = try await PageInsightService.shared.analyze(
                source: context.source,
                page: context.page,
                pageCount: context.pageCount
            )
            guard !Task.isCancelled,
                  currentBookID == context.book.id,
                  currentPage == context.page
            else { return }

            let recent = reactions.values
                .filter { $0.page < context.page }
                .sorted { $0.page < $1.page }
            let reaction = try await DeepSeekService.shared.pageReaction(
                apiKey: key,
                bookTitle: context.book.title,
                insight: insight,
                recentReactions: recent,
                settings: settings
            )
            guard !Task.isCancelled,
                  currentBookID == context.book.id,
                  currentPage == context.page
            else { return }

            reactions[memoryKey] = reaction
            currentInsight = insight
            currentReaction = reaction
            await AIResponseCache.shared.save(reaction, bookID: context.book.id, variant: settings.cacheVariant)
            activity = .idle
            if context.page >= context.pageCount - 1 { generateEndDiscussion() }
        } catch is CancellationError {
            activity = .idle
        } catch {
            guard currentBookID == context.book.id, currentPage == context.page else { return }
            errorMessage = error.localizedDescription
            activity = .idle
        }
    }

    private func loadOrGenerateDiscussion(context: RequestContext, force: Bool) async {
        guard let key = apiKey else { return }
        let settings = requestSettings
        if !force, let cached = await AIResponseCache.shared.endDiscussion(
            bookID: context.book.id,
            variant: settings.cacheVariant
        ) {
            guard currentBookID == context.book.id else { return }
            endDiscussion = cached
            return
        }

        activity = .generatingDiscussion
        do {
            let recent = reactions.values.sorted { $0.page < $1.page }
            let discussion = try await DeepSeekService.shared.endDiscussion(
                apiKey: key,
                bookTitle: context.book.title,
                pageCount: context.pageCount,
                reactions: recent,
                settings: settings
            )
            guard !Task.isCancelled, currentBookID == context.book.id else { return }
            endDiscussion = discussion
            await AIResponseCache.shared.save(discussion, bookID: context.book.id, variant: settings.cacheVariant)
        } catch is CancellationError {
            // Page navigation can cancel a pending discussion without surfacing an error.
        } catch {
            guard currentBookID == context.book.id else { return }
            errorMessage = error.localizedDescription
        }
        activity = .idle
    }

    private var apiKey: String? {
        let value = KeychainStore.read(account: Self.keyAccount)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private var requestSettings: DeepSeekPageSettings {
        let defaults = UserDefaults.standard
        let model = AIModelChoice(rawValue: defaults.string(forKey: "ai.model") ?? "") ?? .pro
        let persona = AICompanionPersona(rawValue: defaults.string(forKey: "ai.persona") ?? "") ?? .friend
        let density = AIDanmakuDensity(rawValue: defaults.string(forKey: "ai.density") ?? "") ?? .balanced
        let strictSpoilers = defaults.object(forKey: "ai.strictSpoilers") as? Bool ?? true
        let includeText = defaults.object(forKey: "ai.includeOCRText") as? Bool ?? true
        let allowsCellular = defaults.object(forKey: "ai.allowsCellular") as? Bool ?? true
        return DeepSeekPageSettings(
            model: model,
            persona: persona,
            density: density,
            strictSpoilers: strictSpoilers,
            includeRecognizedText: includeText,
            allowsCellularAccess: allowsCellular
        )
    }

    private func reactionKey(bookID: UUID, page: Int, variant: String) -> String {
        "\(bookID.uuidString)-\(page)-\(variant)"
    }
}

private struct RequestContext: Sendable {
    let book: Book
    let page: Int
    let pageCount: Int
    let source: AIPageSource
}
