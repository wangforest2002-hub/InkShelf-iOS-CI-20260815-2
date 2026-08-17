import Foundation

enum HomeRoomTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case sunset
    case rain
    case moonlight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sunset: "夕照书房"
        case .rain: "雨声小屋"
        case .moonlight: "月光阁楼"
        }
    }

    var subtitle: String {
        switch self {
        case .sunset: "奶油色暖光与浅木色"
        case .rain: "薄荷灰蓝与窗外雨意"
        case .moonlight: "深蓝夜空与一盏台灯"
        }
    }

    var systemImage: String {
        switch self {
        case .sunset: "sun.horizon.fill"
        case .rain: "cloud.rain.fill"
        case .moonlight: "moon.stars.fill"
        }
    }
}

enum HomePlacementKind: String, Codable, Sendable {
    case furniture
    case book
    case artwork
}

enum HomeFurnitureKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case bookshelf
    case sofa
    case lowTable
    case rug
    case floorLamp
    case plant
    case displayCabinet
    case desk
    case stool
    case bed
    case screen
    case cushion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bookshelf: "画集书架"
        case .sofa: "云朵沙发"
        case .lowTable: "浅木茶几"
        case .rug: "夕阳地毯"
        case .floorLamp: "布罩落地灯"
        case .plant: "窗边绿植"
        case .displayCabinet: "珍藏展示柜"
        case .desk: "阅读书桌"
        case .stool: "软垫小凳"
        case .bed: "午睡小床"
        case .screen: "木格屏风"
        case .cushion: "抱枕"
        }
    }

    var systemImage: String {
        switch self {
        case .bookshelf: "books.vertical.fill"
        case .sofa: "sofa.fill"
        case .lowTable: "table.furniture.fill"
        case .rug: "rectangle.inset.filled"
        case .floorLamp: "lamp.floor.fill"
        case .plant: "leaf.fill"
        case .displayCabinet: "cabinet.fill"
        case .desk: "studentdesk"
        case .stool: "chair.lounge.fill"
        case .bed: "bed.double.fill"
        case .screen: "rectangle.split.3x1.fill"
        case .cushion: "square.fill"
        }
    }
}

enum HomeArtworkKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case standee
    case poster
    case figure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standee: "二次元立牌"
        case .poster: "墙上挂画"
        case .figure: "手办展示"
        }
    }

    var systemImage: String {
        switch self {
        case .standee: "person.crop.rectangle"
        case .poster: "photo.artframe"
        case .figure: "sparkles"
        }
    }
}

struct HomeTransform: Codable, Hashable, Sendable {
    var x: Float
    var y: Float
    var z: Float
    var yaw: Float
    var scale: Float

    init(x: Float, y: Float = 0, z: Float, yaw: Float = 0, scale: Float = 1) {
        self.x = x
        self.y = y
        self.z = z
        self.yaw = yaw
        self.scale = scale
        clamp()
    }

    mutating func clamp() {
        x = min(max(x, -2.72), 2.72)
        y = min(max(y, 0), 2.65)
        z = min(max(z, -2.28), 2.18)
        scale = min(max(scale, 0.45), 1.9)
        guard yaw.isFinite else {
            yaw = 0
            return
        }
        while yaw > .pi { yaw -= .pi * 2 }
        while yaw < -.pi { yaw += .pi * 2 }
    }
}

struct HomePlacement: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var kind: HomePlacementKind
    var furniture: HomeFurnitureKind?
    var bookID: UUID?
    var artworkID: UUID?
    var transform: HomeTransform
    var isLocked: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: HomePlacementKind,
        furniture: HomeFurnitureKind? = nil,
        bookID: UUID? = nil,
        artworkID: UUID? = nil,
        transform: HomeTransform,
        isLocked: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.furniture = furniture
        self.bookID = bookID
        self.artworkID = artworkID
        self.transform = transform
        self.isLocked = isLocked
        self.createdAt = createdAt
    }
}

