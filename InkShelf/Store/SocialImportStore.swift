import Foundation
import Observation

struct SocialImportRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let postURL: String
}

@MainActor
@Observable
final class SocialImportStore {
    var pendingRequest: SocialImportRequest?

    @discardableResult
    func accept(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "nijigenhome",
              url.host?.lowercased() == "x-import",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "url" })?.value,
              SocialPostImportService.shared.normalizedPostURL(value) != nil
        else { return false }
        pendingRequest = SocialImportRequest(postURL: value)
        return true
    }
}

