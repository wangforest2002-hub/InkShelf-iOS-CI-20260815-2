import Foundation

struct LibraryLoadResult: Sendable {
    let books: [Book]
    let recoveredFromBackup: Bool
}

/// Owns the durable book index. The app keeps a second atomic snapshot so an
/// interrupted write or damaged primary JSON never makes the whole shelf
/// disappear on the next launch.
struct LibraryMetadataRepository: Sendable {
    let primaryURL: URL
    let backupURL: URL

    init(primaryURL: URL) {
        self.primaryURL = primaryURL
        backupURL = primaryURL.deletingLastPathComponent().appendingPathComponent("library.backup.json")
    }

    func load() throws -> LibraryLoadResult {
        var primaryError: Error?
        do {
            if let books = try decodeIfPresent(at: primaryURL) {
                return LibraryLoadResult(books: books, recoveredFromBackup: false)
            }
        } catch {
            primaryError = error
        }

        do {
            if let books = try decodeIfPresent(at: backupURL) {
                try? encodedData(for: books).write(to: primaryURL, options: .atomic)
                return LibraryLoadResult(books: books, recoveredFromBackup: true)
            }
        } catch {
            throw primaryError ?? error
        }
        if let primaryError { throw primaryError }
        return LibraryLoadResult(books: [], recoveredFromBackup: false)
    }

    func save(_ books: [Book]) throws {
        let data = try encodedData(for: books)
        try data.write(to: primaryURL, options: .atomic)
        try data.write(to: backupURL, options: .atomic)
    }

    private func decodeIfPresent(at url: URL) throws -> [Book]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Book].self, from: data)
    }

    private func encodedData(for books: [Book]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(books)
    }
}

/// Serializes metadata writes away from the UI thread. Page turns only enqueue
/// a snapshot; explicit saves and lifecycle flushes wait behind older writes so
/// an outdated page can never overwrite a newer one.
final class LibraryMetadataWriter: @unchecked Sendable {
    private let repository: LibraryMetadataRepository
    private let queue = DispatchQueue(label: "com.inkshelf.library-metadata", qos: .utility)

    init(repository: LibraryMetadataRepository) {
        self.repository = repository
    }

    func save(_ books: [Book]) {
        queue.async { [repository] in
            try? repository.save(books)
        }
    }

    func saveAndWait(_ books: [Book]) -> String? {
        queue.sync { [repository] in
            do {
                try repository.save(books)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
    }
}
