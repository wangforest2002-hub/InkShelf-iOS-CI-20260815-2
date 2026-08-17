import ImageIO
import SceneKit
import UIKit

struct HomeRenderableBook: Hashable {
    let id: UUID
    let title: String
    let coverURL: URL?
}

struct HomeRenderableArtwork: Hashable {
    let id: UUID
    let kind: HomeArtworkKind
    let imageURL: URL
    let aspectRatio: Float
}

@MainActor
final class HomeSceneFactory {
    private let imageCache = NSCache<NSURL, UIImage>()

    func makeRoom(theme: HomeRoomTheme) -> SCNNode {
        let palette = HomeScenePalette(theme: theme)
        let room = SCNNode()
        room.name = "room-shell"

        let floor = box(width: 6, height: 0.10, length: 5, color: palette.floor, corner: 0.02)
        floor.position = SCNVector3(0, -0.055, 0)
        floor.name = "room-floor"
        floor.geometry?.firstMaterial?.normal.contents = nil
        room.addChildNode(floor)

        let backWall = box(width: 6.05, height: 3.25, length: 0.10, color: palette.wall, corner: 0.02)
        backWall.position = SCNVector3(0, 1.56, -2.53)
        room.addChildNode(backWall)

        let leftWall = box(width: 0.10, height: 3.25, length: 5.05, color: palette.sideWall, corner: 0.02)
        leftWall.position = SCNVector3(-3.03, 1.56, 0)
        room.addChildNode(leftWall)

        room.addChildNode(makeWindow(palette: palette))
        room.addChildNode(makeCeilingGarland(palette: palette))

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = palette.ambient
        ambient.intensity = theme == .moonlight ? 390 : 560
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        room.addChildNode(ambientNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.color = palette.sun
        sun.intensity = theme == .moonlight ? 520 : 940
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowRadius = 5
        sun.shadowColor = UIColor.black.withAlphaComponent(0.22)
        sun.shadowMapSize = CGSize(width: 1_024, height: 1_024)
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.82, -0.58, -0.16)
        sunNode.position = SCNVector3(2.2, 3.4, 2.2)
        room.addChildNode(sunNode)

        let dust = SCNParticleSystem()
        dust.birthRate = theme == .rain ? 2.5 : 4
        dust.particleLifeSpan = 8
        dust.particleLifeSpanVariation = 3
        dust.particleSize = 0.012
        dust.particleSizeVariation = 0.008
        dust.particleColor = palette.particle
        dust.emitterShape = SCNBox(width: 5.2, height: 2.4, length: 4.2, chamferRadius: 0)
        dust.birthLocation = .volume
        dust.particleVelocity = theme == .rain ? -0.035 : 0.012
        dust.acceleration = SCNVector3(theme == .rain ? 0.01 : 0, theme == .rain ? -0.02 : 0.004, 0)
        dust.blendMode = .additive
        let dustNode = SCNNode()
        dustNode.position = SCNVector3(0, 1.25, 0)
        dustNode.addParticleSystem(dust)
        room.addChildNode(dustNode)

        return room
    }

    func backgroundImage(theme: HomeRoomTheme, size: CGSize = CGSize(width: 900, height: 1_200)) -> UIImage {
        let palette = HomeScenePalette(theme: theme)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [palette.skyTop.cgColor, palette.skyBottom.cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
        }
    }

    func makePlacementNode(
        placement: HomePlacement,
        book: HomeRenderableBook?,
        artwork: HomeRenderableArtwork?
    ) -> SCNNode {
        let root: SCNNode
        switch placement.kind {
        case .furniture:
            root = makeFurniture(placement.furniture ?? .lowTable)
        case .book:
            root = makeBook(book)
        case .artwork:
            root = makeArtwork(artwork)
        }
        root.name = "placement:\(placement.id.uuidString.lowercased())"
        root.userData = [
            "bookID": placement.bookID?.uuidString ?? "",
            "placementKind": placement.kind.rawValue
        ]
        apply(placement.transform, to: root)
        setSelected(false, node: root)
        return root
    }

    func apply(_ transform: HomeTransform, to node: SCNNode) {
        node.position = SCNVector3(transform.x, transform.y, transform.z)
        node.eulerAngles.y = transform.yaw
        node.scale = SCNVector3(transform.scale, transform.scale, transform.scale)
    }

