import Foundation

struct AppUpdateRelease: Identifiable, Codable, Equatable, Sendable {
    let schema: Int
    let version: String
    let build: Int
    let minimumIOS: String
    let publishedAt: Date
    let title: String
    let notes: [String]
    let mandatory: Bool
    let bundleIdentifier: String
    let packageSize: Int64?
    let sha256: String?
    let installURL: URL?
    let dataPolicy: String

    var id: Int { build }

    enum CodingKeys: String, CodingKey {
        case schema
        case version
        case build
        case minimumIOS = "minimum_ios"
        case publishedAt = "published_at"
        case title
        case notes
        case mandatory
        case bundleIdentifier = "bundle_identifier"
        case packageSize = "package_size"
        case sha256
        case installURL = "install_url"
        case dataPolicy = "data_policy"
    }

    func isNewer(thanVersion currentVersion: String, build currentBuild: Int) -> Bool {
        let remote = NumericVersion(version)
        let current = NumericVersion(currentVersion)
        if remote != current { return remote > current }
        return build > currentBuild
    }

    func supports(systemVersion: String) -> Bool {
        NumericVersion(systemVersion) >= NumericVersion(minimumIOS)
    }

    var preservesAppData: Bool {
        dataPolicy == "preserve_app_container"
    }
}

struct UpdateSafetySnapshot: Codable, Equatable, Sendable {
    let preparedAt: Date
    let sourceVersion: String
    let sourceBuild: Int
    let targetVersion: String
    let targetBuild: Int
    let bundleIdentifier: String
    let bookIDs: [UUID]
    let shelfGroupIDs: [UUID]
    let bookCount: Int
    let favoritePageCount: Int
    let policy: String
}

struct NumericVersion: Comparable, Equatable, Sendable {
    private let components: [Int]

    init(_ value: String) {
        let numericPrefix = value.split(separator: "-", maxSplits: 1).first ?? ""
        var parsed = numericPrefix.split(separator: ".").map { component in
            Int(component.filter(\.isNumber)) ?? 0
        }
        while parsed.last == 0, parsed.count > 1 { parsed.removeLast() }
        components = parsed.isEmpty ? [0] : parsed
    }

    static func < (lhs: NumericVersion, rhs: NumericVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

enum AppIdentity {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var build: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.inkshelf.reader"
    }

    static var systemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
