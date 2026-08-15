import SwiftUI

@main
struct InkShelfApp: App {
    @State private var library = LibraryStore()
    @State private var companion = AICompanionStore()
    @State private var achievements = AchievementStore()
    @State private var updates = AppUpdateStore()
    @AppStorage("appearance") private var appearance = AppAppearance.light.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(companion)
                .environment(achievements)
                .environment(updates)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .onOpenURL { url in
                    library.importFiles([url])
                }
        }
    }
}
