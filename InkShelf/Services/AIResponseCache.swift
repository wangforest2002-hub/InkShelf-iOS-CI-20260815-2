import Foundation

actor AIResponseCache {
    static let shared = AIResponseCache()

    private let folder: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        folder = root.appendingPathComponent("InkShelf AI", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func pageReaction(bookID: UUID, page: Int, variant: String) -> AIPageReaction? {
        load(AIPageReaction.self, from: pageURL(bookID: bookID, page: page, variant: variant))
    }

    func save(_ reaction: AIPageReaction, bookID: UUID, variant: String) {
        save(reaction, to: pageURL(bookID: bookID, page: reaction.page, variant: variant))
    }

    func endDiscussion(bookID: UUID, variant: String) -> AIEndDiscussion? {
        load(AIEndDiscussion.self, from: endURL(bookID: bookID, variant: variant))
    }

    func save(_ discussion: AIEndDiscussion, bookID: UUID, variant: String) {
        save(discussion, to: endURL(bookID: bookID, variant: variant))
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func pageURL(bookID: UUID, page: Int, variant: String) -> URL {
        folder.appendingPathComponent("\(bookID.uuidString)-p\(page)-\(variant).json")
    }

    private func endURL(bookID: UUID, variant: String) -> URL {
        folder.appendingPathComponent("\(bookID.uuidString)-end-\(variant).json")
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
