import Foundation

struct SocialPostImage: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let url: URL
    let width: Int
    let height: Int
    let format: String
    let altText: String?

    enum CodingKeys: String, CodingKey {
        case id, url, width, height, format
        case altText = "alt_text"
    }

    var previewURL: URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host?.lowercased() == "pbs.twimg.com"
        else { return url }
        var items = components.queryItems ?? []
        items.removeAll { $0.name.lowercased() == "name" }
        items.append(URLQueryItem(name: "name", value: "small"))
        components.queryItems = items
        return components.url ?? url
    }
}

struct SocialPostPreview: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let postURL: URL
    let authorName: String
    let username: String
    let text: String
    let images: [SocialPostImage]

    enum CodingKeys: String, CodingKey {
        case id = "post_id"
        case postURL = "post_url"
        case authorName = "author_name"
        case username, text, images
    }

    var suggestedTitle: String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = String(cleaned.prefix(28))
        return excerpt.isEmpty ? "@\(username) 的图片" : "@\(username) · \(excerpt)"
    }
}

struct SocialPostDownload: Sendable {
    let temporaryRoot: URL
    let galleryFolder: URL
}
