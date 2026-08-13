import Foundation

/// Reads document-picker and File Provider URLs through the coordination path
/// required by iOS. This also gives iCloud a chance to materialize placeholders
/// before the importer starts parsing them.
enum ExternalFileAccess {
    static func coordinateReading<T>(
        at sourceURL: URL,
        operation: (URL) throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?

        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result { try operation(coordinatedURL) }
        }

        if let coordinationError { throw coordinationError }
        guard let result else { throw BookImportError.accessDenied(sourceURL.lastPathComponent) }
        return try result.get()
    }

    static func copyItem(from sourceURL: URL, to destinationURL: URL) throws {
        try coordinateReading(at: sourceURL) { coordinatedURL in
            try FileManager.default.copyItem(at: coordinatedURL, to: destinationURL)
        }
    }
}