    func setSelected(_ selected: Bool, node: SCNNode) {
        node.childNodes(passingTest: { child, _ in child.geometry != nil }).forEach { child in
            child.geometry?.materials.forEach { material in
                material.emission.contents = selected ? UIColor(red: 0.38, green: 0.62, blue: 1, alpha: 1) : UIColor.black
                material.emission.intensity = selected ? 0.20 : 0
            }
        }
    }

    func makeActivityZone(_ zone: KokoActivityZone) -> SCNNode {
        let root = SCNNode()
        root.name = "koko-activity-zone"
        let plane = SCNPlane(width: CGFloat(zone.width), height: CGFloat(zone.depth))
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemMint.withAlphaComponent(0.13)
        material.emission.contents = UIColor.systemMint.withAlphaComponent(0.16)
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        plane.materials = [material]
        let planeNode = SCNNode(geometry: plane)
        planeNode.eulerAngles.x = -.pi / 2
        planeNode.position.y = 0.018
        root.position = SCNVector3(zone.centerX, 0, zone.centerZ)
        root.addChildNode(planeNode)

        let borderMaterial = materialWith(color: UIColor.systemMint.withAlphaComponent(0.72), roughness: 0.7)
        let horizontal = box(width: CGFloat(zone.width), height: 0.012, length: 0.018, material: borderMaterial)
        let horizontal2 = horizontal.clone()
        horizontal.position = SCNVector3(0, 0.025, zone.depth / 2)
        horizontal2.position = SCNVector3(0, 0.025, -zone.depth / 2)
        root.addChildNode(horizontal)
        root.addChildNode(horizontal2)
        let vertical = box(width: 0.018, height: 0.012, length: CGFloat(zone.depth), material: borderMaterial)
        let vertical2 = vertical.clone()
        vertical.position = SCNVector3(zone.width / 2, 0.025, 0)
        vertical2.position = SCNVector3(-zone.width / 2, 0.025, 0)
        root.addChildNode(vertical)
        root.addChildNode(vertical2)
        return root
    }

    func makeKokoNode() -> SCNNode {
        let wrapper = SCNNode()
        wrapper.name = "koko"
        wrapper.userData = ["isKoko": true]
        if let url = Bundle.main.url(forResource: "Koko", withExtension: "usdz", subdirectory: "Models")
            ?? Bundle.main.url(forResource: "Koko", withExtension: "usdz"),
           let reference = SCNReferenceNode(url: url) {
            reference.load()
            reference.name = "koko-model"
            reference.childNodes(passingTest: { node, _ in node.geometry != nil }).forEach { node in
                node.castsShadow = true
            }
            wrapper.addChildNode(reference)
        } else {
            wrapper.addChildNode(makeKokoFallback())
        }
        let collider = SCNCapsule(capRadius: 0.22, height: 1.58)
        let colliderNode = SCNNode(geometry: collider)
        colliderNode.name = "koko-hit-target"
        colliderNode.opacity = 0.001
        colliderNode.position.y = 0.79
        wrapper.addChildNode(colliderNode)
        return wrapper
    }

    private func makeWindow(palette: HomeScenePalette) -> SCNNode {
        let root = SCNNode()
        root.position = SCNVector3(1.32, 1.85, -2.465)
        let skyPlane = SCNPlane(width: 1.72, height: 1.38)
        let skyMaterial = SCNMaterial()
        skyMaterial.lightingModel = .constant
        skyMaterial.diffuse.contents = backgroundImage(theme: palette.theme, size: CGSize(width: 600, height: 480))
        skyPlane.materials = [skyMaterial]
        root.addChildNode(SCNNode(geometry: skyPlane))

        let frameMaterial = materialWith(color: UIColor.white.withAlphaComponent(0.92), roughness: 0.72)
        for x: Float in [-0.88, 0, 0.88] {
            let bar = box(width: 0.055, height: 1.48, length: 0.045, material: frameMaterial)
            bar.position = SCNVector3(x, 0, 0.035)
            root.addChildNode(bar)
        }
        for y: Float in [-0.72, 0, 0.72] {
            let bar = box(width: 1.82, height: 0.055, length: 0.045, material: frameMaterial)
            bar.position = SCNVector3(0, y, 0.035)
            root.addChildNode(bar)
        }

        let curtainMaterial = materialWith(color: palette.curtain, roughness: 0.88)
        let left = box(width: 0.34, height: 1.65, length: 0.07, material: curtainMaterial, corner: 0.08)
        left.position = SCNVector3(-1.06, 0, 0.09)
        let right = left.clone()
        right.position.x = 1.06
        root.addChildNode(left)
        root.addChildNode(right)

        let sway = SCNAction.sequence([
            .rotateBy(x: 0, y: 0.022, z: 0.008, duration: 3.4),
            .rotateBy(x: 0, y: -0.044, z: -0.016, duration: 6.8),
            .rotateBy(x: 0, y: 0.022, z: 0.008, duration: 3.4)
        ])
        left.runAction(.repeatForever(sway))
        right.runAction(.repeatForever(sway.reversed()))
        return root
    }

