import Foundation

actor AIReliabilityConfigurationService {
    static let shared = AIReliabilityConfigurationService()
    static let endpoint = URL(string: "https://4-3rail.top/inkshelf-update/ai-config.json")!

    private let defaults: UserDefaults
    private var configuration: AIReliabilityConfiguration

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.cacheKey),
           let decoded = try? JSONDecoder().decode(AIReliabilityConfiguration.self, from: data),
           let valid = decoded.validated(forBuild: AppIdentity.build) {
            configuration = valid
        } else {
            configuration = .bundled
        }
    }

    func current() -> AIReliabilityConfiguration { configuration }

    @discardableResult
    func refresh() async -> Bool {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.waitsForConnectivity = false
        sessionConfiguration.timeoutIntervalForRequest = 10
        sessionConfiguration.timeoutIntervalForResource = 12
        do {
            let (data, response) = try await URLSession(configuration: sessionConfiguration).data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  data.count <= 16_384,
                  let decoded = try? JSONDecoder().decode(AIReliabilityConfiguration.self, from: data),
                  let valid = decoded.validated(forBuild: AppIdentity.build)
            else { return false }
            configuration = valid
            defaults.set(data, forKey: Self.cacheKey)
            defaults.set(Date.now, forKey: Self.refreshDateKey)
            return true
        } catch {
            return false
        }
    }

    private static let cacheKey = "ai.reliabilityConfiguration"
    private static let refreshDateKey = "ai.reliabilityConfigurationUpdatedAt"
}
