import Foundation
import ImageIO
import Observation
import UIKit

struct HomeWorldAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
@Observable
final class HomeWorldStore {
    private(set) var state: HomeWorldState
    private(set) var saveRevision = 0
    var alert: HomeWorldAlert?

    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let rootURL: URL
    @ObservationIgnored private let assetsURL: URL
    @ObservationIgnored private let metadataURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(fileManager: FileManager = .default, documentsURL: URL? = nil) {
        self.fileManager = fileManager
        let documents = documentsURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        rootURL = documents.appendingPathComponent("InkShelf Library", isDirectory: true)
        assetsURL = rootURL.appendingPathComponent("Home Assets", isDirectory: true)
        metadataURL = rootURL.appendingPathComponent("home-world.json")
        try? fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        state = Self.loadState(from: metadataURL) ?? HomeWorldState()
        repairState()
    }

    func setTheme(_ theme: HomeRoomTheme) {
        guard state.theme != theme else { return }
        state.theme = theme
        scheduleSave()
    }

    @discardableResult
    func addFurniture(_ furniture: HomeFurnitureKind) -> UUID {
        let index = state.placements.filter { $0.kind == .furniture }.count
        let position = nextFloorPosition(index: index)
        let placement = HomePlacement(
            kind: .furniture,
            furniture: furniture,
            transform: HomeTransform(x: position.x, z: position.z, yaw: Float(index % 4) * .pi / 12)
        )
        state.placements.append(placement)
        saveImmediately()
        return placement.id
    }

    @discardableResult
    func addBook(_ bookID: UUID) -> UUID {
        let count = state.placements.filter { $0.kind == .book }.count
        let column = count % 7
        let row = (count / 7) % 3
        let placement = HomePlacement(
            kind: .book,
            bookID: bookID,
            transform: HomeTransform(
                x: -2.25 + Float(column) * 0.24,
                y: 0.42 + Float(row) * 0.59,
                z: -2.08,
                yaw: 0,
                scale: 0.82
            )
        )
        state.placements.append(placement)
        saveImmediately()
        return placement.id
    }

    func seedRecentBooksIfNeeded(_ books: [Book]) {
        guard !state.hasSeededBooks else { return }
        let recent = books.sorted {
            ($0.lastOpenedAt ?? $0.importedAt) > ($1.lastOpenedAt ?? $1.importedAt)
        }
        for book in recent.prefix(6) { _ = addBook(book.id) }
        state.hasSeededBooks = true
        saveImmediately()
    }

    @discardableResult
    func importArtwork(data: Data, kind: HomeArtworkKind, title: String? = nil) throws -> UUID {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.floatValue > 0,
              height.floatValue > 0,
              let image = Self.downsampledImage(source: source, maxPixelSize: 2_048)
        else { throw HomeWorldStoreError.invalidImage }

        let id = UUID()
        let fileName = "\(id.uuidString.lowercased()).png"
        let destination = assetsURL.appendingPathComponent(fileName)
        guard let png = image.pngData() else { throw HomeWorldStoreError.invalidImage }
        try png.write(to: destination, options: .atomic)

        let artwork = HomeArtwork(
            id: id,
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? kind.title,
            kind: kind,
            relativePath: "Home Assets/\(fileName)",
            aspectRatio: width.floatValue / height.floatValue
        )
        state.artworks.append(artwork)

        let placementTransform: HomeTransform
        switch kind {
        case .poster:
            let posterCount = state.placements.filter { placement in
                placement.artworkID.flatMap(artworkWithID)?.kind == .poster
            }.count
            placementTransform = HomeTransform(
                x: min(2.2, -0.65 + Float(posterCount) * 1.05),
                y: 1.65,
                z: -2.39,
                yaw: 0,
                scale: 0.9
            )
        case .standee, .figure:
            let count = state.placements.filter { $0.kind == .artwork }.count
            let position = nextFloorPosition(index: count + 4)
            placementTransform = HomeTransform(x: position.x, z: position.z, yaw: 0, scale: 0.82)
        }
        state.placements.append(HomePlacement(kind: .artwork, artworkID: id, transform: placementTransform))
        saveImmediately()
        return state.placements.last?.id ?? id
    }

    func artworkURL(for artwork: HomeArtwork) -> URL {
        rootURL.appendingPathComponent(artwork.relativePath)
    }

    func updatePlacement(_ id: UUID, transform: HomeTransform) {
        guard let index = state.placements.firstIndex(where: { $0.id == id }),
              !state.placements[index].isLocked
        else { return }
        var safe = transform
        safe.clamp()
        guard state.placements[index].transform != safe else { return }
        state.placements[index].transform = safe
        scheduleSave()
    }

