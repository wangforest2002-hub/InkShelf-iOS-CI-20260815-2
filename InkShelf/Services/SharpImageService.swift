import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers

enum SharpPageSource: Sendable {
    case image(URL)
    case pdf(URL, page: Int, password: String)
}

struct SharpEnhancementResult: Sendable {
    let temporaryRoot: URL
    let outputURL: URL
    let executionLocation: SharpExecutionLocation
}

enum SharpExecutionLocation: String, Sendable {
    case device
    case computer
}

struct SharpBridgeStatus: Decodable, Sendable {
    let status: String
    let profile: String
    let model: String
    let upscale: Int
    let finalScale: Int
    let downsample: String
    let format: String
}

actor SharpImageService {
    static let shared = SharpImageService()

    func check(address: String) async throws -> SharpBridgeStatus {
        let endpoint = try endpoint(address: address, path: "health")
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, response) = try await session(timeout: 8).data(for: request)
        try validateHTTP(response, data: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let status = try decoder.decode(SharpBridgeStatus.self, from: data)
        guard status.status == "ready",
              status.profile == "sharp",
              status.model == "realesrgan-x4plus-anime",
              status.upscale == 4,
              status.finalScale == 2,
              status.downsample.lowercased() == "lanczos",
              status.format.lowercased() == "png"
        else { throw SharpImageError.wrongPipeline }
        return status
    }

    func enhance(
        source: SharpPageSource,
        address: String,
        outputName: String
    ) async throws -> SharpEnhancementResult {
        _ = try await check(address: address)
        let prepared = try prepare(source)
        guard prepared.data.count <= 50_000_000 else { throw SharpImageError.inputTooLarge }
        let endpoint = try endpoint(address: address, path: "enhance")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 900
        request.setValue(prepared.mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue("sharp", forHTTPHeaderField: "X-InkShelf-Profile")
        request.httpBody = prepared.data

        let (downloadedURL, response) = try await session(timeout: 900).download(for: request)
        guard let http = response as? HTTPURLResponse else { throw SharpImageError.invalidResponse }
        if !(200..<300).contains(http.statusCode) {
            let data = (try? Data(contentsOf: downloadedURL)) ?? Data()
            let message = (try? JSONDecoder().decode(SharpBridgeError.self, from: data).message)
            throw SharpImageError.bridge(message ?? "电脑端处理失败。")
        }
        guard http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("image/png") == true,
              http.value(forHTTPHeaderField: "X-InkShelf-Model") == "realesrgan-x4plus-anime",
              http.value(forHTTPHeaderField: "X-InkShelf-Profile") == "sharp",
              http.value(forHTTPHeaderField: "X-InkShelf-Final-Scale") == "2"
        else { throw SharpImageError.wrongPipeline }

        let fileManager = FileManager.default
        let values = try downloadedURL.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size > 8, size <= 250_000_000 else {
            throw SharpImageError.outputTooLarge
        }
        let header = Data(try Data(contentsOf: downloadedURL, options: [.mappedIfSafe]).prefix(8))
        guard header == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else {
            throw SharpImageError.invalidResponse
        }
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("InkShelfSharpResult", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let cleanedName = safeFilename(outputName)
        let outputURL = temporaryRoot.appendingPathComponent(cleanedName)
        do {
            try fileManager.moveItem(at: downloadedURL, to: outputURL)
            return SharpEnhancementResult(
                temporaryRoot: temporaryRoot,
                outputURL: outputURL,
                executionLocation: .computer
            )
        } catch {
            try? fileManager.removeItem(at: temporaryRoot)
            throw error
        }
    }

    private func prepare(_ source: SharpPageSource) throws -> PreparedSharpInput {
        switch source {
        case .image(let url):
            let ext = url.pathExtension.lowercased()
            if ["jpg", "jpeg", "png", "webp"].contains(ext) {
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                let mime = ext == "png" ? "image/png" : (ext == "webp" ? "image/webp" : "image/jpeg")
                return PreparedSharpInput(data: data, mimeType: mime)
            }
            guard let image = UIImage(contentsOfFile: url.path), let data = image.pngData() else {
                throw SharpImageError.unreadablePage
            }
            return PreparedSharpInput(data: data, mimeType: "image/png")

        case .pdf(let url, let page, let password):
            guard let document = PDFDocument(url: url) else { throw SharpImageError.unreadablePage }
            if document.isLocked, !password.isEmpty { _ = document.unlock(withPassword: password) }
            guard !document.isLocked,
                  page >= 0,
                  page < document.pageCount,
                  let pdfPage = document.page(at: page)
            else { throw SharpImageError.unreadablePage }
            let bounds = pdfPage.bounds(for: .cropBox)
            let longest = max(bounds.width, bounds.height)
            let scale = min(1, 2_048 / max(longest, 1))
            let target = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
            guard let data = pdfPage.thumbnail(of: target, for: .cropBox).pngData() else {
                throw SharpImageError.unreadablePage
            }
            return PreparedSharpInput(data: data, mimeType: "image/png")
        }
    }

    private func endpoint(address: String, path: String) throws -> URL {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard var components = URLComponents(string: withScheme),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host != nil,
              components.user == nil,
              components.password == nil
        else { throw SharpImageError.invalidAddress }
        components.path = "/\(path)"
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw SharpImageError.invalidAddress }
        return url
    }

    private func session(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = false
        return URLSession(configuration: configuration)
    }

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw SharpImageError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(SharpBridgeError.self, from: data).message)
            throw SharpImageError.bridge(message ?? "无法连接电脑端 Sharp 服务。")
        }
    }

    private func safeFilename(_ value: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = value.components(separatedBy: illegal).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = URL(fileURLWithPath: cleaned.isEmpty ? "Sharp 锐化 2x" : cleaned)
            .deletingPathExtension().lastPathComponent
        return "\(String(stem.prefix(70)))-sharp-2x.png"
    }
}

enum SharpImageError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case wrongPipeline
    case unreadablePage
    case inputTooLarge
    case outputTooLarge
    case bridge(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "请先在设置中填写电脑桥地址，例如 http://192.168.1.8:8765。"
        case .invalidResponse: "电脑端返回的不是有效 PNG 图片。"
        case .wrongPipeline: "电脑端不是已确认的 Sharp 方案，已拒绝处理结果。"
        case .unreadablePage: "无法读取当前页面用于清晰化。"
        case .inputTooLarge: "当前页超过 50 MB，暂时不能发送到电脑处理。"
        case .outputTooLarge: "清晰化结果过大，为保护内存已停止导入。"
        case .bridge(let message): message
        }
    }
}

private struct PreparedSharpInput: Sendable {
    let data: Data
    let mimeType: String
}

private struct SharpBridgeError: Decodable {
    let message: String
}