    private func makeCeilingGarland(palette: HomeScenePalette) -> SCNNode {
        let root = SCNNode()
        root.position = SCNVector3(-0.25, 2.72, -2.38)
        let wire = SCNCylinder(radius: 0.008, height: 3.3)
        wire.materials = [materialWith(color: UIColor.brown.withAlphaComponent(0.65), roughness: 0.9)]
        let wireNode = SCNNode(geometry: wire)
        wireNode.eulerAngles.z = .pi / 2
        root.addChildNode(wireNode)
        for index in 0..<8 {
            let bulb = SCNSphere(radius: 0.035)
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = index.isMultiple(of: 2) ? palette.sun : palette.particle
            material.emission.contents = material.diffuse.contents
            material.emission.intensity = 0.55
            bulb.materials = [material]
            let node = SCNNode(geometry: bulb)
            node.position = SCNVector3(-1.45 + Float(index) * 0.42, -0.03 - 0.07 * sin(Float(index) * 0.9), 0)
            root.addChildNode(node)
        }
        return root
    }

    private func makeFurniture(_ kind: HomeFurnitureKind) -> SCNNode {
        switch kind {
        case .bookshelf: makeBookshelf()
        case .sofa: makeSofa()
        case .lowTable: makeLowTable()
        case .rug: makeRug()
        case .floorLamp: makeFloorLamp()
        case .plant: makePlant()
        case .displayCabinet: makeDisplayCabinet()
        case .desk: makeDesk()
        case .stool: makeStool()
        case .bed: makeBed()
        case .screen: makeScreen()
        case .cushion: makeCushion()
        }
    }

    private func makeBookshelf() -> SCNNode {
        let root = SCNNode()
        let wood = materialWith(color: UIColor(red: 0.66, green: 0.43, blue: 0.28, alpha: 1), roughness: 0.82)
        let darkWood = materialWith(color: UIColor(red: 0.43, green: 0.25, blue: 0.17, alpha: 1), roughness: 0.86)
        let back = box(width: 1.52, height: 2.12, length: 0.08, material: darkWood, corner: 0.025)
        back.position = SCNVector3(0, 1.06, -0.18)
        root.addChildNode(back)
        for x: Float in [-0.75, 0.75] {
            let side = box(width: 0.11, height: 2.18, length: 0.42, material: wood, corner: 0.025)
            side.position = SCNVector3(x, 1.09, 0)
            root.addChildNode(side)
        }
        for y: Float in [0.06, 0.60, 1.14, 1.68, 2.17] {
            let shelf = box(width: 1.58, height: 0.10, length: 0.44, material: wood, corner: 0.025)
            shelf.position = SCNVector3(0, y, 0)
            root.addChildNode(shelf)
        }
        return root
    }

