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
    case returnedFromReading
    case periodic
    case conversation
}

enum KokoMood: String, Codable, Sendable {
    case cheerful
    case calm
    case curious
    case focused
    case sleepy

    var title: String {
        switch self {
        case .cheerful: "开心"
        case .calm: "安宁"
        case .curious: "好奇"
        case .focused: "专注"
        case .sleepy: "有点困"
        }
    }
}

struct KokoInnerState: Codable, Hashable, Sendable {
    static let currentSchema = 1

    var schema: Int
    var mood: KokoMood
    var energy: Double
    var curiosity: Double
    var socialNeed: Double
    var orderNeed: Double
    var updatedAt: Date

    init(
        schema: Int = KokoInnerState.currentSchema,
        mood: KokoMood = .calm,
        energy: Double = 0.72,
        curiosity: Double = 0.64,
        socialNeed: Double = 0.36,
        orderNeed: Double = 0.30,
        updatedAt: Date = .now
    ) {
        self.schema = schema
        self.mood = mood
        self.energy = energy
        self.curiosity = curiosity
        self.socialNeed = socialNeed
        self.orderNeed = orderNeed
        self.updatedAt = updatedAt
        clamp()
    }

    mutating func refresh(at date: Date = .now, localHour: Int) {
        let elapsedHours = min(max(date.timeIntervalSince(updatedAt) / 3_600, 0), 24)
        curiosity += elapsedHours * 0.025
        socialNeed += elapsedHours * 0.018
        orderNeed += elapsedHours * 0.012
        if localHour >= 23 || localHour < 6 {
            energy -= elapsedHours * 0.045
        } else {
            energy += elapsedHours * 0.018
        }
        updatedAt = date
        updateMood(localHour: localHour)
        clamp()
    }

    mutating func apply(_ action: KokoAction, at date: Date = .now, localHour: Int) {
        switch action {
        case .greet, .wave:
            socialNeed -= 0.24
            energy -= 0.025
        case .stroll:
            curiosity -= 0.08
            energy -= 0.09
        case .admireBook:
            curiosity -= 0.18
            energy -= 0.035
        case .read:
            curiosity -= 0.26
            energy -= 0.10
        case .tidy:
            orderNeed -= 0.42
            energy -= 0.12
        case .lookOutWindow, .sit:
            socialNeed -= action == .sit ? 0.16 : 0.04
            energy += 0.06
        case .rest:
            energy += 0.30
        }
        updatedAt = date
        updateMood(localHour: localHour)
        clamp()
    }

    private mutating func updateMood(localHour: Int) {
        if energy < 0.28 || ((localHour >= 23 || localHour < 6) && energy < 0.48) {
            mood = .sleepy
        } else if curiosity > 0.70 {
            mood = .curious
        } else if orderNeed > 0.72 {
            mood = .focused
        } else if socialNeed < 0.24 {
            mood = .cheerful
        } else {
            mood = .calm
        }
    }

    private mutating func clamp() {
        schema = Self.currentSchema
        energy = min(max(energy, 0), 1)
        curiosity = min(max(curiosity, 0), 1)
        socialNeed = min(max(socialNeed, 0), 1)
        orderNeed = min(max(orderNeed, 0), 1)
    }
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
    let recentActions: [KokoAction]
    let innerState: KokoInnerState
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
        let lastAction = perception.recentActions.last

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
        case .returnedFromReading:
            if let book = recentlyOpened {
                return KokoDecision(
                    action: .sit,
                    targetBookID: book.id,
                    phrase: "看完一会儿啦。《\(book.title)》先替你放在手边。",
                    innerThought: "他刚从阅读里回来，留一点安静的余韵。",
                    duration: 16
                )
            }
            return KokoDecision(
                action: .sit,
                phrase: "回来啦。我们先让眼睛休息一下。",
                innerThought: "阅读告一段落，安静陪他休息。",
                duration: 15
            )
        case .roomChanged:
            return KokoDecision(
                action: .tidy,
                phrase: "新布置很温柔。我再帮你看看有没有挡路的地方。",
                innerThought: "房间变了，先熟悉新的走动路线。"
            )
        case .periodic:
            if perception.innerState.energy < 0.28 {
                return KokoDecision(
                    action: .rest,
                    phrase: "我先靠一会儿。屋里的灯光让人很安心。",
                    innerThought: "有点困了，先恢复一点精神。",
                    duration: 24
                )
            }
            if perception.innerState.orderNeed > 0.72, lastAction != .tidy {
                return KokoDecision(
                    action: .tidy,
                    phrase: "我把刚才挪动过的角落顺手整理一下。",
                    innerThought: "房间需要恢复整洁，走动也会更舒服。",
                    duration: 18
                )
            }
            if perception.innerState.socialNeed > 0.76, lastAction != .sit {
                return KokoDecision(
                    action: .sit,
                    phrase: "我来这边坐一会儿。你看你的书就好。",
                    innerThought: "想靠近一点，但不打扰阅读。",
                    duration: 22
                )
            }
            if perception.localHour >= 20 || perception.localHour < 6 {
                return KokoDecision(
                    action: .lookOutWindow,
                    phrase: "窗外很安静。不用赶，这里的时间可以慢一点。",
                    innerThought: "在夜色里安静待一会儿。",
                    duration: 18
                )
            }
            if let book = recentlyOpened ?? favorite,
               (perception.innerState.curiosity > 0.52 || lastAction != .read) {
                return KokoDecision(
                    action: .read,
                    targetBookID: book.id,
                    phrase: "我想再翻翻《\(book.title)》。你之前停留的地方，好像很喜欢。",
                    innerThought: "想从他的阅读痕迹里理解他喜欢什么。",
                    duration: 22
                )
            }
            if lastAction == .stroll {
                return KokoDecision(
                    action: .lookOutWindow,
                    phrase: "走到窗边时，正好想看看今天的光。",
                    innerThought: "散步后在窗边停留片刻。",
                    duration: 17
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
