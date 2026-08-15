import Foundation

struct ShelfGroup: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    let styleIndex: Int

    init(id: UUID = UUID(), title: String, createdAt: Date = .now, styleIndex: Int = 0) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.styleIndex = styleIndex
    }

    var systemImage: String {
        let symbols = ["folder.fill", "sparkles.rectangle.stack.fill", "heart.rectangle.fill", "moon.stars.fill", "leaf.fill"]
        return symbols[abs(styleIndex) % symbols.count]
    }
}
