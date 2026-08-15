import Foundation

protocol AppUpdateServing: Sendable {
    func latestRelease() async throws -> AppUpdateRelease
}

struct AppUpdateService: AppUpdateServing {
    static let endpoint = URL(string: "https://4-3rail.top/inkshelf-update/latest.json")!

    func latestRelease() async throws -> AppUpdateRelease {
        var request = URLRequest(url: Self.endpoint)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 15
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppUpdateError.serverUnavailable
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release: AppUpdateRelease
        do {
            release = try decoder.decode(AppUpdateRelease.self, from: data)
        } catch {
            throw AppUpdateError.invalidMetadata
        }
        try validate(release)
        return release
    }

    private func validate(_ release: AppUpdateRelease) throws {
        guard release.schema == 1,
              release.build > 0,
              !release.version.isEmpty,
              release.bundleIdentifier == AppIdentity.bundleIdentifier,
              release.preservesAppData
        else { throw AppUpdateError.invalidMetadata }

        guard let installURL = release.installURL else { return }
        guard installURL.scheme?.lowercased() == "itms-services",
              let components = URLComponents(url: installURL, resolvingAgainstBaseURL: false),
              components.queryItems?.first(where: { $0.name == "action" })?.value == "download-manifest",
              let manifestValue = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let manifestURL = URL(string: manifestValue),
              manifestURL.scheme == "https",
              manifestURL.host == "4-3rail.top"
        else { throw AppUpdateError.untrustedInstallURL }
    }
}

enum AppUpdateError: LocalizedError {
    case serverUnavailable
    case invalidMetadata
    case untrustedInstallURL
    case incompatibleSystem(String)
    case releaseNotReady

    var errorDescription: String? {
        switch self {
        case .serverUnavailable:
            "暂时联系不上更新服务器，请稍后再试。"
        case .invalidMetadata:
            "更新信息不完整，为保护本地书库已停止更新。"
        case .untrustedInstallURL:
            "更新地址未通过安全检查。"
        case .incompatibleSystem(let version):
            "这个版本需要 iOS / iPadOS \(version) 或更高版本。"
        case .releaseNotReady:
            "新版本正在签名和发布，请稍后再试。"
        }
    }
}