    private func makeSofa() -> SCNNode {
        let root = SCNNode()
        let fabric = materialWith(color: UIColor(red: 0.79, green: 0.84, blue: 0.96, alpha: 1), roughness: 0.96)
        let highlight = materialWith(color: UIColor(red: 0.89, green: 0.91, blue: 0.99, alpha: 1), roughness: 0.98)
        let seat = box(width: 1.7, height: 0.34, length: 0.75, material: fabric, corner: 0.15)
        seat.position = SCNVector3(0, 0.40, 0)
        root.addChildNode(seat)
        let back = box(width: 1.7, height: 0.82, length: 0.27, material: fabric, corner: 0.16)
        back.position = SCNVector3(0, 0.78, -0.30)
        back.eulerAngles.x = -0.09
        root.addChildNode(back)
        for x: Float in [-0.88, 0.88] {
            let arm = box(width: 0.22, height: 0.58, length: 0.78, material: highlight, corner: 0.11)
            arm.position = SCNVector3(x, 0.46, 0)
            root.addChildNode(arm)
        }
        for x: Float in [-0.39, 0.39] {
            let cushion = box(width: 0.70, height: 0.17, length: 0.64, material: highlight, corner: 0.10)
            cushion.position = SCNVector3(x, 0.62, 0.02)
            root.addChildNode(cushion)
        }
        return root
    }

    private func makeLowTable() -> SCNNode {
        let root = SCNNode()
        let wood = materialWith(color: UIColor(red: 0.73, green: 0.52, blue: 0.36, alpha: 1), roughness: 0.78)
        let top = box(width: 1.18, height: 0.12, length: 0.76, material: wood, corner: 0.07)
        top.position = SCNVector3(0, 0.46, 0)
        root.addChildNode(top)
        for x: Float in [-0.48, 0.48] {
            for z: Float in [-0.27, 0.27] {
                let leg = box(width: 0.09, height: 0.42, length: 0.09, material: wood, corner: 0.025)
                leg.position = SCNVector3(x, 0.21, z)
                root.addChildNode(leg)
            }
        }
        return root
    }

    private func makeRug() -> SCNNode {
        let material = materialWith(color: UIColor(red: 0.98, green: 0.68, blue: 0.64, alpha: 1), roughness: 1)
        let node = box(width: 2.18, height: 0.025, length: 1.48, material: material, corner: 0.18)
        node.position.y = 0.014
        return node
    }

    private func makeFloorLamp() -> SCNNode {
        let root = SCNNode()
        let metal = materialWith(color: UIColor(red: 0.38, green: 0.28, blue: 0.24, alpha: 1), roughness: 0.58)
        let shade = materialWith(color: UIColor(red: 1, green: 0.86, blue: 0.64, alpha: 1), roughness: 0.92)
        let base = SCNCylinder(radius: 0.24, height: 0.06)
        base.materials = [metal]
        let baseNode = SCNNode(geometry: base)
        baseNode.position.y = 0.03
        root.addChildNode(baseNode)
        let stem = SCNCylinder(radius: 0.025, height: 1.36)
        stem.materials = [metal]
        let stemNode = SCNNode(geometry: stem)
        stemNode.position.y = 0.72
        root.addChildNode(stemNode)
        let shadeGeometry = SCNCone(topRadius: 0.18, bottomRadius: 0.38, height: 0.46)
        shadeGeometry.materials = [shade]
        let shadeNode = SCNNode(geometry: shadeGeometry)
        shadeNode.position.y = 1.52
        root.addChildNode(shadeNode)
        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(red: 1, green: 0.72, blue: 0.44, alpha: 1)
        light.intensity = 430
        light.attenuationStartDistance = 0.4
        light.attenuationEndDistance = 3.2
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position.y = 1.40
        root.addChildNode(lightNode)
        return root
    }

    private func makePlant() -> SCNNode {
        let root = SCNNode()
        let potMaterial = materialWith(color: UIColor(red: 0.78, green: 0.52, blue: 0.39, alpha: 1), roughness: 0.92)
        let leafMaterial = materialWith(color: UIColor(red: 0.29, green: 0.65, blue: 0.48, alpha: 1), roughness: 0.86)
        let pot = SCNCone(topRadius: 0.20, bottomRadius: 0.27, height: 0.42)
        pot.materials = [potMaterial]
        let potNode = SCNNode(geometry: pot)
        potNode.position.y = 0.21
        root.addChildNode(potNode)
        for index in 0..<8 {
            let leaf = SCNSphere(radius: 0.18)
            leaf.segmentCount = 18
            leaf.materials = [leafMaterial]
            let node = SCNNode(geometry: leaf)
            let angle = Float(index) * .pi * 2 / 8
            node.scale = SCNVector3(0.55, 1.65, 0.38)
            node.position = SCNVector3(cos(angle) * 0.22, 0.58 + Float(index % 3) * 0.18, sin(angle) * 0.22)
            node.eulerAngles.z = cos(angle) * 0.55
            root.addChildNode(node)
            let sway = SCNAction.sequence([
                .rotateBy(x: 0.015, y: 0.025, z: -0.02, duration: 3.8 + Double(index) * 0.12),
                .rotateBy(x: -0.03, y: -0.05, z: 0.04, duration: 7.6 + Double(index) * 0.12),
                .rotateBy(x: 0.015, y: 0.025, z: -0.02, duration: 3.8 + Double(index) * 0.12)
            ])
            node.runAction(.repeatForever(sway))
        }
        return root
    }

