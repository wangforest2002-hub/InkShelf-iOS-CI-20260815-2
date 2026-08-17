import Foundation
import Observation

@MainActor
@Observable
final class KokoAgentStore {
    private(set) var decision = KokoDecision(
        action: .rest,
        phrase: "窗边的光很柔和。我先在这里等你。",
        innerThought: "安静熟悉这个家。",
        duration: 12
    )
    private(set) var decisionRevision = 0
    private(set) var memories: [KokoMemory] = []
    private(set) var innerState: KokoInnerState
    private(set) var conversation: [AIChatMessage] = []
    private(set) var isThinking = false
    private(set) var isReplying = false
    var errorMessage: String?

    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let memoryURL: URL
    @ObservationIgnored private let innerStateURL: URL
    @ObservationIgnored private var autonomyTask: Task<Void, Never>?
    @ObservationIgnored private var decisionTask: Task<Void, Never>?
    @ObservationIgnored private var lastAIRequestAt: Date?
    @ObservationIgnored private var latestWorld: HomeWorldState?
    @ObservationIgnored private var latestBooks: [Book] = []

    init(fileManager: FileManager = .default, documentsURL: URL? = nil) {
        self.fileManager = fileManager
        let documents = documentsURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appendingPathComponent("InkShelf Library", isDirectory: true)
        memoryURL = root.appendingPathComponent("koko-memory.json")
        innerStateURL = root.appendingPathComponent("koko-state.json")
        memories = Self.loadMemories(from: memoryURL)
        innerState = Self.loadInnerState(from: innerStateURL) ?? KokoInnerState()
    }

