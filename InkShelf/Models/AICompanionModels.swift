import Foundation

enum AIModelChoice: String, CaseIterable, Identifiable, Codable, Sendable {
    case flash
    case pro

    var id: String { rawValue }
    var modelID: String { self == .flash ? "deepseek-v4-flash" : "deepseek-v4-pro" }
    var title: String { self == .flash ? "V4 Flash" : "V4 Pro" }
    var detail: String { self == .flash ? "翻页更快、费用更低" : "评论更细腻、响应稍慢" }
}

enum AIWritingPurpose: String, CaseIterable, Identifiable, Codable, Sendable {
    case synopsis
    case recommendation
    case socialShare
    case reflection
    case titleIdeas
    case keepsake

    var id: String { rawValue }

    var title: String {
        switch self {
        case .synopsis: "画集简介"
        case .recommendation: "推荐文案"
        case .socialShare: "分享配文"
        case .reflection: "阅读感想"
        case .titleIdeas: "标题灵感"
        case .keepsake: "珍藏寄语"
        }
    }

    var systemImage: String {
        switch self {
        case .synopsis: "text.book.closed.fill"
        case .recommendation: "hand.thumbsup.fill"
        case .socialShare: "square.and.arrow.up.fill"
        case .reflection: "quote.bubble.fill"
        case .titleIdeas: "lightbulb.fill"
        case .keepsake: "heart.text.square.fill"
        }
    }

    var promptDescription: String {
        switch self {
        case .synopsis: "写一段清楚、有画面感的内容简介，不编造未提供的信息"
        case .recommendation: "写一段真诚、有吸引力但不过度营销的推荐文案"
        case .socialShare: "写适合社交平台发布的轻松配文，可带少量自然的 emoji"
        case .reflection: "写一段有个人温度、像真实读者写下的阅读感想"
        case .titleIdeas: "给出 8 个风格各异、简短好记的标题，并各附一句说明"
        case .keepsake: "写一段温暖克制、适合留在私人收藏中的珍藏寄语"
        }
    }
}

enum AICompanionPersona: String, CaseIterable, Identifiable, Codable, Sendable {
    case friend
    case otaku
    case analyst
    case gentle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .friend: "同好朋友"
        case .otaku: "资深二次元"
        case .analyst: "细节观察员"
        case .gentle: "安静陪伴"
        }
    }

    var systemImage: String {
        switch self {
        case .friend: "person.2.fill"
        case .otaku: "sparkles"
        case .analyst: "eye.fill"
        case .gentle: "moon.stars.fill"
        }
    }

    var promptDescription: String {
        switch self {
        case .friend: "像熟悉我的同好朋友，反应自然、有共鸣，偶尔幽默"
        case .otaku: "像资深动漫爱好者，懂常见叙事套路和二次元表达，但不卖弄术语"
        case .analyst: "关注构图、台词、伏笔和人物情绪，表达简洁清楚"
        case .gentle: "温柔克制，少量弹幕，不打断沉浸感，更多给予情绪陪伴"
        }
    }
}

enum AIDanmakuDensity: String, CaseIterable, Identifiable, Codable, Sendable {
    case quiet
    case balanced
    case lively

    var id: String { rawValue }
    var title: String {
        switch self {
        case .quiet: "清静"
        case .balanced: "适中"
        case .lively: "热闹"
        }
    }
    var messageCount: Int {
        switch self {
        case .quiet: 3
        case .balanced: 6
        case .lively: 10
        }
    }
}

enum AIDanmakuTone: String, Codable, Sendable {
    case normal
    case excited
    case amused
    case touched
    case curious
}

struct AIPageInsight: Codable, Hashable, Sendable {
    let page: Int
    let pageCount: Int
    let recognizedText: String
    let visualLabels: [String]
    let faceCount: Int
    let sourceKind: String

    var isSparse: Bool {
        recognizedText.isEmpty && visualLabels.isEmpty && faceCount == 0
    }
}

struct AIDanmakuMessage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let text: String
    let tone: AIDanmakuTone

    init(id: UUID = UUID(), text: String, tone: AIDanmakuTone = .normal) {
        self.id = id
        self.text = text
        self.tone = tone
    }
}

enum AITranslationRole: String, Codable, Sendable {
    case dialogue
    case narration
    case soundEffect = "sound_effect"
    case other

    var title: String {
        switch self {
        case .dialogue: "对白"
        case .narration: "旁白"
        case .soundEffect: "拟声"
        case .other: "文字"
        }
    }
}

struct AITranslationSegment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let source: String
    let translation: String
    let role: AITranslationRole
    let speaker: String?

    init(
        id: UUID = UUID(),
        source: String,
        translation: String,
        role: AITranslationRole,
        speaker: String? = nil
    ) {
        self.id = id
        self.source = source
        self.translation = translation
        self.role = role
        self.speaker = speaker
    }
}

struct AIPageTranslation: Codable, Hashable, Sendable {
    let detectedJapanese: Bool
    let title: String
    let segments: [AITranslationSegment]
    let note: String?
}

enum AIReactionSource: String, Codable, Sendable {
    case deepSeek
    case localFallback
}

struct AIPageReaction: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let page: Int
    let summary: String
    let mood: String
    let danmaku: [AIDanmakuMessage]
    let talkingPoints: [String]
    let translation: AIPageTranslation?
    let source: AIReactionSource?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        page: Int,
        summary: String,
        mood: String,
        danmaku: [AIDanmakuMessage],
        talkingPoints: [String],
        translation: AIPageTranslation? = nil,
        source: AIReactionSource = .deepSeek,
        createdAt: Date = .now
    ) {
        self.id = id
        self.page = page
        self.summary = summary
        self.mood = mood
        self.danmaku = danmaku
        self.talkingPoints = talkingPoints
        self.translation = translation
        self.source = source
        self.createdAt = createdAt
    }

    var isLocalFallback: Bool { source == .localFallback }
}

struct AISimulatedComment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let username: String
    let avatarEmoji: String
    let body: String
    let likes: Int
    let badge: String?

    init(
        id: UUID = UUID(),
        username: String,
        avatarEmoji: String,
        body: String,
        likes: Int,
        badge: String? = nil
    ) {
        self.id = id
        self.username = username
        self.avatarEmoji = avatarEmoji
        self.body = body
        self.likes = likes
        self.badge = badge
    }
}

struct AIEndDiscussion: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let title: String
    let closingNote: String
    let comments: [AISimulatedComment]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        closingNote: String,
        comments: [AISimulatedComment],
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.closingNote = closingNote
        self.comments = comments
        self.createdAt = createdAt
    }
}

struct AIChatMessage: Identifiable, Hashable, Sendable {
    enum Role: Sendable { case user, companion }

    let id: UUID
    let role: Role
    let text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

enum AICompanionActivity: Equatable {
    case idle
    case readingPage(Int)
    case generatingDiscussion
    case answering

    var isBusy: Bool { self != .idle }
}
