import Foundation
import UIKit

enum EBookImportError: LocalizedError {
    case invalidEPUB
    case emptyBook
    case bookTooLarge
    case unreadableText
    case invalidFictionBook

    var errorDescription: String? {
        switch self {
        case .invalidEPUB: return "EPUB 结构不完整或文件已损坏。"
        case .emptyBook: return "电子书中没有可阅读的章节。"
        case .bookTooLarge: return "电子书展开后过大，已停止导入以保护设备存储空间。"
        case .unreadableText: return "无法识别这个文本文件的编码。"
        case .invalidFictionBook: return "FB2 文件结构不完整或已损坏。"
        }
    }
}

enum EBookImporter {
    static let supportedExtensions: Set<String> = ["epub", "txt", "text", "html", "htm", "md", "markdown", "rtf", "fb2"]

    static func importBook(_ sourceURL: URL, into libraryURL: URL) throws -> (Book, URL) {
        let fileManager = FileManager.default
        let id = UUID()
        let folder = libraryURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        let publicationFolder = folder.appendingPathComponent("publication", isDirectory: true)
        try fileManager.createDirectory(at: publicationFolder, withIntermediateDirectories: true)

        do {
            let ext = sourceURL.pathExtension.lowercased()
            let sourceName = ext.isEmpty ? "source" : "source.\(ext)"
            let copiedSource = folder.appendingPathComponent(sourceName)
            try ExternalFileAccess.copyItem(from: sourceURL, to: copiedSource)

            let generated: GeneratedEBook
            switch ext {
            case "epub":
                let parsed = try EPUBParser.parse(archiveURL: copiedSource, extractionRoot: publicationFolder)
                generated = GeneratedEBook(package: parsed.package, coverURL: parsed.coverURL)
            case "txt", "text":
                generated = try importPlainText(copiedSource, title: sourceURL.deletingPathExtension().lastPathComponent, into: publicationFolder)
            case "html", "htm":
                generated = try importHTML(copiedSource, title: sourceURL.deletingPathExtension().lastPathComponent, into: publicationFolder)
            case "md", "markdown":
                generated = try importMarkdown(copiedSource, title: sourceURL.deletingPathExtension().lastPathComponent, into: publicationFolder)
            case "rtf":
                generated = try importRTF(copiedSource, title: sourceURL.deletingPathExtension().lastPathComponent, into: publicationFolder)
            case "fb2":
                generated = try importFictionBook(copiedSource, fallbackTitle: sourceURL.deletingPathExtension().lastPathComponent, into: publicationFolder)
            default:
                throw BookImportError.unsupportedFile(sourceURL.lastPathComponent)
            }

            let packageURL = folder.appendingPathComponent("ebook.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(generated.package).write(to: packageURL, options: .atomic)

            let previewNames = generated.coverURL.map {
                CoverService.createImagePreviews(sourceURLs: [$0], in: folder)
            } ?? []
            let previewPaths = previewNames.map { "\(id.uuidString.lowercased())/\($0)" }
            let title = generated.package.title.trimmingCharacters(in: .whitespacesAndNewlines)
            // ebook.json and publication contain everything the reader needs.
            // The selected source remains in Files/iCloud, so the copied
            // container is redundant once conversion has succeeded.
            try fileManager.removeItem(at: copiedSource)
            let book = Book(
                id: id,
                title: title.isEmpty ? sourceURL.deletingPathExtension().lastPathComponent : title,
                kind: .ebook,
                sourceFileName: sourceURL.lastPathComponent,
                contentRelativePath: "\(id.uuidString.lowercased())/ebook.json",
                sourceRelativePath: nil,
                coverRelativePath: previewPaths.first,
                previewRelativePaths: previewPaths,
                pageCount: generated.package.chapters.count,
                fileSize: folderSize(of: folder),
                ebookChapterProgress: 0
            )
            return (book, folder)
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
    }

    private static func importPlainText(_ url: URL, title: String, into folder: URL) throws -> GeneratedEBook {
        let text = try decodedText(at: url)
        let html = documentHTML(title: title, body: paragraphsHTML(text))
        return try writeSingleChapter(html: html, searchText: normalizedSearchText(text), title: title, format: .text, into: folder)
    }

    private static func importHTML(_ url: URL, title: String, into folder: URL) throws -> GeneratedEBook {
        let html = try decodedText(at: url)
        let searchText = HTMLTextExtractor.extract(html)
        let destination = folder.appendingPathComponent("content.html")
        try Data(html.utf8).write(to: destination, options: .atomic)
        return GeneratedEBook(
            package: singleChapterPackage(title: title, format: .html, searchText: searchText),
            coverURL: nil
        )
    }

    private static func importMarkdown(_ url: URL, title: String, into folder: URL) throws -> GeneratedEBook {
        let markdown = try decodedText(at: url)
        let html = documentHTML(title: title, body: MarkdownRenderer.render(markdown))
        return try writeSingleChapter(html: html, searchText: normalizedSearchText(markdown), title: title, format: .markdown, into: folder)
    }

    private static func importRTF(_ url: URL, title: String, into folder: URL) throws -> GeneratedEBook {
        let data = try Data(contentsOf: url)
        let attributed = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        let htmlData = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        )
        guard let html = String(data: htmlData, encoding: .utf8) else { throw EBookImportError.unreadableText }
        return try writeSingleChapter(html: html, searchText: normalizedSearchText(attributed.string), title: title, format: .rtf, into: folder)
    }

    private static func importFictionBook(_ url: URL, fallbackTitle: String, into folder: URL) throws -> GeneratedEBook {
        let parser = FictionBookParser(resourceFolder: folder)
        try parser.parse(url: url)
        let title = parser.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackTitle : parser.title
        let html = documentHTML(title: title, body: parser.renderedBody)
        return try writeSingleChapter(
            html: html,
            searchText: normalizedSearchText(parser.searchText),
            title: title,
            author: parser.author.nilIfBlank,
            format: .fictionBook,
            coverURL: parser.coverURL,
            into: folder
        )
    }

    private static func writeSingleChapter(
        html: String,
        searchText: String,
        title: String,
        author: String? = nil,
        format: EBookFormat,
        coverURL: URL? = nil,
        into folder: URL
    ) throws -> GeneratedEBook {
        try Data(html.utf8).write(to: folder.appendingPathComponent("content.html"), options: .atomic)
        return GeneratedEBook(
            package: EBookPackage(
                title: title,
                author: author,
                format: format,
                chapters: [EBookChapter(id: "content", title: title, relativePath: "content.html", searchText: String(searchText.prefix(500_000)))],
                resourceRootRelativePath: "publication"
            ),
            coverURL: coverURL
        )
    }

    private static func singleChapterPackage(title: String, format: EBookFormat, searchText: String) -> EBookPackage {
        EBookPackage(
            title: title,
            author: nil,
            format: format,
            chapters: [EBookChapter(id: "content", title: title, relativePath: "content.html", searchText: String(searchText.prefix(500_000)))],
            resourceRootRelativePath: "publication"
        )
    }

    private static func decodedText(at url: URL) throws -> String {
        let encodings: [String.Encoding] = [
            .utf8, .utf16, .utf16LittleEndian, .utf16BigEndian,
            String.Encoding(rawValue: 0x8000_0632), .isoLatin1
        ]
        for encoding in encodings {
            if let value = try? String(contentsOf: url, encoding: encoding), !value.isEmpty { return value }
        }
        throw EBookImportError.unreadableText
    }

    private static func paragraphsHTML(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { line in
                let value = escapeHTML(line.trimmingCharacters(in: .whitespaces))
                return value.isEmpty ? "<p><br></p>" : "<p>\(value)</p>"
            }
            .joined(separator: "\n")
    }

    private static func documentHTML(title: String, body: String) -> String {
        """
        <!doctype html><html lang="zh-Hans"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"><title>\(escapeHTML(title))</title></head><body>\(body)</body></html>
        """
    }

    fileprivate static func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func normalizedSearchText(_ value: String) -> String {
        value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fileSize(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private static func folderSize(of folder: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }
}

private struct GeneratedEBook {
    let package: EBookPackage
    let coverURL: URL?
}

private enum HTMLTextExtractor {
    static func extract(_ html: String) -> String {
        html.replacingOccurrences(of: "(?is)<script.*?</script>|<style.*?</style>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum MarkdownRenderer {
    static func render(_ source: String) -> String {
        var output: [String] = []
        var inCode = false
        var inList = false
        for rawLine in source.components(separatedBy: "\n") {
            if rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inList { output.append("</ul>"); inList = false }
                output.append(inCode ? "</code></pre>" : "<pre><code>")
                inCode.toggle()
                continue
            }
            if inCode {
                output.append(EBookImporter.escapeHTML(rawLine) + "\n")
                continue
            }

            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !inList { output.append("<ul>"); inList = true }
                output.append("<li>\(inline(String(line.dropFirst(2))))</li>")
                continue
            }
            if inList { output.append("</ul>"); inList = false }
            if line.isEmpty { output.append("<p><br></p>"); continue }

            let hashes = line.prefix { $0 == "#" }.count
            if hashes > 0, hashes <= 6, line.dropFirst(hashes).first == " " {
                output.append("<h\(hashes)>\(inline(String(line.dropFirst(hashes + 1))))</h\(hashes)>")
            } else if line.hasPrefix("> ") {
                output.append("<blockquote>\(inline(String(line.dropFirst(2))))</blockquote>")
            } else {
                output.append("<p>\(inline(line))</p>")
            }
        }
        if inList { output.append("</ul>") }
        if inCode { output.append("</code></pre>") }
        return output.joined(separator: "\n")
    }

    private static func inline(_ value: String) -> String {
        EBookImporter.escapeHTML(value)
            .replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
            .replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)
            .replacingOccurrences(of: "\\*([^*]+)\\*", with: "<em>$1</em>", options: .regularExpression)
    }
}

private final class FictionBookParser: NSObject, XMLParserDelegate {
    let resourceFolder: URL
    var title = ""
    var author = ""
    var renderedBody = ""
    var searchText = ""
    var coverURL: URL?

    private var stack: [String] = []
    private var binaries: [String: (mime: String, data: String)] = [:]
    private var binaryID: String?
    private var binaryMime = "image/jpeg"
    private var binaryBuffer = ""
    private var coverReference: String?
    private var inMainBody = false
    private var inDescription = false
    private var metadataBuffer = ""

    init(resourceFolder: URL) {
        self.resourceFolder = resourceFolder
    }

    func parse(url: URL) throws {
        guard let parser = XMLParser(contentsOf: url) else { throw EBookImportError.invalidFictionBook }
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        guard parser.parse() else { throw parser.parserError ?? EBookImportError.invalidFictionBook }
        materializeImages()
        guard !renderedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw EBookImportError.emptyBook }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributes: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        stack.append(name)
        if name == "description" { inDescription = true }
        if name == "body", attributes["name"] == nil || attributes["name"]?.isEmpty == true { inMainBody = true }
        if name == "book-title" || name == "first-name" || name == "last-name" { metadataBuffer = "" }

        if name == "binary", let id = attributes["id"] {
            binaryID = id
            binaryMime = attributes["content-type"] ?? "image/jpeg"
            binaryBuffer = ""
        }

        if name == "image", let href = attributes.first(where: { $0.key.lowercased().hasSuffix("href") })?.value {
            let id = href.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            if stack.contains("coverpage") { coverReference = id }
            if inMainBody { renderedBody += "{{IMAGE:\(id)}}" }
        }

        if inMainBody {
            switch name {
            case "section": renderedBody += "<section>"
            case "title": renderedBody += "<h2>"
            case "subtitle": renderedBody += "<h3>"
            case "p": renderedBody += "<p>"
            case "strong": renderedBody += "<strong>"
            case "emphasis": renderedBody += "<em>"
            case "cite": renderedBody += "<blockquote>"
            case "poem": renderedBody += "<div class=\"poem\">"
            case "stanza": renderedBody += "<div>"
            case "v": renderedBody += "<p>"
            case "empty-line": renderedBody += "<p><br></p>"
            default: break
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if binaryID != nil { binaryBuffer += string; return }
        if inDescription, ["book-title", "first-name", "last-name"].contains(stack.last ?? "") {
            metadataBuffer += string
        }
        if inMainBody {
            renderedBody += EBookImporter.escapeHTML(string)
            searchText += " " + string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        if name == "binary", let id = binaryID {
            binaries[id] = (binaryMime, binaryBuffer)
            binaryID = nil
            binaryBuffer = ""
        }
        if inDescription {
            if name == "book-title", title.isEmpty { title = metadataBuffer }
            if name == "first-name" || name == "last-name" { author += (author.isEmpty ? "" : " ") + metadataBuffer }
        }
        if inMainBody {
            switch name {
            case "section": renderedBody += "</section>"
            case "title": renderedBody += "</h2>"
            case "subtitle": renderedBody += "</h3>"
            case "p", "v": renderedBody += "</p>"
            case "strong": renderedBody += "</strong>"
            case "emphasis": renderedBody += "</em>"
            case "cite": renderedBody += "</blockquote>"
            case "poem", "stanza": renderedBody += "</div>"
            default: break
            }
        }
        if name == "description" { inDescription = false }
        if name == "body" { inMainBody = false }
        _ = stack.popLast()
    }

    private func materializeImages() {
        let imageFolder = resourceFolder.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imageFolder, withIntermediateDirectories: true)
        for (id, binary) in binaries {
            let compact = binary.data.filter { !$0.isWhitespace }
            guard let data = Data(base64Encoded: compact) else { continue }
            let ext = binary.mime.contains("png") ? "png" : binary.mime.contains("gif") ? "gif" : "jpg"
            let safeName = id.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
            let fileName = "\(safeName).\(ext)"
            let url = imageFolder.appendingPathComponent(fileName)
            try? data.write(to: url, options: .atomic)
            renderedBody = renderedBody.replacingOccurrences(of: "{{IMAGE:\(id)}}", with: "<img src=\"images/\(fileName)\" alt=\"\">")
            if coverReference == id { coverURL = url }
        }
        renderedBody = renderedBody.replacingOccurrences(of: "\\{\\{IMAGE:[^}]+\\}\\}", with: "", options: .regularExpression)
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