    private func makeDisplayCabinet() -> SCNNode {
        let root = SCNNode()
        let frame = materialWith(color: UIColor(red: 0.69, green: 0.50, blue: 0.36, alpha: 1), roughness: 0.78)
        let glass = materialWith(color: UIColor(red: 0.72, green: 0.91, blue: 1, alpha: 0.20), roughness: 0.12, transparency: 0.27)
        let back = box(width: 1.08, height: 1.76, length: 0.08, material: frame, corner: 0.03)
        back.position = SCNVector3(0, 0.88, -0.20)
        root.addChildNode(back)
        for x: Float in [-0.54, 0.54] {
            let side = box(width: 0.08, height: 1.82, length: 0.45, material: frame, corner: 0.02)
            side.position = SCNVector3(x, 0.91, 0)
            root.addChildNode(side)
        }
        for y: Float in [0.05, 0.62, 1.18, 1.79] {
            let shelf = box(width: 1.16, height: 0.07, length: 0.45, material: frame, corner: 0.02)
            shelf.position = SCNVector3(0, y, 0)
            root.addChildNode(shelf)
        }
        let door = box(width: 1.04, height: 1.67, length: 0.025, material: glass, corner: 0.025)
        door.position = SCNVector3(0, 0.91, 0.23)
        root.addChildNode(door)
        return root
    }

    private func makeDesk() -> SCNNode {
        let root = SCNNode()
        let wood = materialWith(color: UIColor(red: 0.76, green: 0.56, blue: 0.39, alpha: 1), roughness: 0.82)
        let top = box(width: 1.45, height: 0.11, length: 0.72, material: wood, corner: 0.045)
        top.position.y = 0.76
        root.addChildNode(top)
        for x: Float in [-0.60, 0.60] {
            for z: Float in [-0.26, 0.26] {
                let leg = box(width: 0.09, height: 0.72, length: 0.09, material: wood, corner: 0.025)
                leg.position = SCNVector3(x, 0.36, z)
                root.addChildNode(leg)
            }
        }
        return root
    }

    private func makeStool() -> SCNNode {
        let root = SCNNode()
        let fabric = materialWith(color: UIColor(red: 0.80, green: 0.68, blue: 0.95, alpha: 1), roughness: 0.96)
        let wood = materialWith(color: UIColor(red: 0.58, green: 0.38, blue: 0.26, alpha: 1), roughness: 0.86)
        let seat = SCNCylinder(radius: 0.37, height: 0.18)
        seat.radialSegmentCount = 32
        seat.materials = [fabric]
        let seatNode = SCNNode(geometry: seat)
        seatNode.position.y = 0.48
        root.addChildNode(seatNode)
        for x: Float in [-0.23, 0.23] {
            for z: Float in [-0.17, 0.17] {
                let leg = box(width: 0.065, height: 0.44, length: 0.065, material: wood, corner: 0.02)
                leg.position = SCNVector3(x, 0.22, z)
                root.addChildNode(leg)
            }
        }
        return root
    }