    func updatePlacement(_ id: UUID, locked: Bool) {
        guard let index = state.placements.firstIndex(where: { $0.id == id }) else { return }
        state.placements[index].isLocked = locked
        saveImmediately()
    }

    func duplicatePlacement(_ id: UUID) -> UUID? {
        guard var copy = state.placements.first(where: { $0.id == id }) else { return nil }
        copy = HomePlacement(
            kind: copy.kind,
            furniture: copy.furniture,
            bookID: copy.bookID,
            artworkID: copy.artworkID,
            transform: HomeTransform(
                x: copy.transform.x + 0.28,
                y: copy.transform.y,
                z: copy.transform.z + 0.22,
                yaw: copy.transform.yaw,
                scale: copy.transform.scale
            )
        )
        state.placements.append(copy)
        saveImmediately()
        return copy.id
    }

    func removePlacement(_ id: UUID) {
        guard let placement = state.placements.first(where: { $0.id == id }) else { return }
        state.placements.removeAll { $0.id == id }
        if let artworkID = placement.artworkID,
           !state.placements.contains(where: { $0.artworkID == artworkID }),
           let artwork = artworkWithID(artworkID) {
            try? fileManager.removeItem(at: artworkURL(for: artwork))
            state.artworks.removeAll { $0.id == artworkID }
        }
        saveImmediately()
    }

    func resetRoom() {
        let bookPlacements = state.placements.filter { $0.kind == .book }
        let artworkPlacements = state.placements.filter { $0.kind == .artwork }
        state.placements = HomeWorldState.defaultFurniture + bookPlacements + artworkPlacements
        saveImmediately()
    }

    func reconcileBooks(validIDs: Set<UUID>) {
        let count = state.placements.count
        state.placements.removeAll { placement in
            placement.kind == .book && placement.bookID.map { !validIDs.contains($0) } == true
        }
        if state.placements.count != count { saveImmediately() }
    }

    func updateKokoZone(_ zone: KokoActivityZone) {
        var safe = zone
        safe.clamp()
        state.koko.activityZone = safe
        scheduleSave()
    }

    func updateKoko(roamingEnabled: Bool? = nil, welcomesHome: Bool? = nil, quietWhileReading: Bool? = nil) {
        if let roamingEnabled { state.koko.roamingEnabled = roamingEnabled }
        if let welcomesHome { state.koko.welcomesHome = welcomesHome }
        if let quietWhileReading { state.koko.quietWhileReading = quietWhileReading }
        saveImmediately()
    }

    func placement(withID id: UUID?) -> HomePlacement? {
        guard let id else { return nil }
        return state.placements.first { $0.id == id }
    }

    func artworkWithID(_ id: UUID) -> HomeArtwork? {
        state.artworks.first { $0.id == id }
    }

    func flush() {
        saveTask?.cancel()
        saveImmediately()
    }

    private func repairState() {
        state.schema = HomeWorldState.currentSchema
        state.placements = state.placements.filter { placement in
            switch placement.kind {
            case .furniture: return placement.furniture != nil
            case .book: return placement.bookID != nil
            case .artwork:
                guard let id = placement.artworkID,
                      let artwork = state.artworks.first(where: { $0.id == id })
                else { return false }
                return fileManager.fileExists(atPath: artworkURL(for: artwork).path)
            }
        }
        var zone = state.koko.activityZone
        zone.clamp()
        state.koko.activityZone = zone
    }

    private func nextFloorPosition(index: Int) -> (x: Float, z: Float) {
        let columns = 5
        let column = index % columns
        let row = (index / columns) % 4
        return (-1.8 + Float(column) * 0.86, -1.25 + Float(row) * 0.78)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            self?.saveImmediately()
        }
    }

    private func saveImmediately() {
        saveTask?.cancel()
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: metadataURL, options: .atomic)
            saveRevision &+= 1
        } catch {
            alert = HomeWorldAlert(title: "小家没有保存好", message: error.localizedDescription)
        }
    }

    private static func loadState(from url: URL) -> HomeWorldState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HomeWorldState.self, from: data)
    }

    private static func downsampledImage(source: CGImageSource, maxPixelSize: Int) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

enum HomeWorldStoreError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage: "这张图片暂时无法做成家中摆件。"
        }
    }
}

private extension String {
    var nilIfBlank: String? { isEmpty ? nil : self }
}
