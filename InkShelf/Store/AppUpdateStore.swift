import Foundation
import Observation

@MainActor
@Observable
final class AppUpdateStore {
    private(set) var latestRelease: AppUpdateRelease?
    private(set) var isChecking = false
    private(set) var lastCheckedAt: Date?
    private(set) var errorMessage: String?
    private(set) var didCheckThisLaunch = false

    @ObservationIgnored private let service: any AppUpdateServing
    @ObservationIgnored private let defaults: UserDefaults

    init(
        service: any AppUpdateServing = AppUpdateService(),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults
        lastCheckedAt = defaults.object(forKey: Self.lastCheckedKey) as? Date
    }

    var availableRelease: AppUpdateRelease? {
        guard let latestRelease,
              latestRelease.isNewer(thanVersion: AppIdentity.version, build: AppIdentity.build)
        else { return nil }
        return latestRelease
    }

    var canInstall: Bool {
        guard let release = availableRelease else { return false }
        return release.installURL != nil && release.supports(systemVersion: AppIdentity.systemVersion)
    }

    var shouldOfferAutomaticPrompt: Bool {
        guard let release = availableRelease, release.installURL != nil else { return false }
        return release.mandatory || defaults.integer(forKey: Self.dismissedBuildKey) < release.build
    }

    var statusText: String {
        if isChecking { return "正在检查…" }
        if let release = availableRelease {
            return release.installURL == nil ? "\(release.version) 正在准备" : "发现 \(release.version)"
        }
        if errorMessage != nil { return "检查失败" }
        if didCheckThisLaunch || lastCheckedAt != nil { return "已是最新版" }
        return "尚未检查"
    }

    func checkForUpdates(silent: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        if !silent { errorMessage = nil }
        defer {
            isChecking = false
            didCheckThisLaunch = true
        }

        do {
            let release = try await service.latestRelease()
            latestRelease = release
            lastCheckedAt = .now
            defaults.set(lastCheckedAt, forKey: Self.lastCheckedKey)
            errorMessage = nil
        } catch {
            if !silent {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func dismissCurrentPrompt() {
        guard let release = availableRelease, !release.mandatory else { return }
        defaults.set(release.build, forKey: Self.dismissedBuildKey)
    }

    private static let lastCheckedKey = "updates.lastCheckedAt"
    private static let dismissedBuildKey = "updates.dismissedBuild"
}
