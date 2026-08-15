import Foundation
import ZIPFoundation

struct ParsedEPUB {
    let package: EBookPackage
    let coverURL: URL?
}

enum EPUBParser {
    private static let maximumEntries = 50_000
    private static let maximumExpandedBytes: UInt64 = 8 * 1_024 * 1_024 * 1_024

    static func parse(archiveURL: URL, extractionRoot: URL) throws -> ParsedEPUB {
        try extract(archiveURL: archiveURL, to: extractionRoot)

        let containerURL = extractionRoot.appendingPathComponent("META-INF/container.xml")
        let container = ContainerDocumentParser()
        try container.parse(url: containerURL)
        guard let rootFile = container.rootFilePath else { throw EBookImportError.invalidEPUB }

        let opfURL = try safeURL(relativePath: rootFile, root: extractionRoot)
        let opf = OPFDocumentParser()
        try opf.parse(url: opfURL)
        guard !opf.spineIDs.isEmpty else { throw EBookImportError.emptyBook }

        let opfFolder = opfURL.deletingLastPathComponent()
        var navigationTitles: [String: String] = [:]
        if let navItem = opf.manifest.values.first(where: { $0.properties.split(separator: " ").contains("nav") }) {
            navigationTitles.merge(parseNavigation(item: navItem, opfFolder: opfFolder, root: extractionRoot)) { first, _ in first }
        }
        if let tocID = opf.tocID, let ncx = opf.manifest[tocID] {
            navigationTitles.merge(parseNavigation(item: ncx, opfFolder: opfFolder, root: extractionRoot)) { first, _ in first }
        }

        var chapters: [EBookChapter] = []
        for (index, idref) in opf.spineIDs.enumerated() {
            guard let item = opf.manifest[idref],
                  let itemURL = resolvedURL(href: item.href, relativeTo: opfFolder, root: extractionRoot)
            else { continue }
            let relativePath = relativePath(of: itemURL, from: extractionRoot)
            let content = TextContentParser.read(url: itemURL)
            let title = navigationTitles[normalizedPath(itemURL)]
                ?? content.title.nilIfBlank
                ?? "第 \(index + 1) 章"
            chapters.append(EBookChapter(
                id: idref,
                title: title,
                relativePath: relativePath,
                searchText: String(content.text.prefix(120_000))
            ))
        }
        guard !chapters.isEmpty else { throw EBookImportError.emptyBook }

        let coverItem: EPUBManifestItem? = {
            if let coverID = opf.coverID, let item = opf.manifest[coverID] { return item }
            return opf.manifest.values.first { $0.properties.split(separator: " ").contains("cover-image") }
        }()
        let coverURL = coverItem.flatMap { resolvedURL(href: $0.href, relativeTo: opfFolder, root: extractionRoot) }
        let title = opf.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedEPUB(
            package: EBookPackage(
                title: title.isEmpty ? archiveURL.deletingPathExtension().lastPathComponent : title,
                author: opf.author.nilIfBlank,
                format: .epub,
                chapters: chapters,
                resourceRootRelativePath: "publication"
            ),
            coverURL: coverURL
        )
    }

    private static func extract(archiveURL: URL, to root: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = try Archive(url: archiveURL, accessMode: .read)

        var expanded: UInt64 = 0
        var entryCount = 0
        for entry in archive where entry.type == .file {
            entryCount += 1
            guard entryCount <= maximumEntries else { throw EBookImportError.bookTooLarge }
            expanded += UInt64(entry.uncompressedSize)
            guard expanded <= maximumExpandedBytes else { throw EBookImportError.bookTooLarge }
            let destination = try safeURL(relativePath: entry.path, root: root)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try archive.extract(entry, to: destination)
        }
    }

    private static func parseNavigation(item: EPUBManifestItem, opfFolder: URL, root: URL) -> [String: String] {
        guard let navURL = resolvedURL(href: item.href, relativeTo: opfFolder, root: root) else { return [:] }
        let parser = NavigationDocumentParser(baseURL: navURL.deletingLastPathComponent(), root: root)
        try? parser.parse(url: navURL)
        return parser.titles
    }

    private static func resolvedURL(href: String, relativeTo base: URL, root: URL) -> URL? {
        let path = href.components(separatedBy: "#")[0].components(separatedBy: "?")[0]
        guard !path.isEmpty else { return nil }
        let decoded = path.removingPercentEncoding ?? path
        let url = base.appendingPathComponent(decoded).standardizedFileURL
        return isContained(url, in: root) ? url : nil
    }

    fileprivate static func safeURL(relativePath: String, root: URL) throws -> URL {
        let cleaned = relativePath.replacingOccurrences(of: "\\", with: "/")
        let url = root.appendingPathComponent(cleaned).standardizedFileURL
        guard isContained(url, in: root) else { throw EBookImportError.invalidEPUB }
        return url
    }

    private static func isContained(_ url: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let candidate = url.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return candidate == rootPath || candidate.hasPrefix(rootPath + "/")
    }

    private static func relativePath(of url: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
        let path = url.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : url.lastPathComponent
    }

