import SwiftUI

@main
struct InkShelfApp: App {
    @State private var library = LibraryStore()
    @State private var companion = AICompanionStore()
    @State private var remoteLibrary = RemoteLibraryStore()
    @State private var iCloudLibrary = ICloudLibraryStore()
    @AppStorage("appearance") private var appearance = AppAppearance.light.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(companion)
                .environment(remoteLibrary)
                .environment(iCloudLibrary)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .onOpenURL { url in
                    library.importFiles([url])
                }
        }
    }
}
