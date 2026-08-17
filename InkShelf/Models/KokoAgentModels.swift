import Foundation

enum KokoAction: String, CaseIterable, Codable, Sendable {
    case greet
    case stroll
    case admireBook
    case read
    case tidy
    case lookOutWindow
    case sit
    case rest
    case wave

    var title: String {
        switch self {
        case .greet: "迎接你回家"
        case .stroll: "在屋里散步"
        case .admireBook: "欣赏画集"
        case .read: "安静看书"
        case .tidy: "整理房间"
        case .lookOutWindow: "去窗边发呆"
        case .sit: "坐下陪伴"
        case .rest: "稍微休息"
        case .wave: "向你挥手"
        }
    }
}

enum KokoTrigger: String, Codable, Sendable {
    case enteredHome
    case tapped
    case roomChanged
    case bookPlaced
    case periodic
    case conversation
}

struct KokoBookCandidate: Codable, Hashable, Sendable {
    let id: UUID
    let title: String
    let progress: Double
    let isFavorite: Bool
    let lastOpenedAt: Date?
}

struct KokoPerception: Codable, Hashable, Sendable {
    let trigger: KokoTrigger
    let localHour: Int
    let roomTheme: HomeRoomTheme
    let furnitureNames: [String]
    let books: [KokoBookCandidate]
    let displayedBookIDs: [UUID]
    let recentMemories: [String]
}

struct KokoDecision: Codable, Hashable, Sendable {
    let action: KokoAction
    let targetBookID: UUID?
    let phrase: String
    let innerThought: String
    let duration: TimeInterval
    let generatedByAI: Bool

    init(
        action: KokoAction,
        targetBookID: UUID? = nil,
        phrase: String,
        innerThought: String,
        duration: TimeInterval = 12,
        generatedByAI: Bool = false
    ) {
        self.action = action
        self.targetBookID = targetBookID
        self.phrase = String(phrase.prefix(80))
        self.innerThought = String(innerThought.prefix(120))
        self.duration = min(max(duration, 4), 45)
        self.generatedByAI = generatedByAI
    }
}

struct KokoMemory: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let trigger: KokoTrigger
    let action: KokoAction
    let bookID: UUID?
    let note: String

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        trigger: KokoTrigger,
        action: KokoAction,
        bookID: UUID? = nil,
        note: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.trigger = trigger
        self.action = action
        self.bookID = bookID
        self.note = String(note.prefix(160))
    }
}

extension KokoDecision {
    static func localFallback(for perception: KokoPerception) -> KokoDecision {
        let recentlyOpened = perception.books
            .filter { $0.lastOpenedAt != nil }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .first
        let favorite = perception.books.first(where: \.isFavorite)

        switch perception.trigger {
        case .enteredHome:
            if perception.localHour >= 22 || perception.localHour < 6 {
                return KokoDecision(
                    action: .greet,
                    phrase: "你回来啦。我把灯调暗了一点，今晚慢慢看就好。",
                    innerThought: "夜深了，想让家里保持安静。"
                )
            }
            return KokoDecision(
                action: .greet,
                phrase: "欢迎回家。你的位置和书，我都好好留着。",
                innerThought: "想先让他放松下来。"
            )
        case .tapped:
            return KokoDecision(
                action: .wave,
                phrase: "我在呢。今天想一起看哪本？",
                innerThought: "他在找我，回应得轻一点。",
                duration: 9
            )
        case .bookPlaced:
            return KokoDecision(
                action: .admireBook,
                targetBookID: recentlyOpened?.id ?? favorite?.id,
                phrase: "放在这里很好看。这个角落一下子有了你的气息。",
                innerThought: "新的收藏值得好好看一看。"
            )
        case .roomChanged:
            return KokoDecision(
                action: .tidy,
                phrase: "新布置很温柔。我再帮你看看有没有挡路的地方。",
                innerThought: "房间变了，先熟悉新的走动路线。"
            )
        case .periodic:
            if perception.localHour >= 20 || perception.localHour < 6 {
                return KokoDecision(
                    action: .lookOutWindow,
                    phrase: "窗外很安静。不用赶，这里的时间可以慢一点。",
                    innerThought: "在夜色里安静待一会儿。",
                    duration: 18
                )
            }
            if let book = recentlyOpened ?? favorite {
                return KokoDecision(
                    action: .read,
                    targetBookID: book.id,
                    phrase: "我想再翻翻《\(book.title)》。你之前停留的地方，好像很喜欢。",
                    innerThought: "想从他的阅读痕迹里理解他喜欢什么。",
                    duration: 22
                )
            }
            return KokoDecision(
                action: .stroll,
                phrase: "我先在屋里走走，等你挑好今天的画集。",
                innerThought: "屋里很安静，走一走也很舒服。"
            )
        case .conversation:
            return KokoDecision(
                action: .sit,
                phrase: "我在听。你可以慢慢说。",
                innerThought: "先安静陪在旁边。",
                duration: 16
            )
        }
    }
}