    fileprivate static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path.lowercased()
    }
}

private final class ContainerDocumentParser: NSObject, XMLParserDelegate {
    var rootFilePath: String?

    func parse(url: URL) throws {
        guard let parser = XMLParser(contentsOf: url) else { throw EBookImportError.invalidEPUB }
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        guard parser.parse() else { throw parser.parserError ?? EBookImportError.invalidEPUB }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "rootfile", rootFilePath == nil else { return }
        rootFilePath = attributeDict["full-path"]
    }
}

fileprivate struct EPUBManifestItem {
    let id: String
    let href: String
    let mediaType: String
    let properties: String
}

private final class OPFDocumentParser: NSObject, XMLParserDelegate {
    var title = ""
    var author = ""
    var manifest: [String: EPUBManifestItem] = [:]
    var spineIDs: [String] = []
    var coverID: String?
    var tocID: String?

    private var metadataElement: String?
    private var metadataBuffer = ""

    func parse(url: URL) throws {
        guard let parser = XMLParser(contentsOf: url) else { throw EBookImportError.invalidEPUB }
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        guard parser.parse() else { throw parser.parserError ?? EBookImportError.invalidEPUB }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributes: [String: String] = [:]
    ) {
        switch elementName.lowercased() {
        case "title", "creator":
            metadataElement = elementName.lowercased()
            metadataBuffer = ""
        case "item":
            if let id = attributes["id"], let href = attributes["href"] {
                manifest[id] = EPUBManifestItem(
                    id: id,
                    href: href,
                    mediaType: attributes["media-type"] ?? "",
                    properties: attributes["properties"] ?? ""
                )
            }
        case "spine":
            tocID = attributes["toc"]
        case "itemref":
            if attributes["linear"]?.lowercased() != "no", let idref = attributes["idref"] {
                spineIDs.append(idref)
            }
        case "meta":
            if attributes["name"]?.lowercased() == "cover" { coverID = attributes["content"] }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if metadataElement != nil { metadataBuffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard metadataElement == elementName.lowercased() else { return }
        if metadataElement == "title", title.isEmpty { title = metadataBuffer }
        if metadataElement == "creator", author.isEmpty { author = metadataBuffer }
        metadataElement = nil
        metadataBuffer = ""
    }
}

private final class NavigationDocumentParser: NSObject, XMLParserDelegate {
    private let baseURL: URL
    private let root: URL
    private var activeHref: String?
    private var buffer = ""
    private var pendingNCXTitle = ""
    var titles: [String: String] = [:]

    init(baseURL: URL, root: URL) {
        self.baseURL = baseURL
        self.root = root
    }

    func parse(url: URL) throws {
        guard let parser = XMLParser(contentsOf: url) else { return }
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        _ = parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributes: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        if name == "a", let href = attributes["href"] {
            activeHref = href
            buffer = ""
        } else if name == "text" {
            buffer = ""
        } else if name == "content", let src = attributes["src"] {
            store(title: pendingNCXTitle, href: src)
            pendingNCXTitle = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if activeHref != nil || buffer.isEmpty || !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            buffer += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        if name == "a", let href = activeHref {
            store(title: buffer, href: href)
            activeHref = nil
            buffer = ""
        } else if name == "text", activeHref == nil {
            pendingNCXTitle = buffer
            buffer = ""
        }
    }

    private func store(title: String, href: String) {
        let cleanTitle = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let path = href.components(separatedBy: "#")[0]
        guard !cleanTitle.isEmpty, !path.isEmpty else { return }
        let decoded = path.removingPercentEncoding ?? path
        let url = baseURL.appendingPathComponent(decoded).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        guard url.path == rootPath || url.path.hasPrefix(rootPath + "/") else { return }
        titles[EPUBParser.normalizedPath(url)] = cleanTitle
    }
}

private enum TextContentParser {
    static func read(url: URL) -> (title: String, text: String) {
        let ext = url.pathExtension.lowercased()
        if ["xhtml", "html", "htm", "xml"].contains(ext), let parser = XMLParser(contentsOf: url) {
            let collector = XMLTextCollector()
            parser.delegate = collector
            parser.shouldProcessNamespaces = true
            if parser.parse() {
                return (collector.title, collector.text)
            }
        }
        if ["txt", "md", "markdown"].contains(ext), let text = try? String(contentsOf: url, encoding: .utf8) {
            return ("", normalized(text))
        }
        return ("", "")
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class XMLTextCollector: NSObject, XMLParserDelegate {
    var title = ""
    var text = ""
    private var elementStack: [String] = []
    private var titleBuffer = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        elementStack.append(elementName.lowercased())
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !elementStack.contains("script"), !elementStack.contains("style") else { return }
        if elementStack.last == "title" { titleBuffer += string }
        if elementStack.contains("body") { text += " " + string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName.lowercased() == "title", title.isEmpty {
            title = titleBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        _ = elementStack.popLast()
        if ["p", "div", "li", "br", "h1", "h2", "h3"].contains(elementName.lowercased()) { text += "\n" }
        if elementName.lowercased() == "body" {
            text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
