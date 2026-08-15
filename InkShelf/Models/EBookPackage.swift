import Foundation

enum EBookFormat: String, Codable, Sendable {
    case epub = "EPUB"
    case text = "TXT"
    case html = "HTML"
    case markdown = "Markdown"
    case rtf = "RTF"
    case fictionBook = "FB2"
}

struct EBookChapter: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let relativePath: String
    let searchText: String
}

struct EBookPackage: Codable, Hashable, Sendable {
    let title: String
    let author: String?
    let format: EBookFormat
    let chapters: [EBookChapter]
    let resourceRootRelativePath: String

    func chapterURL(at index: Int, packageURL: URL) -> URL? {
        guard chapters.indices.contains(index) else { return nil }
        let root = packageURL.deletingLastPathComponent().appendingPathComponent(resourceRootRelativePath, isDirectory: true)
        return root.appendingPathComponent(chapters[index].relativePath).standardizedFileURL
    }

    func resourceRootURL(packageURL: URL) -> URL {
        packageURL.deletingLastPathComponent().appendingPathComponent(resourceRootRelativePath, isDirectory: true)
    }
}

struct EBookSearchResult: Identifiable, Hashable {
    let chapterIndex: Int
    let chapterTitle: String
    let excerpt: String
    var id: String { "\(chapterIndex)-\(excerpt)" }
}