    private func makeBed() -> SCNNode {
        let root = SCNNode()
        let wood = materialWith(color: UIColor(red: 0.65, green: 0.46, blue: 0.32, alpha: 1), roughness: 0.85)
        let sheet = materialWith(color: UIColor(red: 0.91, green: 0.89, blue: 1, alpha: 1), roughness: 0.98)
        let blanket = materialWith(color: UIColor(red: 0.62, green: 0.80, blue: 0.93, alpha: 1), roughness: 0.98)
        let frame = box(width: 1.45, height: 0.22, length: 2.05, material: wood, corner: 0.06)
        frame.position.y = 0.19
        root.addChildNode(frame)
        let mattress = box(width: 1.34, height: 0.28, length: 1.92, material: sheet, corner: 0.14)
        mattress.position.y = 0.40
        root.addChildNode(mattress)
        let cover = box(width: 1.28, height: 0.10, length: 1.18, material: blanket, corner: 0.09)
        cover.position = SCNVector3(0, 0.59, 0.30)
        root.addChildNode(cover)
        let pillow = box(width: 0.82, height: 0.18, length: 0.42, material: sheet, corner: 0.14)
        pillow.position = SCNVector3(0, 0.61, -0.68)
        root.addChildNode(pillow)
        return root
    }

    private func makeScreen() -> SCNNode {
        let root = SCNNode()
        let wood = materialWith(color: UIColor(red: 0.49, green: 0.31, blue: 0.22, alpha: 1), roughness: 0.86)
        let paper = materialWith(color: UIColor(red: 1, green: 0.94, blue: 0.83, alpha: 0.90), roughness: 0.98, transparency: 0.92)
        for panel in 0..<3 {
            let x = -0.72 + Float(panel) * 0.72
            let sheet = box(width: 0.62, height: 1.55, length: 0.025, material: paper, corner: 0.015)
            sheet.position = SCNVector3(x, 0.83, 0)
            root.addChildNode(sheet)
            for edge: Float in [-0.34, 0.34] {
                let bar = box(width: 0.045, height: 1.68, length: 0.055, material: wood, corner: 0.012)
                bar.position = SCNVector3(x + edge, 0.84, 0)
                root.addChildNode(bar)
            }
        }
        return root
    }

    private func makeCushion() -> SCNNode {
        let material = materialWith(color: UIColor(red: 1, green: 0.73, blue: 0.75, alpha: 1), roughness: 1)
        let node = box(width: 0.52, height: 0.42, length: 0.16, material: material, corner: 0.15)
        node.position.y = 0.22
        return node
    }

    private func makeBook(_ book: HomeRenderableBook?) -> SCNNode {
        let root = SCNNode()
        let image = book?.coverURL.flatMap(loadImage)
        let aspect = image.map { Float($0.size.width / max($0.size.height, 1)) } ?? 0.70
        let height: CGFloat = 0.48
        let width = height * CGFloat(min(max(aspect, 0.42), 1.60))
        let geometry = SCNBox(width: width, height: height, length: 0.055, chamferRadius: 0.012)
        let cover = materialWith(color: UIColor(red: 0.68, green: 0.80, blue: 1, alpha: 1), roughness: 0.78)
        cover.diffuse.contents = image ?? placeholderCover(title: book?.title ?? "画集")
        cover.diffuse.wrapS = .clamp
        cover.diffuse.wrapT = .clamp
        let pages = materialWith(color: UIColor(red: 0.98, green: 0.95, blue: 0.87, alpha: 1), roughness: 0.96)
        let back = materialWith(color: UIColor(red: 0.55, green: 0.64, blue: 0.84, alpha: 1), roughness: 0.84)
        geometry.materials = [cover, pages, back, pages, pages, pages]
        let bookNode = SCNNode(geometry: geometry)
        bookNode.position.y = Float(height / 2)
        bookNode.castsShadow = true
        root.addChildNode(bookNode)
        return root
    }

