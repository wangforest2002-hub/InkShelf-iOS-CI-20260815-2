import Foundation

actor SocialPostImportService {
    static let shared = SocialPostImportService()

    private let endpoint = URL(string: "https://4-3rail.top/inkshelf-media/x/resolve")!
    private static let allowedHosts = Set(["x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"])

    func resolve(_ input: String) async throws -> SocialPostPreview {
        guard let postURL = normalizedPostURL(input) else { throw SocialPostImportError.invalidURL }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "url", value: postURL.absoluteString)]
        guard let url = components?.url else { throw SocialPostImportError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SocialPostImportError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ServerError.self, from: data).message) ?? "暂时无法读取这条帖子。"
            throw SocialPostImportError.server(message)
        }
        let preview = try JSONDecoder().decode(SocialPostPreview.self, from: data)
        guard !preview.images.isEmpty else { throw SocialPostImportError.noImages }
        return preview
    }

    func download(preview: SocialPostPreview, imageIDs: Set<String>) async throws -> SocialPostDownload {
        let selected = preview.images.filter { imageIDs.contains($0.id) }
        guard !selected.isEmpty else { throw SocialPostImportError.noSelection }
        guard selected.count <= 20 else { throw SocialPostImportError.tooManyImages }

        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("InkShelfSocialImport", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let title = safeFolderName(preview.suggestedTitle)
        let gallery = temporaryRoot.appendingPathComponent(title, isDirectory: true)
        try fileManager.createDirectory(at: gallery, withIntermediateDirectories: true)

        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 30
            let session = URLSession(configuration: configuration)
            var totalBytes = 0
            for (index, image) in selected.enumerated() {
                var request = URLRequest(url: image.url)
                request.setValue("image/avif,image/webp,image/png,image/jpeg,*/*;q=0.6", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("image/") == true,
                      !data.isEmpty,
                      data.count <= 50_000_000
                else { throw SocialPostImportError.downloadFailed(index + 1) }
                totalBytes += data.count
                guard totalBytes <= 200_000_000 else { throw SocialPostImportError.downloadTooLarge }
                let ext = safeExtension(image.format)
                try data.write(
                    to: gallery.appendingPathComponent(String(format: "%06d.%@", index + 1, ext)),
                    options: .atomic
                )
            }
            return SocialPostDownload(temporaryRoot: temporaryRoot, galleryFolder: gallery)
        } catch {
            try? fileManager.removeItem(at: temporaryRoot)
            throw error
        }
    }

    nonisolated func normalizedPostURL(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              Self.allowedHosts.contains(host)
        else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 3,
              parts[1].lowercased() == "status",
              parts[2].allSatisfy(\.isNumber)
        else { return nil }
        return URL(string: "https://x.com/\(parts[0])/status/\(parts[2])")
    }

    private func safeFolderName(_ value: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = value.components(separatedBy: illegal).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? "X 图片珍藏" : cleaned).prefix(60))
    }

    private func safeExtension(_ format: String) -> String {
        switch format.lowercased() {
        case "jpg", "jpeg": "jpg"
        case "webp": "webp"
        default: "png"
        }
    }
}

enum SocialPostImportError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(String)
    case noImages
    case noSelection
    case tooManyImages
    case downloadFailed(Int)
    case downloadTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidURL: "请粘贴完整的 X 帖子链接，例如 https://x.com/画师/status/数字。"
        case .invalidResponse: "图片通道返回了无法识别的内容。"
        case .server(let message): message
        case .noImages: "这条帖子里没有可导入的静态图片。"
        case .noSelection: "请至少选择一张图片。"
        case .tooManyImages: "一次最多导入 20 张图片。"
        case .downloadFailed(let index): "第 \(index) 张原图下载失败，请稍后重试。"
        case .downloadTooLarge: "这组图片超过 200 MB，请分开导入。"
        }
    }
}

private struct ServerError: Decodable {
    let message: String
}
