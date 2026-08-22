import Foundation

enum BookMood: String, CaseIterable, Codable, Identifiable, Sendable {
    case sweet
    case teasing
    case glamorous
    case intimate
    case thrilling
    case artful

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sweet: "甜欲心动"
        case .teasing: "暧昧拉扯"
        case .glamorous: "姐姐气场"
        case .intimate: "亲密治愈"
        case .thrilling: "大胆刺激"
        case .artful: "作画盛宴"
        }
    }

    var shortTitle: String {
        switch self {
        case .sweet: "甜欲"
        case .teasing: "暧昧"
        case .glamorous: "姐姐"
        case .intimate: "亲密"
        case .thrilling: "大胆"
        case .artful: "作画"
        }
    }

    var systemImage: String {
        switch self {
        case .sweet: "heart.fill"
        case .teasing: "sparkles"
        case .glamorous: "crown.fill"
        case .intimate: "moon.stars.fill"
        case .thrilling: "flame.fill"
        case .artful: "paintpalette.fill"
        }
    }

    var invitation: String {
        switch self {
        case .sweet: "今晚适合一点直白的心动"
        case .teasing: "不说破的距离，反而最让人在意"
        case .glamorous: "把目光交给从容、自信的成熟魅力"
        case .intimate: "慢一点，留在温柔又亲密的氛围里"
        case .thrilling: "挑一本构图大胆、张力拉满的作品"
        case .artful: "先不谈剧情，只好好欣赏线条与色彩"
        }
    }
}

enum AfterDarkTagCatalog {
    static let suggestions = [
        "御姐", "成熟系", "姐姐感", "魅惑", "暧昧", "亲密",
        "大胆构图", "丝袜", "泳装", "睡衣", "角色魅力", "神级作画"
    ]
}

struct NightReadingPrompt: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String

    static let collection: [NightReadingPrompt] = [
        .init(id: "first-look", title: "只凭第一眼", subtitle: "抽一本书，先看三页再决定要不要留下", systemImage: "eyes"),
        .init(id: "favorite-line", title: "寻找心动线条", subtitle: "收藏一页最喜欢的构图或姿态", systemImage: "heart.circle.fill"),
        .init(id: "aftertaste", title: "读完留一句", subtitle: "在作品档案里写下今晚的余韵", systemImage: "quote.bubble.fill"),
        .init(id: "no-rush", title: "慢速夜读", subtitle: "关掉弹幕十分钟，只看画面和细节", systemImage: "moon.zzz.fill")
    ]
}