    private func makeArtwork(_ artwork: HomeRenderableArtwork?) -> SCNNode {
        guard let artwork else {
            return makeArtworkPlaceholder()
        }
        let root = SCNNode()
        let image = loadImage(artwork.imageURL)
        let aspect = CGFloat(min(max(artwork.aspectRatio, 0.32), 3.2))
        switch artwork.kind {
        case .poster:
            let height: CGFloat = 0.86
            let width = height * aspect
            let frameMaterial = materialWith(color: UIColor(red: 0.49, green: 0.31, blue: 0.22, alpha: 1), roughness: 0.82)
            let frame = box(width: width + 0.10, height: height + 0.10, length: 0.045, material: frameMaterial, corner: 0.025)
            root.addChildNode(frame)
            let plane = SCNPlane(width: width, height: height)
            let artMaterial = SCNMaterial()
            artMaterial.lightingModel = .physicallyBased
            artMaterial.diffuse.contents = image
            artMaterial.roughness.contents = 0.72
            artMaterial.isDoubleSided = true
            plane.materials = [artMaterial]
            let artNode = SCNNode(geometry: plane)
            artNode.position.z = 0.026
            root.addChildNode(artNode)
        case .standee, .figure:
            let height: CGFloat = artwork.kind == .figure ? 0.72 : 0.92
            let width = height * aspect
            let plane = SCNPlane(width: width, height: height)
            let artMaterial = SCNMaterial()
            artMaterial.lightingModel = .physicallyBased
            artMaterial.diffuse.contents = image
            artMaterial.transparent.contents = image
            artMaterial.isDoubleSided = true
            artMaterial.writesToDepthBuffer = true
            plane.materials = [artMaterial]
            let artNode = SCNNode(geometry: plane)
            artNode.position.y = Float(height / 2) + 0.08
            root.addChildNode(artNode)
            let baseColor = artwork.kind == .figure
                ? UIColor(red: 0.46, green: 0.62, blue: 0.95, alpha: 1)
                : UIColor(red: 0.82, green: 0.93, blue: 1, alpha: 0.68)
            let base = SCNCylinder(radius: max(0.18, width * 0.35), height: 0.07)
            base.radialSegmentCount = 32
            base.materials = [materialWith(color: baseColor, roughness: 0.28, transparency: artwork.kind == .standee ? 0.72 : 1)]
            let baseNode = SCNNode(geometry: base)
            baseNode.position.y = 0.035
            root.addChildNode(baseNode)
        }
        return root
    }

    private func makeArtworkPlaceholder() -> SCNNode {
        let material = materialWith(color: UIColor.systemPink.withAlphaComponent(0.55), roughness: 0.8)
        let node = box(width: 0.46, height: 0.70, length: 0.04, material: material, corner: 0.04)
        node.position.y = 0.35
        return node
    }

    private func makeKokoFallback() -> SCNNode {
        let root = SCNNode()
        root.name = "koko-fallback"
        let hair = materialWith(color: UIColor(red: 0.08, green: 0.10, blue: 0.20, alpha: 1), roughness: 0.92)
        let skin = materialWith(color: UIColor(red: 1, green: 0.82, blue: 0.74, alpha: 1), roughness: 0.96)
        let dress = materialWith(color: UIColor(red: 0.35, green: 0.48, blue: 0.83, alpha: 1), roughness: 0.92)
        let body = SCNCapsule(capRadius: 0.22, height: 0.78)
        body.materials = [dress]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position.y = 0.87
        root.addChildNode(bodyNode)
        let head = SCNSphere(radius: 0.27)
        head.materials = [skin]
        let headNode = SCNNode(geometry: head)
        headNode.position.y = 1.45
        root.addChildNode(headNode)
        let hairBack = SCNSphere(radius: 0.30)
        hairBack.materials = [hair]
        let hairNode = SCNNode(geometry: hairBack)
        hairNode.scale = SCNVector3(1, 1.24, 0.82)
        hairNode.position = SCNVector3(0, 1.49, -0.07)
        root.addChildNode(hairNode)
        return root
    }

    private func loadImage(_ url: URL) -> UIImage? {
        if let cached = imageCache.object(forKey: url as NSURL) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        imageCache.setObject(image, forKey: url as NSURL, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    private func placeholderCover(title: String) -> UIImage {
        let size = CGSize(width: 420, height: 600)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [
                UIColor(red: 0.68, green: 0.88, blue: 1, alpha: 1).cgColor,
                UIColor(red: 0.83, green: 0.73, blue: 1, alpha: 1).cgColor
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            (String(title.prefix(20)) as NSString).draw(
                in: CGRect(x: 36, y: 220, width: size.width - 72, height: 180),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 34, weight: .semibold),
                    .foregroundColor: UIColor(red: 0.12, green: 0.15, blue: 0.30, alpha: 1),
                    .paragraphStyle: paragraph
                ]
            )
        }
    }

