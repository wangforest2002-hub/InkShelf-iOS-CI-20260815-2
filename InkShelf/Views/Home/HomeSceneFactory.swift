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
    private var generatedTextureCache: [String: UIImage] = [:]

    func makeRoom(theme: HomeRoomTheme) -> SCNNode {
        let palette = HomeScenePalette(theme: theme)
        let room = SCNNode()
        room.name = "room-shell"

        let floorMaterial = materialWith(color: palette.floor, roughness: 0.72)
        floorMaterial.diffuse.contents = woodTexture(palette: palette)
        floorMaterial.diffuse.wrapS = .repeat
        floorMaterial.diffuse.wrapT = .repeat
        floorMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(3.2, 2.6, 1)
        let floor = box(width: 6.12, height: 0.12, length: 5.12, material: floorMaterial, corner: 0.035)
        floor.position = SCNVector3(0, -0.065, 0)
        floor.name = "room-floor"
        room.addChildNode(floor)

        let wallpaper = materialWith(color: palette.wall, roughness: 0.94)
        wallpaper.diffuse.contents = wallpaperTexture(palette: palette)
        wallpaper.diffuse.wrapS = .repeat
        wallpaper.diffuse.wrapT = .repeat
        wallpaper.diffuse.contentsTransform = SCNMatrix4MakeScale(3.0, 2.0, 1)
        let backWall = box(width: 6.16, height: 3.35, length: 0.12, material: wallpaper, corner: 0.025)
        backWall.position = SCNVector3(0, 1.62, -2.56)
        backWall.name = "room-back-wall"
        room.addChildNode(backWall)

        let sideMaterial = materialWith(color: palette.sideWall, roughness: 0.94)
        sideMaterial.diffuse.contents = wallpaperTexture(palette: palette, side: true)
        sideMaterial.diffuse.wrapS = .repeat
        sideMaterial.diffuse.wrapT = .repeat
        sideMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(2.5, 2.0, 1)
        let leftWall = box(width: 0.12, height: 3.35, length: 5.16, material: sideMaterial, corner: 0.025)
        leftWall.position = SCNVector3(-3.08, 1.62, 0)
        leftWall.name = "room-left-wall"
        room.addChildNode(leftWall)

        let rightWall = box(width: 0.12, height: 3.35, length: 5.16, material: wallpaper, corner: 0.025)
        rightWall.position = SCNVector3(3.08, 1.62, 0)
        rightWall.name = "room-right-wall"
        room.addChildNode(rightWall)

        let frontWall = box(width: 6.16, height: 3.35, length: 0.12, material: sideMaterial, corner: 0.025)
        frontWall.position = SCNVector3(0, 1.62, 2.56)
        frontWall.name = "room-front-wall"
        room.addChildNode(frontWall)

        let ceilingMaterial = materialWith(color: palette.wall, roughness: 0.98)
        let ceiling = box(width: 6.16, height: 0.10, length: 5.16, material: ceilingMaterial, corner: 0.02)
        ceiling.position = SCNVector3(0, 3.28, 0)
        ceiling.name = "room-ceiling"
        ceiling.castsShadow = false
        room.addChildNode(ceiling)

        room.addChildNode(makeEntryway(palette: palette))

        addArchitecturalTrim(to: room, palette: palette)
        room.addChildNode(makeWindow(palette: palette))
        room.addChildNode(makeWindowSeat(palette: palette))
        room.addChildNode(makeWallReadingNook(palette: palette))
        room.addChildNode(makeCeilingGarland(palette: palette))
        room.addChildNode(makePendantLight(palette: palette))

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = palette.ambient
        ambient.intensity = theme == .moonlight ? 170 : 235
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        room.addChildNode(ambientNode)

        let windowLight = SCNLight()
        windowLight.type = .directional
        windowLight.color = palette.sun
        windowLight.intensity = theme == .moonlight ? 280 : 430
        windowLight.castsShadow = true
        windowLight.shadowMode = .deferred
        windowLight.shadowRadius = 7
        windowLight.shadowColor = UIColor.black.withAlphaComponent(0.20)
        windowLight.shadowMapSize = CGSize(width: 2_048, height: 2_048)
        windowLight.orthographicScale = 7.5
        let windowLightNode = SCNNode()
        windowLightNode.name = "room-window-light"
        windowLightNode.light = windowLight
        windowLightNode.eulerAngles = SCNVector3(-0.78, -0.86, -0.12)
        windowLightNode.position = SCNVector3(2.4, 3.1, -0.4)
        room.addChildNode(windowLightNode)

        let softFill = SCNLight()
        softFill.type = .omni
        softFill.color = palette.fill
        softFill.intensity = theme == .moonlight ? 105 : 145
        softFill.attenuationStartDistance = 1.0
        softFill.attenuationEndDistance = 6.5
        let softFillNode = SCNNode()
        softFillNode.name = "room-soft-fill"
        softFillNode.light = softFill
        softFillNode.position = SCNVector3(-1.8, 2.35, 1.4)
        room.addChildNode(softFillNode)

        let dust = SCNParticleSystem()
        dust.birthRate = theme == .rain ? 1.6 : 2.4
        dust.particleLifeSpan = 8
        dust.particleLifeSpanVariation = 3
        dust.particleSize = 0.008
        dust.particleSizeVariation = 0.005
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

    private func makeEntryway(palette: HomeScenePalette) -> SCNNode {
        let root = SCNNode()
        root.name = "room-entryway"
        root.position = SCNVector3(1.76, 0, 2.48)
        let charcoal = materialWith(color: palette.windowFrame, roughness: 0.62)
        let door = box(width: 1.12, height: 2.26, length: 0.075, material: charcoal, corner: 0.028)
        door.position = SCNVector3(0, 1.13, 0)
        root.addChildNode(door)
        let inset = box(width: 0.91, height: 2.04, length: 0.028, material: materialWith(color: palette.woodShadow, roughness: 0.74), corner: 0.020)
        inset.position = SCNVector3(0, 1.13, -0.055)
        root.addChildNode(inset)
        let handle = SCNCylinder(radius: 0.025, height: 0.20)
        handle.radialSegmentCount = 18
        handle.materials = [materialWith(color: UIColor(red: 0.72, green: 0.67, blue: 0.55, alpha: 1), roughness: 0.35)]
        let handleNode = SCNNode(geometry: handle)
        handleNode.eulerAngles.x = .pi / 2
        handleNode.position = SCNVector3(-0.38, 1.08, -0.105)
        root.addChildNode(handleNode)
        let genkan = box(width: 1.42, height: 0.025, length: 0.78, material: materialWith(color: UIColor(red: 0.47, green: 0.48, blue: 0.46, alpha: 1), roughness: 0.96), corner: 0.02)
        genkan.position = SCNVector3(0, -0.04, -0.35)
        root.addChildNode(genkan)
        return root
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
        let platform = SCNCylinder(radius: 0.38, height: 0.018)
        platform.radialSegmentCount = 48
        let platformMaterial = materialWith(
            color: UIColor(red: 0.58, green: 0.82, blue: 1, alpha: 0.42),
            roughness: 0.32,
            transparency: 0.52
        )
        platformMaterial.emission.contents = UIColor(red: 0.36, green: 0.70, blue: 1, alpha: 0.32)
        platformMaterial.emission.intensity = 0.28
        platform.materials = [platformMaterial]
        let platformNode = SCNNode(geometry: platform)
        platformNode.name = "koko-platform"
        platformNode.position.y = 0.009
        wrapper.addChildNode(platformNode)

        if let url = Bundle.main.url(forResource: "Koko", withExtension: "usdz", subdirectory: "Models")
            ?? Bundle.main.url(forResource: "Koko", withExtension: "usdz"),
           let importedScene = try? SCNScene(url: url, options: [
               .checkConsistency: true,
               .createNormalsIfAbsent: true
           ]) {
            let importedRoot = importedScene.rootNode.clone()
            importedRoot.name = "koko-model"
            importedRoot.scale = SCNVector3(1.08, 1.08, 1.08)
            let renderableNodes = importedRoot.childNodes(passingTest: { node, _ in node.geometry != nil })
            renderableNodes.forEach { node in
                node.opacity = 1
                node.castsShadow = true
                node.geometry?.materials.forEach { material in
                    let materialName = material.name ?? ""
                    if let texture = kokoTexture(named: materialName) {
                        material.diffuse.contents = texture
                        material.diffuse.wrapS = .repeat
                        material.diffuse.wrapT = .repeat
                    }
                    let needsTransparency = kokoMaterialNeedsTransparency(materialName)
                    material.blendMode = needsTransparency ? .alpha : .replace
                    material.transparency = 1
                    material.transparencyMode = .aOne
                    material.readsFromDepthBuffer = true
                    material.writesToDepthBuffer = !needsTransparency
                    material.isDoubleSided = true
                }
            }
            if renderableNodes.isEmpty {
                let fallback = makeKokoFallback()
                fallback.name = "koko-model-fallback"
                wrapper.addChildNode(fallback)
            } else {
                wrapper.addChildNode(importedRoot)
            }
        } else {
            let fallback = makeKokoFallback()
            fallback.name = "koko-model-fallback"
            wrapper.addChildNode(fallback)
        }
        let collider = SCNCapsule(capRadius: 0.24, height: 1.72)
        let colliderNode = SCNNode(geometry: collider)
        colliderNode.name = "koko-hit-target"
        colliderNode.opacity = 0.001
        colliderNode.position.y = 0.86
        wrapper.addChildNode(colliderNode)
        return wrapper
    }

    private func kokoTexture(named materialName: String?) -> UIImage? {
        guard let materialName, !materialName.isEmpty else { return nil }
        let locations = ["Models/KokoTextures", "KokoTextures", nil]
        for subdirectory in locations {
            if let url = Bundle.main.url(
                forResource: materialName,
                withExtension: "png",
                subdirectory: subdirectory
            ), let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }
        return nil
    }

    private func kokoMaterialNeedsTransparency(_ materialName: String) -> Bool {
        [
            "EyeExtra", "EyeHighlight", "EyeIris",
            "FaceBrow", "FaceEyelash", "FaceEyeline",
            "HairBack"
        ].contains { materialName.localizedCaseInsensitiveContains($0) }
    }

    private func addArchitecturalTrim(to room: SCNNode, palette: HomeScenePalette) {
        let timber = materialWith(color: palette.lightWood, roughness: 0.76)
        let darkEdge = materialWith(color: palette.woodShadow, roughness: 0.68)

        let backBase = box(width: 6.12, height: 0.10, length: 0.075, material: timber, corner: 0.018)
        backBase.position = SCNVector3(0, 0.05, -2.43)
        room.addChildNode(backBase)
        let leftBase = box(width: 0.075, height: 0.10, length: 5.08, material: timber, corner: 0.018)
        leftBase.position = SCNVector3(-2.95, 0.05, 0)
        room.addChildNode(leftBase)

        let ceilingEdge = box(width: 6.10, height: 0.105, length: 0.08, material: timber, corner: 0.018)
        ceilingEdge.position = SCNVector3(0, 3.10, -2.43)
        room.addChildNode(ceilingEdge)
        let ceilingSide = box(width: 0.08, height: 0.105, length: 5.08, material: timber, corner: 0.018)
        ceilingSide.position = SCNVector3(-2.95, 3.10, 0)
        room.addChildNode(ceilingSide)

        let windowValance = box(width: 3.64, height: 0.075, length: 0.16, material: timber, corner: 0.018)
        windowValance.position = SCNVector3(1.08, 3.03, -2.34)
        windowValance.name = "room-window-valance"
        room.addChildNode(windowValance)

        let floorBorder = materialWith(color: palette.floorBorder, roughness: 0.70)
        let backInlay = box(width: 5.82, height: 0.014, length: 0.055, material: floorBorder, corner: 0.012)
        backInlay.position = SCNVector3(0, 0.008, -2.34)
        room.addChildNode(backInlay)
        let leftInlay = box(width: 0.055, height: 0.014, length: 4.82, material: floorBorder, corner: 0.012)
        leftInlay.position = SCNVector3(-2.84, 0.008, 0)
        room.addChildNode(leftInlay)

        let threshold = box(width: 3.54, height: 0.045, length: 0.26, material: darkEdge, corner: 0.018)
        threshold.position = SCNVector3(1.08, 0.026, -2.20)
        threshold.name = "room-balcony-threshold"
        room.addChildNode(threshold)

        room.addChildNode(makeShojiPartition(palette: palette))
        room.addChildNode(makeTatamiCorner(palette: palette))
    }

    private func makeShojiPartition(palette: HomeScenePalette) -> SCNNode {
        let root = SCNNode()
        root.name = "room-shoji-partition"
        root.position = SCNVector3(-2.88, 1.26, 1.38)
        root.eulerAngles.y = .pi / 2
        let frame = materialWith(color: palette.lightWood, roughness: 0.78)
        let paper = SCNMaterial()
        paper.lightingModel = .physicallyBased
        paper.diffuse.contents = shojiPaperTexture()
        paper.roughness.contents = 0.98
        paper.transparency = 0.90
        paper.isDoubleSided = true
        let panel = SCNPlane(width: 1.72, height: 2.34)
        panel.materials = [paper]
        let panelNode = SCNNode(geometry: panel)
        root.addChildNode(panelNode)
        for x: Float in [-0.88, -0.44, 0, 0.44, 0.88] {
            let vertical = box(width: x == -0.88 || x == 0.88 ? 0.055 : 0.028, height: 2.42, length: 0.045, material: frame, corner: 0.008)
            vertical.position = SCNVector3(x, 0, 0.03)
            root.addChildNode(vertical)
        }
        for y: Float in [-1.20, -0.80, -0.40, 0, 0.40, 0.80, 1.20] {
            let horizontal = box(width: 1.82, height: y == -1.20 || y == 1.20 ? 0.055 : 0.028, length: 0.045, material: frame, corner: 0.008)
            horizontal.position = SCNVector3(0, y, 0.03)
            root.addChildNode(horizontal)
        }
        return root
    }

    private func makeTatamiCorner(palette: HomeScenePalette) -> SCNNode {
        let root = SCNNode()
        root.name = "room-tatami-corner"
        root.position = SCNVector3(-1.78, 0, 1.46)
        let straw = materialWith(color: palette.tatami, roughness: 0.98)
        straw.diffuse.contents = tatamiTexture(base: palette.tatami)
        straw.diffuse.wrapS = .repeat
        straw.diffuse.wrapT = .repeat
        straw.diffuse.contentsTransform = SCNMatrix4MakeScale(1.3, 3.0, 1)
        let border = materialWith(color: palette.tatamiBorder, roughness: 0.90)
        for index in 0..<2 {
            let mat = box(width: 0.76, height: 0.045, length: 1.78, material: straw, corner: 0.018)
            mat.position = SCNVector3(-0.39 + Float(index) * 0.78, 0.026, 0)
            mat.name = "room-tatami-mat-\(index)"
            root.addChildNode(mat)
            for x: Float in [-0.38, 0.38] {
                let edge = box(width: 0.035, height: 0.052, length: 1.80, material: border, corner: 0.008)
                edge.position = SCNVector3(mat.position.x + x, 0.030, 0)
                root.addChildNode(edge)
            }
        }
        return root
    }

    private func makeWindow(palette: HomeScenePalette) -> SCNNode {
        let root = SCNNode()
        root.name = "room-balcony-window"
        root.position = SCNVector3(1.08, 1.74, -2.455)

        let scenery = SCNPlane(width: 3.34, height: 1.67)
        let sceneryMaterial = SCNMaterial()
        sceneryMaterial.lightingModel = .constant
        sceneryMaterial.diffuse.contents = panoramaContents(theme: palette.theme)
        sceneryMaterial.diffuse.wrapS = .clamp
        sceneryMaterial.diffuse.wrapT = .clamp
        scenery.materials = [sceneryMaterial]
        let sceneryNode = SCNNode(geometry: scenery)
        sceneryNode.name = "room-outdoor-panorama"
        sceneryNode.position.z = 0.012
        sceneryNode.castsShadow = false
        root.addChildNode(sceneryNode)

        let glass = SCNPlane(width: 3.28, height: 1.62)
        let glassMaterial = materialWith(color: palette.glass, roughness: 0.08, transparency: 0.025)
        glassMaterial.blendMode = .alpha
        glassMaterial.writesToDepthBuffer = false
        glassMaterial.metalness.contents = 0.08
        glassMaterial.specular.contents = UIColor.white
        glass.materials = [glassMaterial]
        let glassNode = SCNNode(geometry: glass)
        glassNode.name = "room-window-glass"
        glassNode.position.z = 0.052
        root.addChildNode(glassNode)

        let frameMaterial = materialWith(color: palette.windowFrame, roughness: 0.50)
        for x: Float in [-1.70, 0, 1.70] {
            let bar = box(width: x == 0 ? 0.055 : 0.085, height: 1.84, length: 0.105, material: frameMaterial, corner: 0.018)
            bar.position = SCNVector3(x, 0, 0.11)
            root.addChildNode(bar)
        }
        for y: Float in [-0.90, 0, 0.90] {
            let bar = box(width: 3.48, height: y == 0 ? 0.05 : 0.085, length: 0.105, material: frameMaterial, corner: 0.018)
            bar.position = SCNVector3(0, y, 0.11)
            root.addChildNode(bar)
        }

        let sill = box(width: 3.56, height: 0.105, length: 0.34, material: frameMaterial, corner: 0.028)
        sill.position = SCNVector3(0, -0.94, 0.18)
        root.addChildNode(sill)

        let balconyMaterial = materialWith(color: palette.metal, roughness: 0.58)
        let topRail = box(width: 3.16, height: 0.055, length: 0.055, material: balconyMaterial, corner: 0.016)
        topRail.position = SCNVector3(0, -0.60, -0.015)
        root.addChildNode(topRail)
        for x: Float in stride(from: -1.48, through: 1.48, by: 0.30) {
            let rail = box(width: 0.022, height: 0.62, length: 0.035, material: balconyMaterial, corner: 0.008)
            rail.position = SCNVector3(x, -0.87, -0.012)
            root.addChildNode(rail)
        }

        let sheer = SCNPlane(width: 0.42, height: 1.76)
        let sheerMaterial = materialWith(color: UIColor.white, roughness: 0.94, transparency: 0.30)
        sheerMaterial.blendMode = .alpha
        sheerMaterial.writesToDepthBuffer = false
        sheer.materials = [sheerMaterial]
        let sheerNode = SCNNode(geometry: sheer)
        sheerNode.name = "room-sheer-curtain"
        sheerNode.position = SCNVector3(-1.49, 0, 0.18)
        root.addChildNode(sheerNode)
        return root
    }

    private func makeWindowSeat(palette: HomeScenePalette) -> SCNNode {
        let root = SCNNode()
        root.name = "room-window-seat"
        root.position = SCNVector3(1.45, 0, -2.13)
        let wood = materialWith(color: palette.lightWood, roughness: 0.76)
        let fabric = materialWith(color: palette.seatFabric, roughness: 0.96)
        fabric.diffuse.contents = fabricTexture(base: palette.seatFabric)
        fabric.diffuse.wrapS = .repeat
        fabric.diffuse.wrapT = .repeat

        let cabinet = box(width: 1.78, height: 0.42, length: 0.52, material: wood, corner: 0.055)
        cabinet.position.y = 0.21
        root.addChildNode(cabinet)
        let cushion = box(width: 1.68, height: 0.16, length: 0.50, material: fabric, corner: 0.11)
        cushion.position = SCNVector3(0, 0.49, 0.02)
        root.addChildNode(cushion)

        for x: Float in [-0.58, 0, 0.58] {
            let seam = box(width: 0.018, height: 0.29, length: 0.012, material: materialWith(color: palette.woodShadow, roughness: 0.80), corner: 0.005)
            seam.position = SCNVector3(x, 0.22, 0.268)
            root.addChildNode(seam)
            let handle = SCNTorus(ringRadius: 0.055, pipeRadius: 0.009)
            handle.ringSegmentCount = 18
            handle.pipeSegmentCount = 8
            handle.materials = [materialWith(color: palette.metal, roughness: 0.40)]
            let handleNode = SCNNode(geometry: handle)
            handleNode.position = SCNVector3(x, 0.24, 0.282)
            root.addChildNode(handleNode)
        }
        let cherryArrangement = makeCherryBranchArrangement()
        cherryArrangement.position = SCNVector3(0.63, 0.56, -0.02)
        cherryArrangement.scale = SCNVector3(0.72, 0.72, 0.72)
        root.addChildNode(cherryArrangement)
        return root
    }

    private func makeCherryBranchArrangement() -> SCNNode {
        let root = SCNNode()
        root.name = "room-cherry-branch"
        let ceramic = materialWith(color: UIColor(red: 0.88, green: 0.92, blue: 0.93, alpha: 1), roughness: 0.40)
        let vase = SCNCone(topRadius: 0.075, bottomRadius: 0.12, height: 0.30)
        vase.radialSegmentCount = 32
        vase.materials = [ceramic]
        let vaseNode = SCNNode(geometry: vase)
        vaseNode.position.y = 0.15
        root.addChildNode(vaseNode)

        let branchMaterial = materialWith(color: UIColor(red: 0.30, green: 0.19, blue: 0.16, alpha: 1), roughness: 0.84)
        let segments: [(SCNVector3, Float, Float)] = [
            (SCNVector3(0.00, 0.52, 0), 0.52, -0.20),
            (SCNVector3(-0.12, 0.69, 0), 0.34, 0.78),
            (SCNVector3(0.14, 0.76, 0), 0.40, -0.70)
        ]
        for (position, height, angle) in segments {
            let branch = SCNCylinder(radius: 0.012, height: CGFloat(height))
            branch.radialSegmentCount = 10
            branch.materials = [branchMaterial]
            let branchNode = SCNNode(geometry: branch)
            branchNode.position = position
            branchNode.eulerAngles.z = angle
            root.addChildNode(branchNode)
        }

        let blossomColors = [
            UIColor(red: 1.00, green: 0.82, blue: 0.86, alpha: 1),
            UIColor(red: 1.00, green: 0.90, blue: 0.92, alpha: 1),
            UIColor(red: 0.96, green: 0.72, blue: 0.79, alpha: 1)
        ]
        let blossomPositions: [SCNVector3] = [
            SCNVector3(-0.30, 0.84, 0), SCNVector3(-0.18, 0.96, 0.01),
            SCNVector3(-0.03, 1.00, 0), SCNVector3(0.15, 0.88, 0.01),
            SCNVector3(0.31, 0.98, 0), SCNVector3(0.38, 1.10, 0.01),
            SCNVector3(0.05, 0.76, 0.02), SCNVector3(-0.36, 0.72, 0)
        ]
        for (index, position) in blossomPositions.enumerated() {
            let blossom = SCNSphere(radius: 0.040)
            blossom.segmentCount = 12
            blossom.materials = [materialWith(color: blossomColors[index % blossomColors.count], roughness: 0.92)]
            let blossomNode = SCNNode(geometry: blossom)
            blossomNode.scale = SCNVector3(1.0, 0.48, 1.0)
            blossomNode.position = position
            root.addChildNode(blossomNode)
        }
        return root
    }

    private func makeWallReadingNook(palette: HomeScenePalette) -> SCNNode {
        let root = SCNNode()
        root.name = "room-wall-reading-nook"
        root.position = SCNVector3(-2.91, 1.76, 0.38)
        root.eulerAngles.y = .pi / 2
        let wood = materialWith(color: palette.lightWood, roughness: 0.78)
        let backing = box(width: 1.58, height: 1.54, length: 0.035, material: materialWith(color: palette.panel, roughness: 0.94), corner: 0.018)
        backing.position = SCNVector3(0, 0, 0.02)
        root.addChildNode(backing)
        let shelf = box(width: 1.68, height: 0.085, length: 0.34, material: wood, corner: 0.025)
        shelf.position = SCNVector3(0, -0.72, 0.19)
        root.addChildNode(shelf)
        let frame = box(width: 0.57, height: 0.88, length: 0.045, material: materialWith(color: palette.woodShadow, roughness: 0.74), corner: 0.018)
        frame.position = SCNVector3(-0.37, 0.14, 0.045)
        root.addChildNode(frame)
        let print = SCNPlane(width: 0.50, height: 0.81)
        let printMaterial = materialWith(color: palette.wallArt, roughness: 0.88)
        printMaterial.diffuse.contents = cherryPrintTexture()
        printMaterial.emission.contents = UIColor.white.withAlphaComponent(0.035)
        print.materials = [printMaterial]
        let printNode = SCNNode(geometry: print)
        printNode.position = SCNVector3(-0.37, 0.14, 0.072)
        root.addChildNode(printNode)
        for index in 0..<5 {
            let book = box(
                width: 0.105,
                height: 0.26 + CGFloat(index % 2) * 0.06,
                length: 0.20,
                material: materialWith(color: palette.decorativeBookColors[index], roughness: 0.82),
                corner: 0.012
            )
            book.position = SCNVector3(0.03 + Float(index) * 0.12, -0.55, 0.15)
            root.addChildNode(book)
        }
        let smallPlant = makePlant()
        smallPlant.scale = SCNVector3(0.32, 0.32, 0.32)
        smallPlant.position = SCNVector3(0.57, -0.58, 0.12)
        root.addChildNode(smallPlant)
        return root
    }

    private func makePendantLight(palette: HomeScenePalette) -> SCNNode {
        let root = SCNNode()
        root.name = "room-pendant-light"
        root.position = SCNVector3(-1.28, 3.22, -0.82)
        let metal = materialWith(color: palette.metal, roughness: 0.38)
        let cord = SCNCylinder(radius: 0.014, height: 0.62)
        cord.radialSegmentCount = 16
        cord.materials = [metal]
        let cordNode = SCNNode(geometry: cord)
        cordNode.position.y = -0.30
        root.addChildNode(cordNode)
        let paper = materialWith(color: palette.lampShade, roughness: 0.96, transparency: 0.90)
        paper.emission.contents = palette.bulb.withAlphaComponent(0.11)
        let shade = SCNSphere(radius: 0.28)
        shade.segmentCount = 48
        shade.materials = [paper]
        let shadeNode = SCNNode(geometry: shade)
        shadeNode.name = "room-washi-pendant"
        shadeNode.scale = SCNVector3(1, 1.12, 1)
        shadeNode.position.y = -0.78
        root.addChildNode(shadeNode)
        let ribMaterial = materialWith(color: palette.woodShadow.withAlphaComponent(0.60), roughness: 0.82, transparency: 0.72)
        for y: Float in [-0.19, -0.095, 0, 0.095, 0.19] {
            let radius = CGFloat(0.265 * sqrt(max(0.18, 1 - pow(y / 0.27, 2))))
            let rib = SCNTorus(ringRadius: radius, pipeRadius: 0.006)
            rib.ringSegmentCount = 36
            rib.pipeSegmentCount = 6
            rib.materials = [ribMaterial]
            let ribNode = SCNNode(geometry: rib)
            ribNode.position = SCNVector3(0, -0.78 + y, 0)
            root.addChildNode(ribNode)
        }
        let light = SCNLight()
        light.type = .omni
        light.color = palette.bulb
        light.intensity = palette.theme == .moonlight ? 150 : 115
        light.attenuationStartDistance = 0.4
        light.attenuationEndDistance = 3.8
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position.y = -0.84
        root.addChildNode(lightNode)
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
        let wood = materialWith(color: UIColor(red: 0.78, green: 0.67, blue: 0.53, alpha: 1), roughness: 0.86)
        let darkWood = materialWith(color: UIColor(red: 0.56, green: 0.45, blue: 0.34, alpha: 1), roughness: 0.90)
        let back = box(width: 1.52, height: 2.12, length: 0.055, material: darkWood, corner: 0.018)
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
        let bookColors = [
            UIColor(red: 0.82, green: 0.46, blue: 0.43, alpha: 1),
            UIColor(red: 0.34, green: 0.53, blue: 0.64, alpha: 1),
            UIColor(red: 0.76, green: 0.67, blue: 0.50, alpha: 1),
            UIColor(red: 0.49, green: 0.62, blue: 0.52, alpha: 1),
            UIColor(red: 0.72, green: 0.58, blue: 0.72, alpha: 1)
        ]
        for shelfIndex in 0..<4 {
            let baseY = Float(0.13 + Double(shelfIndex) * 0.54)
            for index in 0..<8 {
                let height = CGFloat(0.31 + Double((index + shelfIndex) % 3) * 0.035)
                let book = box(width: 0.115, height: height, length: 0.28, material: materialWith(color: bookColors[(index + shelfIndex) % bookColors.count], roughness: 0.88), corner: 0.008)
                book.position = SCNVector3(-0.57 + Float(index) * 0.15, baseY + Float(height / 2), 0.035)
                root.addChildNode(book)
            }
        }
        let crown = box(width: 1.68, height: 0.09, length: 0.48, material: wood, corner: 0.025)
        crown.position = SCNVector3(0, 2.22, 0)
        root.addChildNode(crown)
        return root
    }

    private func makeSofa() -> SCNNode {
        let root = SCNNode()
        let fabricColor = UIColor(red: 0.76, green: 0.81, blue: 0.78, alpha: 1)
        let highlightColor = UIColor(red: 0.90, green: 0.87, blue: 0.79, alpha: 1)
        let fabric = materialWith(color: fabricColor, roughness: 0.98)
        fabric.diffuse.contents = fabricTexture(base: fabricColor)
        let highlight = materialWith(color: highlightColor, roughness: 0.98)
        highlight.diffuse.contents = fabricTexture(base: highlightColor)
        let wood = materialWith(color: UIColor(red: 0.43, green: 0.32, blue: 0.25, alpha: 1), roughness: 0.88)
        let seat = box(width: 1.78, height: 0.30, length: 0.76, material: fabric, corner: 0.13)
        seat.position = SCNVector3(0, 0.38, 0)
        root.addChildNode(seat)
        let back = box(width: 1.78, height: 0.72, length: 0.23, material: fabric, corner: 0.14)
        back.position = SCNVector3(0, 0.76, -0.31)
        back.eulerAngles.x = -0.09
        root.addChildNode(back)
        for x: Float in [-0.90, 0.90] {
            let arm = box(width: 0.18, height: 0.48, length: 0.78, material: fabric, corner: 0.09)
            arm.position = SCNVector3(x, 0.43, 0)
            root.addChildNode(arm)
        }
        for x: Float in [-0.39, 0.39] {
            let cushion = box(width: 0.72, height: 0.14, length: 0.62, material: highlight, corner: 0.09)
            cushion.position = SCNVector3(x, 0.58, 0.02)
            root.addChildNode(cushion)
        }
        for x: Float in [-0.68, 0.68] {
            for z: Float in [-0.27, 0.27] {
                let leg = box(width: 0.07, height: 0.20, length: 0.07, material: wood, corner: 0.016)
                leg.position = SCNVector3(x, 0.10, z)
                root.addChildNode(leg)
            }
        }
        let throwPillow = box(width: 0.42, height: 0.40, length: 0.16, material: materialWith(color: UIColor(red: 0.80, green: 0.56, blue: 0.54, alpha: 1), roughness: 0.98), corner: 0.12)
        throwPillow.position = SCNVector3(-0.56, 0.80, -0.08)
        throwPillow.eulerAngles.z = -0.12
        root.addChildNode(throwPillow)
        return root
    }

    private func makeLowTable() -> SCNNode {
        let root = SCNNode()
        let wood = materialWith(color: UIColor(red: 0.72, green: 0.57, blue: 0.41, alpha: 1), roughness: 0.82)
        let ceramic = materialWith(color: UIColor(red: 0.79, green: 0.87, blue: 0.85, alpha: 1), roughness: 0.44)
        let top = box(width: 1.26, height: 0.105, length: 0.78, material: wood, corner: 0.10)
        top.position = SCNVector3(0, 0.40, 0)
        root.addChildNode(top)
        for x: Float in [-0.48, 0.48] {
            for z: Float in [-0.27, 0.27] {
                let leg = box(width: 0.075, height: 0.35, length: 0.075, material: wood, corner: 0.020)
                leg.position = SCNVector3(x, 0.18, z)
                root.addChildNode(leg)
            }
        }
        let lowerShelf = box(width: 0.92, height: 0.045, length: 0.50, material: wood, corner: 0.035)
        lowerShelf.position.y = 0.17
        root.addChildNode(lowerShelf)
        let cup = SCNCylinder(radius: 0.075, height: 0.10)
        cup.radialSegmentCount = 28
        cup.materials = [ceramic]
        let cupNode = SCNNode(geometry: cup)
        cupNode.position = SCNVector3(0.32, 0.51, -0.08)
        root.addChildNode(cupNode)
        let book = box(width: 0.34, height: 0.025, length: 0.28, material: materialWith(color: UIColor(red: 0.88, green: 0.70, blue: 0.70, alpha: 1), roughness: 0.88), corner: 0.012)
        book.position = SCNVector3(-0.22, 0.47, 0.03)
        book.eulerAngles.y = 0.12
        root.addChildNode(book)
        return root
    }

    private func makeRug() -> SCNNode {
        let material = materialWith(color: UIColor(red: 0.40, green: 0.50, blue: 0.56, alpha: 1), roughness: 1)
        material.diffuse.contents = rugTexture()
        let node = box(width: 2.18, height: 0.025, length: 1.48, material: material, corner: 0.18)
        node.position.y = 0.014
        return node
    }

    private func makeFloorLamp() -> SCNNode {
        let root = SCNNode()
        let wood = materialWith(color: UIColor(red: 0.34, green: 0.25, blue: 0.20, alpha: 1), roughness: 0.84)
        let paper = materialWith(color: UIColor(red: 1, green: 0.91, blue: 0.73, alpha: 1), roughness: 0.98, transparency: 0.88)
        paper.emission.contents = UIColor(red: 1, green: 0.72, blue: 0.42, alpha: 0.10)
        for x: Float in [-0.22, 0.22] {
            let post = box(width: 0.035, height: 1.30, length: 0.035, material: wood, corner: 0.008)
            post.position = SCNVector3(x, 0.67, 0)
            root.addChildNode(post)
        }
        for y: Float in [0.04, 0.44, 0.84, 1.32] {
            let rail = box(width: 0.50, height: 0.035, length: 0.28, material: wood, corner: 0.008)
            rail.position = SCNVector3(0, y, 0)
            root.addChildNode(rail)
        }
        let shadeNode = box(width: 0.42, height: 1.20, length: 0.22, material: paper, corner: 0.055)
        shadeNode.position = SCNVector3(0, 0.68, 0)
        root.addChildNode(shadeNode)
        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(red: 1, green: 0.72, blue: 0.44, alpha: 1)
        light.intensity = 145
        light.attenuationStartDistance = 0.4
        light.attenuationEndDistance = 3.2
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position.y = 0.78
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

    private func panoramaImage(theme: HomeRoomTheme) -> UIImage {
        let cacheKey = "panorama-\(theme.rawValue)"
        if let cached = generatedTextureCache[cacheKey] { return cached }
        let source = panoramaResourceURL().flatMap { UIImage(contentsOfFile: $0.path) }
            ?? backgroundImage(theme: theme, size: CGSize(width: 2_048, height: 1_024))
        let base = croppedImage(source, toAspectRatio: 3.34 / 2.06)
        guard theme != .sunset else {
            generatedTextureCache[cacheKey] = base
            return base
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: base.size, format: format).image { context in
            base.draw(in: CGRect(origin: .zero, size: base.size))
            let overlay = theme == .rain
                ? UIColor(red: 0.20, green: 0.35, blue: 0.48, alpha: 0.34)
                : UIColor(red: 0.035, green: 0.055, blue: 0.18, alpha: 0.68)
            overlay.setFill()
            context.fill(CGRect(origin: .zero, size: base.size))
            if theme == .rain {
                UIColor.white.withAlphaComponent(0.16).setStroke()
                context.cgContext.setLineWidth(1.4)
                for index in 0..<92 {
                    let x = CGFloat((index * 83) % 2_048) / 2_048 * base.size.width
                    let y = CGFloat((index * 131) % 1_024) / 1_024 * base.size.height
                    context.cgContext.move(to: CGPoint(x: x, y: y))
                    context.cgContext.addLine(to: CGPoint(x: x - 8, y: y + 28))
                }
                context.cgContext.strokePath()
            } else {
                UIColor(red: 0.80, green: 0.86, blue: 1, alpha: 0.72).setFill()
                for index in 0..<48 {
                    let x = CGFloat((index * 149 + 41) % 2_048) / 2_048 * base.size.width
                    let y = CGFloat((index * 71 + 23) % 520) / 1_024 * base.size.height
                    let radius = CGFloat(1 + index % 3)
                    context.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: radius, height: radius))
                }
            }
        }
        generatedTextureCache[cacheKey] = rendered
        return rendered
    }

    private func panoramaContents(theme: HomeRoomTheme) -> Any {
        if theme == .sunset, let resourceURL = panoramaResourceURL() {
            return resourceURL as NSURL
        }
        return panoramaImage(theme: theme)
    }

    private func panoramaResourceURL() -> URL? {
        Bundle.main.url(forResource: "WindowPanoramaTokyoSpring", withExtension: "png")
    }

    private func croppedImage(_ image: UIImage, toAspectRatio targetAspectRatio: CGFloat) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let sourceAspectRatio = width / max(height, 1)
        let cropRect: CGRect
        if sourceAspectRatio > targetAspectRatio {
            let cropWidth = height * targetAspectRatio
            cropRect = CGRect(x: (width - cropWidth) / 2, y: 0, width: cropWidth, height: height)
        } else {
            let cropHeight = width / targetAspectRatio
            cropRect = CGRect(x: 0, y: (height - cropHeight) / 2, width: width, height: cropHeight)
        }
        guard let cropped = cgImage.cropping(to: cropRect.integral) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    private func woodTexture(palette: HomeScenePalette) -> UIImage {
        let cacheKey = "wood-\(palette.theme.rawValue)"
        if let cached = generatedTextureCache[cacheKey] { return cached }
        let size = CGSize(width: 512, height: 512)
        let rendered = textureRenderer(size: size).image { context in
            palette.floor.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let boardHeight: CGFloat = 64
            for row in 0..<8 {
                let y = CGFloat(row) * boardHeight
                let tint = row.isMultiple(of: 2) ? UIColor.white.withAlphaComponent(0.035) : UIColor.black.withAlphaComponent(0.028)
                tint.setFill()
                context.fill(CGRect(x: 0, y: y, width: size.width, height: boardHeight))
                palette.floorBorder.withAlphaComponent(0.34).setStroke()
                context.cgContext.setLineWidth(1.25)
                context.cgContext.move(to: CGPoint(x: 0, y: y))
                context.cgContext.addLine(to: CGPoint(x: size.width, y: y))
                context.cgContext.strokePath()
                let offset: CGFloat = row.isMultiple(of: 2) ? 82 : 214
                for joint in stride(from: offset, through: size.width, by: 256) {
                    context.cgContext.move(to: CGPoint(x: joint, y: y))
                    context.cgContext.addLine(to: CGPoint(x: joint, y: y + boardHeight))
                }
                context.cgContext.strokePath()
            }
            for index in 0..<118 {
                let y = CGFloat((index * 37 + 19) % 512)
                let x = CGFloat((index * 97 + 31) % 512)
                let length = CGFloat(34 + (index * 29) % 120)
                UIColor.black.withAlphaComponent(index.isMultiple(of: 3) ? 0.030 : 0.018).setStroke()
                context.cgContext.setLineWidth(0.75)
                context.cgContext.move(to: CGPoint(x: x, y: y))
                context.cgContext.addCurve(
                    to: CGPoint(x: min(size.width, x + length), y: y + 1.5),
                    control1: CGPoint(x: x + length * 0.3, y: y - 2.2),
                    control2: CGPoint(x: x + length * 0.7, y: y + 3.0)
                )
                context.cgContext.strokePath()
            }
        }
        generatedTextureCache[cacheKey] = rendered
        return rendered
    }

    private func wallpaperTexture(palette: HomeScenePalette, side: Bool = false) -> UIImage {
        let cacheKey = "wallpaper-\(palette.theme.rawValue)-\(side)"
        if let cached = generatedTextureCache[cacheKey] { return cached }
        let size = CGSize(width: 384, height: 384)
        let base = side ? palette.sideWall : palette.wall
        let rendered = textureRenderer(size: size).image { context in
            base.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for index in 0..<620 {
                let x = CGFloat((index * 73 + 19) % 384)
                let y = CGFloat((index * 131 + 7) % 384)
                let alpha = index.isMultiple(of: 3) ? 0.040 : 0.020
                (index.isMultiple(of: 2) ? UIColor.white : palette.wallMotif).withAlphaComponent(alpha).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: 1.1, height: 1.1))
            }
            UIColor.black.withAlphaComponent(0.018).setStroke()
            context.cgContext.setLineWidth(0.5)
            for x in stride(from: CGFloat(0), through: size.width, by: 12) {
                context.cgContext.move(to: CGPoint(x: x, y: 0))
                context.cgContext.addLine(to: CGPoint(x: x + 2, y: size.height))
            }
            context.cgContext.strokePath()
        }
        generatedTextureCache[cacheKey] = rendered
        return rendered
    }

    private func fabricTexture(base: UIColor) -> UIImage {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        base.getRed(&red, green: &green, blue: &blue, alpha: nil)
        let cacheKey = String(format: "fabric-%.2f-%.2f-%.2f", red, green, blue)
        if let cached = generatedTextureCache[cacheKey] { return cached }
        let size = CGSize(width: 128, height: 128)
        let rendered = textureRenderer(size: size).image { context in
            base.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.setLineWidth(0.55)
            UIColor.white.withAlphaComponent(0.075).setStroke()
            for value in stride(from: CGFloat(0), through: size.width, by: 4) {
                context.cgContext.move(to: CGPoint(x: value, y: 0))
                context.cgContext.addLine(to: CGPoint(x: value, y: size.height))
            }
            context.cgContext.strokePath()
            UIColor.black.withAlphaComponent(0.045).setStroke()
            for value in stride(from: CGFloat(2), through: size.height, by: 4) {
                context.cgContext.move(to: CGPoint(x: 0, y: value))
                context.cgContext.addLine(to: CGPoint(x: size.width, y: value))
            }
            context.cgContext.strokePath()
        }
        generatedTextureCache[cacheKey] = rendered
        return rendered
    }

    private func rugTexture() -> UIImage {
        let cacheKey = "rug-japanese-wave"
        if let cached = generatedTextureCache[cacheKey] { return cached }
        let size = CGSize(width: 640, height: 420)
        let rendered = textureRenderer(size: size).image { context in
            UIColor(red: 0.35, green: 0.47, blue: 0.53, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.87, green: 0.82, blue: 0.70, alpha: 0.42).setStroke()
            context.cgContext.setLineWidth(2.2)
            let radius: CGFloat = 52
            for row in 0..<6 {
                for column in 0..<8 {
                    let x = CGFloat(column) * radius * 1.55 + (row.isMultiple(of: 2) ? 0 : radius * 0.78)
                    let y = CGFloat(row) * radius * 1.28
                    context.cgContext.addArc(center: CGPoint(x: x, y: y + radius), radius: radius, startAngle: .pi, endAngle: 0, clockwise: false)
                    context.cgContext.addArc(center: CGPoint(x: x, y: y + radius), radius: radius * 0.66, startAngle: .pi, endAngle: 0, clockwise: false)
                    context.cgContext.addArc(center: CGPoint(x: x, y: y + radius), radius: radius * 0.33, startAngle: .pi, endAngle: 0, clockwise: false)
                }
            }
            context.cgContext.strokePath()
            UIColor.white.withAlphaComponent(0.13).setStroke()
            context.cgContext.setLineWidth(0.7)
            for y in stride(from: CGFloat(0), through: size.height, by: 5) {
                context.cgContext.move(to: CGPoint(x: 0, y: y))
                context.cgContext.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.cgContext.strokePath()
        }
        generatedTextureCache[cacheKey] = rendered
        return rendered
    }

    private func shojiPaperTexture() -> UIImage {
        let cacheKey = "shoji-washi"
        if let cached = generatedTextureCache[cacheKey] { return cached }
        let size = CGSize(width: 256, height: 256)
        let rendered = textureRenderer(size: size).image { context in
            UIColor(red: 0.98, green: 0.96, blue: 0.88, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for index in 0..<360 {
                let x = CGFloat((index * 61 + 5) % 256)
                let y = CGFloat((index * 109 + 17) % 256)
                UIColor(red: 0.55, green: 0.49, blue: 0.39, alpha: index.isMultiple(of: 2) ? 0.045 : 0.025).setStroke()
                context.cgContext.setLineWidth(0.6)
                context.cgContext.move(to: CGPoint(x: x, y: y))
                context.cgContext.addLine(to: CGPoint(x: min(CGFloat(256), x + CGFloat(4 + index % 13)), y: y + CGFloat(index % 3) - 1))
                context.cgContext.strokePath()
            }
        }
        generatedTextureCache[cacheKey] = rendered
        return rendered
    }

    private func tatamiTexture(base: UIColor) -> UIImage {
        let cacheKey = "tatami-weave"
        if let cached = generatedTextureCache[cacheKey] { return cached }
        let size = CGSize(width: 256, height: 256)
        let rendered = textureRenderer(size: size).image { context in
            base.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.withAlphaComponent(0.105).setStroke()
            context.cgContext.setLineWidth(0.65)
            for y in stride(from: CGFloat(0), through: size.height, by: 3) {
                context.cgContext.move(to: CGPoint(x: 0, y: y))
                context.cgContext.addLine(to: CGPoint(x: size.width, y: y + 1))
            }
            context.cgContext.strokePath()
            UIColor.black.withAlphaComponent(0.055).setStroke()
            for x in stride(from: CGFloat(1), through: size.width, by: 6) {
                context.cgContext.move(to: CGPoint(x: x, y: 0))
                context.cgContext.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.cgContext.strokePath()
        }
        generatedTextureCache[cacheKey] = rendered
        return rendered
    }

    private func cherryPrintTexture() -> UIImage {
        let cacheKey = "tokyo-cherry-print"
        if let cached = generatedTextureCache[cacheKey] { return cached }
        let size = CGSize(width: 500, height: 810)
        let rendered = textureRenderer(size: size).image { context in
            UIColor(red: 0.96, green: 0.94, blue: 0.88, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.76, green: 0.32, blue: 0.27, alpha: 0.80).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 300, y: 120, width: 105, height: 105))
            UIColor(red: 0.23, green: 0.19, blue: 0.17, alpha: 0.88).setStroke()
            context.cgContext.setLineWidth(9)
            context.cgContext.move(to: CGPoint(x: 40, y: 700))
            context.cgContext.addCurve(to: CGPoint(x: 360, y: 245), control1: CGPoint(x: 190, y: 620), control2: CGPoint(x: 185, y: 335))
            context.cgContext.move(to: CGPoint(x: 185, y: 475))
            context.cgContext.addCurve(to: CGPoint(x: 430, y: 385), control1: CGPoint(x: 275, y: 455), control2: CGPoint(x: 330, y: 360))
            context.cgContext.strokePath()
            let colors = [UIColor(red: 0.93, green: 0.56, blue: 0.62, alpha: 0.78), UIColor(red: 1, green: 0.78, blue: 0.80, alpha: 0.88)]
            for index in 0..<24 {
                let x = CGFloat((index * 79 + 73) % 390) + 45
                let y = CGFloat((index * 47 + 211) % 410) + 150
                colors[index % colors.count].setFill()
                context.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: 20, height: 12))
            }
        }
        generatedTextureCache[cacheKey] = rendered
        return rendered
    }

    private func textureRenderer(size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format)
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
        case .sunset: UIColor(red: 0.78, green: 0.67, blue: 0.52, alpha: 1)
        case .rain: UIColor(red: 0.64, green: 0.61, blue: 0.55, alpha: 1)
        case .moonlight: UIColor(red: 0.34, green: 0.31, blue: 0.38, alpha: 1)
        }
    }

    var wall: UIColor {
        switch theme {
        case .sunset: UIColor(red: 0.95, green: 0.94, blue: 0.90, alpha: 1)
        case .rain: UIColor(red: 0.80, green: 0.90, blue: 0.89, alpha: 1)
        case .moonlight: UIColor(red: 0.25, green: 0.25, blue: 0.40, alpha: 1)
        }
    }

    var sideWall: UIColor {
        switch theme {
        case .sunset: UIColor(red: 0.91, green: 0.91, blue: 0.87, alpha: 1)
        case .rain: UIColor(red: 0.70, green: 0.81, blue: 0.83, alpha: 1)
        case .moonlight: UIColor(red: 0.18, green: 0.19, blue: 0.33, alpha: 1)
        }
    }

    var panel: UIColor {
        switch theme {
        case .sunset: UIColor(red: 0.90, green: 0.88, blue: 0.81, alpha: 1)
        case .rain: UIColor(red: 0.67, green: 0.76, blue: 0.76, alpha: 1)
        case .moonlight: UIColor(red: 0.20, green: 0.20, blue: 0.31, alpha: 1)
        }
    }

    var trim: UIColor {
        switch theme {
        case .sunset: UIColor(red: 0.98, green: 0.90, blue: 0.80, alpha: 1)
        case .rain: UIColor(red: 0.84, green: 0.90, blue: 0.87, alpha: 1)
        case .moonlight: UIColor(red: 0.39, green: 0.37, blue: 0.52, alpha: 1)
        }
    }

    var floorBorder: UIColor {
        switch theme {
        case .sunset: UIColor(red: 0.48, green: 0.38, blue: 0.28, alpha: 1)
        case .rain: UIColor(red: 0.34, green: 0.29, blue: 0.27, alpha: 1)
        case .moonlight: UIColor(red: 0.13, green: 0.11, blue: 0.19, alpha: 1)
        }
    }

    var lightWood: UIColor {
        switch theme {
        case .sunset: UIColor(red: 0.79, green: 0.68, blue: 0.54, alpha: 1)
        case .rain: UIColor(red: 0.63, green: 0.53, blue: 0.44, alpha: 1)
        case .moonlight: UIColor(red: 0.38, green: 0.31, blue: 0.38, alpha: 1)
        }
    }

    var woodShadow: UIColor {
        switch theme {
        case .sunset: UIColor(red: 0.39, green: 0.24, blue: 0.17, alpha: 1)
        case .rain: UIColor(red: 0.31, green: 0.28, blue: 0.26, alpha: 1)
        case .moonlight: UIColor(red: 0.16, green: 0.14, blue: 0.22, alpha: 1)
        }
    }

    var seatFabric: UIColor {
        switch theme {
        case .sunset: UIColor(red: 0.94, green: 0.78, blue: 0.70, alpha: 1)
        case .rain: UIColor(red: 0.69, green: 0.84, blue: 0.82, alpha: 1)
        case .moonlight: UIColor(red: 0.47, green: 0.45, blue: 0.68, alpha: 1)
        }
    }

    var windowFrame: UIColor { theme == .moonlight ? UIColor(red: 0.18, green: 0.20, blue: 0.28, alpha: 1) : UIColor(red: 0.20, green: 0.22, blue: 0.22, alpha: 1) }
    var metal: UIColor { theme == .moonlight ? UIColor(red: 0.48, green: 0.49, blue: 0.60, alpha: 1) : UIColor(red: 0.27, green: 0.28, blue: 0.27, alpha: 1) }
    var tatami: UIColor { theme == .moonlight ? UIColor(red: 0.48, green: 0.49, blue: 0.39, alpha: 1) : UIColor(red: 0.70, green: 0.70, blue: 0.53, alpha: 1) }
    var tatamiBorder: UIColor { theme == .moonlight ? UIColor(red: 0.15, green: 0.17, blue: 0.21, alpha: 1) : UIColor(red: 0.20, green: 0.25, blue: 0.24, alpha: 1) }
    var curtainTie: UIColor { theme == .moonlight ? UIColor(red: 0.72, green: 0.67, blue: 0.94, alpha: 1) : UIColor(red: 0.91, green: 0.70, blue: 0.35, alpha: 1) }
    var lampShade: UIColor { theme == .moonlight ? UIColor(red: 0.42, green: 0.42, blue: 0.62, alpha: 1) : UIColor(red: 0.96, green: 0.82, blue: 0.64, alpha: 1) }
    var bulb: UIColor { theme == .moonlight ? UIColor(red: 0.73, green: 0.79, blue: 1, alpha: 1) : UIColor(red: 1, green: 0.75, blue: 0.43, alpha: 1) }
    var glass: UIColor { theme == .moonlight ? UIColor(red: 0.40, green: 0.55, blue: 0.94, alpha: 1) : UIColor(red: 0.78, green: 0.92, blue: 1, alpha: 1) }
    var wallMotif: UIColor { theme == .moonlight ? UIColor(red: 0.68, green: 0.65, blue: 0.94, alpha: 1) : UIColor(red: 0.58, green: 0.42, blue: 0.38, alpha: 1) }
    var wallArt: UIColor { theme == .rain ? UIColor(red: 0.55, green: 0.78, blue: 0.74, alpha: 1) : UIColor(red: 0.84, green: 0.59, blue: 0.69, alpha: 1) }
    var fill: UIColor { theme == .moonlight ? UIColor(red: 0.45, green: 0.55, blue: 0.90, alpha: 1) : UIColor(red: 0.72, green: 0.84, blue: 1, alpha: 1) }

    var decorativeBookColors: [UIColor] {
        [
            UIColor(red: 0.88, green: 0.48, blue: 0.48, alpha: 1),
            UIColor(red: 0.42, green: 0.67, blue: 0.82, alpha: 1),
            UIColor(red: 0.78, green: 0.63, blue: 0.89, alpha: 1),
            UIColor(red: 0.91, green: 0.72, blue: 0.42, alpha: 1),
            UIColor(red: 0.48, green: 0.72, blue: 0.61, alpha: 1)
        ]
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