struct HomeArtwork: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var kind: HomeArtworkKind
    var relativePath: String
    var aspectRatio: Float
    let importedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        kind: HomeArtworkKind,
        relativePath: String,
        aspectRatio: Float,
        importedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.relativePath = relativePath
        self.aspectRatio = min(max(aspectRatio, 0.32), 3.2)
        self.importedAt = importedAt
    }
}

struct KokoActivityZone: Codable, Hashable, Sendable {
    var centerX: Float
    var centerZ: Float
    var width: Float
    var depth: Float

    init(centerX: Float = 0, centerZ: Float = 0.25, width: Float = 4.5, depth: Float = 3.5) {
        self.centerX = centerX
        self.centerZ = centerZ
        self.width = width
        self.depth = depth
        clamp()
    }

    mutating func clamp() {
        width = min(max(width, 0.8), 5.4)
        depth = min(max(depth, 0.8), 4.4)
        let halfWidth = width / 2
        let halfDepth = depth / 2
        centerX = min(max(centerX, -2.7 + halfWidth), 2.7 - halfWidth)
        centerZ = min(max(centerZ, -2.2 + halfDepth), 2.1 - halfDepth)
    }
}

struct KokoHomeSettings: Codable, Hashable, Sendable {
    var activityZone: KokoActivityZone
    var welcomesHome: Bool
    var quietWhileReading: Bool
    var roamingEnabled: Bool

    init(
        activityZone: KokoActivityZone = KokoActivityZone(),
        welcomesHome: Bool = true,
        quietWhileReading: Bool = true,
        roamingEnabled: Bool = true
    ) {
        self.activityZone = activityZone
        self.welcomesHome = welcomesHome
        self.quietWhileReading = quietWhileReading
        self.roamingEnabled = roamingEnabled
    }
}

struct HomeWorldState: Codable, Hashable, Sendable {
    static let currentSchema = 1

    var schema: Int
    var theme: HomeRoomTheme
    var placements: [HomePlacement]
    var artworks: [HomeArtwork]
    var koko: KokoHomeSettings
    var hasSeededBooks: Bool

    init(
        schema: Int = HomeWorldState.currentSchema,
        theme: HomeRoomTheme = .sunset,
        placements: [HomePlacement] = HomeWorldState.defaultFurniture,
        artworks: [HomeArtwork] = [],
        koko: KokoHomeSettings = KokoHomeSettings(),
        hasSeededBooks: Bool = false
    ) {
        self.schema = schema
        self.theme = theme
        self.placements = placements
        self.artworks = artworks
        self.koko = koko
        self.hasSeededBooks = hasSeededBooks
    }

    static let defaultFurniture: [HomePlacement] = [
        HomePlacement(kind: .furniture, furniture: .bookshelf, transform: HomeTransform(x: -1.75, z: -2.05, yaw: 0)),
        HomePlacement(kind: .furniture, furniture: .displayCabinet, transform: HomeTransform(x: 0.1, z: -2.08, yaw: 0, scale: 0.92)),
        HomePlacement(kind: .furniture, furniture: .sofa, transform: HomeTransform(x: 1.2, z: 0.35, yaw: -.pi / 7)),
        HomePlacement(kind: .furniture, furniture: .lowTable, transform: HomeTransform(x: 0.05, z: 0.5, yaw: .pi / 20, scale: 0.9)),
        HomePlacement(kind: .furniture, furniture: .rug, transform: HomeTransform(x: 0.35, z: 0.55, yaw: -.pi / 18, scale: 1.18)),
        HomePlacement(kind: .furniture, furniture: .floorLamp, transform: HomeTransform(x: 2.25, z: -1.55, yaw: 0, scale: 0.9)),
        HomePlacement(kind: .furniture, furniture: .plant, transform: HomeTransform(x: 2.38, z: -2.02, yaw: 0, scale: 0.82)),
        HomePlacement(kind: .furniture, furniture: .cushion, transform: HomeTransform(x: 1.35, y: 0.58, z: 0.32, yaw: -.pi / 10, scale: 0.78))
    ]
}

extension HomePlacement {
    var displayName: String {
        if let furniture { return furniture.title }
        if bookID != nil { return "画集" }
        if artworkID != nil { return "私人收藏" }
        return "小家摆件"
    }
}
