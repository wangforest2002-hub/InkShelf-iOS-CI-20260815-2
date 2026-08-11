import SwiftUI

@main
struct InkShelfApp: App {
    @State private var library = LibraryStore()
    @AppStorage("appearance") private var appearance = AppAppearance.light.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .onOpenURL { url in
                    library.importFiles([url])
                }
        }
    }
}
