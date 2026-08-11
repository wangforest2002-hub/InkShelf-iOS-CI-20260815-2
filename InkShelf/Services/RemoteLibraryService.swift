import Foundation

enum RemoteLibraryError: LocalizedError, Sendable {
    case invalidServer
    case invalidResponse
    case authenticationRequired
    case server(status: Int, message: String?)
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidServer: return "服务器地址无效，请使用 HTTPS 地址。"
        case .invalidResponse: return "远程书库返回了无法识别的响应。"
        case .authenticationRequired: return "登录已失效，请重新登录远程书库。"
        case .server(let status, let message):
            return message ?? "远程书库请求失败（\(status)）。"
        case .downloadFailed: return "书籍下载没有完成，请检查网络后重试。"
        }
    }
}

struct RemoteLibraryService: Sendable {
    let baseURL: URL

    init(serverAddress: String) throws {
        let value = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host != nil
        else { throw RemoteLibraryError.invalidServer }
        baseURL = url
    }

    func login(username: String, password: String) async throws -> RemoteLibraryUser {
        var request = URLRequest(url: try endpoint("/api/auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "username": username,
            "password": password,
        ])
        let data = try await data(for: request)
        let envelope = try JSONDecoder().decode(RemoteLoginEnvelope.self, from: data)
        guard let user = envelope.user else { throw RemoteLibraryError.authenticationRequired }
        return user
    }

    func currentUser() async throws -> RemoteLibraryUser? {
        let data = try await data(for: URLRequest(url: try endpoint("/api/auth/me")))
        return try JSONDecoder().decode(RemoteLoginEnvelope.self, from: data).user
    }

    func logout() async throws {
        var request = URLRequest(url: try endpoint("/api/auth/logout"))
        request.httpMethod = "POST"
        _ = try await data(for: request)
    }

    func fetchBooks() async throws -> [RemoteBook] {
        let data = try await data(for: URLRequest(url: try endpoint("/api/inkshelf/books")))
        return try JSONDecoder().decode(RemoteBooksEnvelope.self, from: data).books
    }

    func absoluteURL(for path: String) -> URL? {
        if let direct = URL(string: path), direct.scheme != nil { return direct }
        return try? endpoint(path)
    }

    func download(
        _ book: RemoteBook,
        to destination: URL,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> URL {
        let request = URLRequest(url: try endpoint(book.downloadPath))
        return try await FileDownloadDelegate.download(
            request: request,
            destination: destination,
            progress: progress
        )
    }

    func upload(_ fileURL: URL) async throws -> RemoteBook {
        var components = URLComponents(url: try endpoint("/api/inkshelf/upload"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "name", value: fileURL.lastPathComponent)]
        guard let url = components?.url else { throw RemoteLibraryError.invalidServer }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType(for: fileURL), forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(RemoteUploadEnvelope.self, from: data).book
    }

    func delete(_ book: RemoteBook) async throws {
        var request = URLRequest(url: try endpoint("/api/inkshelf/books/\(book.id)"))
        request.httpMethod = "DELETE"
        _ = try await data(for: request)
    }

    func updateProgress(bookID: String, progress: Double, position: Int) async throws {
        var request = URLRequest(url: try endpoint("/api/inkshelf/progress/\(bookID)"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "progress": min(max(progress, 0), 1),
            "position": max(position, 0),
        ])
        _ = try await data(for: request)
    }

    private func endpoint(_ path: String) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw RemoteLibraryError.invalidServer
        }
        let root = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let child = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [root, child].filter { !$0.isEmpty }.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw RemoteLibraryError.invalidServer }
        return url
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw RemoteLibraryError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(RemoteAPIError.self, from: data))?.error
            if http.statusCode == 401 { throw RemoteLibraryError.authenticationRequired }
            throw RemoteLibraryError.server(status: http.statusCode, message: message)
        }
    }

    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": "application/pdf"
        case "epub": "application/epub+zip"
        case "cbz", "zip": "application/zip"
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "webp": "image/webp"
        case "html", "htm": "text/html"
        case "txt", "md", "markdown": "text/plain; charset=utf-8"
        default: "application/octet-stream"
        }
    }
}

private struct RemoteAPIError: Decodable {
    let error: String
}

private final class FileDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @MainActor @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var resultURL: URL?
    private var resultError: Error?

    private init(destination: URL, progress: @escaping @MainActor @Sendable (Double) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    static func download(
        request: URLRequest,
        destination: URL,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> URL {
        let delegate = FileDownloadDelegate(destination: destination, progress: progress)
        return try await delegate.start(request: request)
    }

    private func start(request: URLRequest) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.default
            configuration.httpCookieStorage = .shared
            configuration.httpShouldSetCookies = true
            configuration.waitsForConnectivity = true
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let value = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1)
        Task { @MainActor in progress(value) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let response = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            let data = try? Data(contentsOf: location)
            let message = data.flatMap { try? JSONDecoder().decode(RemoteAPIError.self, from: $0).error }
            resultError = response.statusCode == 401
                ? RemoteLibraryError.authenticationRequired
                : RemoteLibraryError.server(status: response.statusCode, message: message)
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            resultURL = destination
        } catch {
            resultError = error
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        defer {
            continuation = nil
            self.session?.finishTasksAndInvalidate()
            self.session = nil
        }
        if let error {
            continuation?.resume(throwing: error)
        } else if let resultError {
            continuation?.resume(throwing: resultError)
        } else if let resultURL {
            continuation?.resume(returning: resultURL)
        } else {
            continuation?.resume(throwing: RemoteLibraryError.downloadFailed)
        }
    }
}