    private func materialWith(
        color: UIColor,
        roughness: CGFloat,
        transparency: CGFloat = 1
    ) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = roughness
        material.metalness.contents = 0
        material.transparency = transparency
        material.isDoubleSided = transparency < 1
        return material
    }

    private func box(
        width: CGFloat,
        height: CGFloat,
        length: CGFloat,
        color: UIColor,
        corner: CGFloat = 0
    ) -> SCNNode {
        box(width: width, height: height, length: length, material: materialWith(color: color, roughness: 0.84), corner: corner)
    }

    private func box(
        width: CGFloat,
        height: CGFloat,
        length: CGFloat,
        material: SCNMaterial,
        corner: CGFloat = 0
    ) -> SCNNode {
        let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: corner)
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.castsShadow = true
        return node
    }
}

private struct HomeScenePalette {
    let theme: HomeRoomTheme

    var floor: UIColor {
        switch theme {
        case .sunset: UIColor(red: 0.73, green: 0.53, blue: 0.38, alpha: 1)
        case .rain: UIColor(red: 0.55, green: 0.50, blue: 0.47, alpha: 1)
        case .moonlight: UIColor(red: 0.26, green: 0.23, blue: 0.34, alpha: 1)
        }
    }

    var wall: UIColor {
        switch theme {
        case .sunset: UIColor(red: 1, green: 0.92, blue: 0.80, alpha: 1)
        case .rain: UIColor(red: 0.80, green: 0.90, blue: 0.89, alpha: 1)
        case .moonlight: UIColor(red: 0.25, green: 0.25, blue: 0.40, alpha: 1)
        }
    }

    var sideWall: UIColor {
        switch theme {
        case .sunset: UIColor(red: 0.95, green: 0.82, blue: 0.72, alpha: 1)
        case .rain: UIColor(red: 0.70, green: 0.81, blue: 0.83, alpha: 1)
        case .moonlight: UIColor(red: 0.18, green: 0.19, blue: 0.33, alpha: 1)
        }
    }

    var curtain: UIColor {
        switch theme {
        case .sunset: UIColor(red: 0.91, green: 0.66, blue: 0.68, alpha: 1)
        case .rain: UIColor(red: 0.55, green: 0.76, blue: 0.76, alpha: 1)
        case .moonlight: UIColor(red: 0.47, green: 0.42, blue: 0.70, alpha: 1)
        }
    }

    var ambient: UIColor {
        switch theme {
        case .sunset: UIColor(red: 1, green: 0.78, blue: 0.62, alpha: 1)
        case .rain: UIColor(red: 0.64, green: 0.80, blue: 0.86, alpha: 1)
        case .moonlight: UIColor(red: 0.45, green: 0.51, blue: 0.80, alpha: 1)
        }
    }

    var sun: UIColor {
        switch theme {
        case .sunset: UIColor(red: 1, green: 0.66, blue: 0.42, alpha: 1)
        case .rain: UIColor(red: 0.70, green: 0.84, blue: 0.95, alpha: 1)
        case .moonlight: UIColor(red: 0.56, green: 0.65, blue: 1, alpha: 1)
        }
    }

    var particle: UIColor {
        switch theme {
        case .sunset: UIColor(red: 1, green: 0.86, blue: 0.58, alpha: 0.52)
        case .rain: UIColor(red: 0.70, green: 0.90, blue: 1, alpha: 0.40)
        case .moonlight: UIColor(red: 0.75, green: 0.72, blue: 1, alpha: 0.46)
        }
    }

    var skyTop: UIColor {
        switch theme {
        case .sunset: UIColor(red: 0.61, green: 0.83, blue: 1, alpha: 1)
        case .rain: UIColor(red: 0.39, green: 0.52, blue: 0.64, alpha: 1)
        case .moonlight: UIColor(red: 0.06, green: 0.08, blue: 0.20, alpha: 1)
        }
    }

    var skyBottom: UIColor {
        switch theme {
        case .sunset: UIColor(red: 1, green: 0.72, blue: 0.61, alpha: 1)
        case .rain: UIColor(red: 0.63, green: 0.72, blue: 0.77, alpha: 1)
        case .moonlight: UIColor(red: 0.25, green: 0.19, blue: 0.39, alpha: 1)
        }
    }
}

private extension SCNNode {
    func childNodes(passingTest test: (SCNNode, UnsafeMutablePointer<ObjCBool>) -> Bool) -> [SCNNode] {
        var result: [SCNNode] = []
        enumerateChildNodes { node, stop in
            if test(node, stop) { result.append(node) }
        }
        return result
    }
}
