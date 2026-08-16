import Foundation

struct AIReliabilityConfiguration: Codable, Equatable, Sendable {
    let schema: Int
    let revision: Int
    let minimumBuild: Int
    let requestTimeoutSeconds: Int
    let maximumAttempts: Int
    let retryBaseDelayMilliseconds: Int

    enum CodingKeys: String, CodingKey {
        case schema, revision
        case minimumBuild = "minimum_build"
        case requestTimeoutSeconds = "request_timeout_seconds"
        case maximumAttempts = "maximum_attempts"
        case retryBaseDelayMilliseconds = "retry_base_delay_ms"
    }

    static let bundled = AIReliabilityConfiguration(
        schema: 1,
        revision: 0,
        minimumBuild: 15,
        requestTimeoutSeconds: 24,
        maximumAttempts: 3,
        retryBaseDelayMilliseconds: 650
    )

    func validated(forBuild build: Int) -> AIReliabilityConfiguration? {
        guard schema == 1,
              revision >= 0,
              minimumBuild <= build,
              (20...90).contains(requestTimeoutSeconds),
              (1...4).contains(maximumAttempts),
              (250...3_000).contains(retryBaseDelayMilliseconds)
        else { return nil }
        return self
    }
}