    func start(world: HomeWorldState, books: [Book]) {
        latestWorld = world
        latestBooks = books
        if autonomyTask == nil {
            react(to: .enteredHome, world: world, books: books, prefersAI: true)
            autonomyTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(78))
                    guard !Task.isCancelled, let self,
                          let world = self.latestWorld
                    else { continue }
                    self.react(to: .periodic, world: world, books: self.latestBooks, prefersAI: true)
                }
            }
        }
    }

    func updateContext(world: HomeWorldState, books: [Book]) {
        latestWorld = world
        latestBooks = books
    }

    func stop() {
        autonomyTask?.cancel()
        autonomyTask = nil
        decisionTask?.cancel()
        decisionTask = nil
    }

    func react(
        to trigger: KokoTrigger,
        world: HomeWorldState,
        books: [Book],
        prefersAI: Bool
    ) {
        latestWorld = world
        latestBooks = books
        let perception = makePerception(trigger: trigger, world: world, books: books)
        let fallback = KokoDecision.localFallback(for: perception)
        apply(fallback, trigger: trigger)

        guard prefersAI,
              UserDefaults.standard.bool(forKey: "ai.enabled"),
              let key = KeychainStore.read(account: AICompanionStore.keyAccount)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty,
              trigger != .periodic || lastAIRequestAt.map({ Date().timeIntervalSince($0) > 150 }) != false
        else { return }

        decisionTask?.cancel()
        decisionTask = Task { [weak self] in
            guard let self else { return }
            self.isThinking = true
            defer { self.isThinking = false }
            do {
                let model = AIModelChoice(
                    rawValue: UserDefaults.standard.string(forKey: "ai.model") ?? ""
                ) ?? .pro
                let allowsCellular = UserDefaults.standard.object(forKey: "ai.allowsCellular") as? Bool ?? true
                let generated = try await DeepSeekService.shared.kokoDecision(
                    apiKey: key,
                    perception: perception,
                    model: model,
                    allowsCellularAccess: allowsCellular
                )
                guard !Task.isCancelled else { return }
                self.lastAIRequestAt = .now
                self.errorMessage = nil
                self.apply(generated, trigger: trigger)
            } catch is CancellationError {
                return
            } catch {
                self.errorMessage = "可可今天稍微安静一点，但她仍会在家里正常活动。"
            }
        }
    }

    func send(_ text: String, world: HomeWorldState, books: [Book]) async {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !isReplying else { return }
        conversation.append(AIChatMessage(role: .user, text: cleaned))
        conversation = Array(conversation.suffix(24))
        react(to: .conversation, world: world, books: books, prefersAI: false)

        guard UserDefaults.standard.bool(forKey: "ai.enabled"),
              let key = KeychainStore.read(account: AICompanionStore.keyAccount)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else {
            conversation.append(AIChatMessage(
                role: .companion,
                text: "我听到了。现在云端陪伴没有开启，我先安静陪你在这里待一会儿。"
            ))
            return
        }

        isReplying = true
        errorMessage = nil
        defer { isReplying = false }
        do {
            let model = AIModelChoice(
                rawValue: UserDefaults.standard.string(forKey: "ai.model") ?? ""
            ) ?? .pro
            let allowsCellular = UserDefaults.standard.object(forKey: "ai.allowsCellular") as? Bool ?? true
            let perception = makePerception(trigger: .conversation, world: world, books: books)
            let reply = try await DeepSeekService.shared.kokoReply(
                apiKey: key,
                message: cleaned,
                perception: perception,
                conversation: conversation,
                model: model,
                allowsCellularAccess: allowsCellular
            )
            conversation.append(AIChatMessage(role: .companion, text: reply))
            conversation = Array(conversation.suffix(24))
        } catch {
            errorMessage = error.localizedDescription
            conversation.append(AIChatMessage(
                role: .companion,
                text: "刚才的话没能顺利送到云端。你说的我先记下了，等网络恢复后可以再试一次。"
            ))
        }
    }

    func clearConversation() {
        conversation = []
    }

    private func makePerception(trigger: KokoTrigger, world: HomeWorldState, books: [Book]) -> KokoPerception {
        let localHour = Calendar.current.component(.hour, from: .now)
        innerState.refresh(localHour: localHour)
        let furniture = world.placements.compactMap(\.furniture).map(\.title)
        let candidates = books
            .sorted { ($0.lastOpenedAt ?? $0.importedAt) > ($1.lastOpenedAt ?? $1.importedAt) }
            .prefix(16)
            .map {
                KokoBookCandidate(
                    id: $0.id,
                    title: $0.title,
                    progress: $0.progress,
                    isFavorite: $0.isFavorite,
                    lastOpenedAt: $0.lastOpenedAt
                )
            }
        let memoryNotes = memories.suffix(10).map { memory in
            "\(memory.action.title)：\(memory.note)"
        }
        return KokoPerception(
            trigger: trigger,
            localHour: localHour,
            roomTheme: world.theme,
            furnitureNames: furniture,
            books: candidates,
            displayedBookIDs: world.placements.compactMap(\.bookID),
            recentMemories: memoryNotes,
            recentActions: memories.suffix(8).map(\.action),
            innerState: innerState
        )
    }

    private func apply(_ newDecision: KokoDecision, trigger: KokoTrigger) {
        decision = newDecision
        decisionRevision &+= 1
        if newDecision.generatedByAI,
           let last = memories.last,
           last.trigger == trigger,
           Date().timeIntervalSince(last.createdAt) < 12 {
            memories.removeLast()
        } else {
            innerState.apply(
                newDecision.action,
                localHour: Calendar.current.component(.hour, from: .now)
            )
        }
        memories.append(KokoMemory(
            trigger: trigger,
            action: newDecision.action,
            bookID: newDecision.targetBookID,
            note: newDecision.innerThought
        ))
        memories = Array(memories.suffix(40))
        saveAgentState()
    }

    private func saveAgentState() {
        do {
            try fileManager.createDirectory(at: memoryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(memories).write(to: memoryURL, options: .atomic)
            try encoder.encode(innerState).write(to: innerStateURL, options: .atomic)
        } catch {
            errorMessage = "可可的本地记忆没有保存好：\(error.localizedDescription)"
        }
    }

    private static func loadMemories(from url: URL) -> [KokoMemory] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([KokoMemory].self, from: data)).map { Array($0.suffix(40)) } ?? []
    }

    private static func loadInnerState(from url: URL) -> KokoInnerState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(KokoInnerState.self, from: data)
    }
}
