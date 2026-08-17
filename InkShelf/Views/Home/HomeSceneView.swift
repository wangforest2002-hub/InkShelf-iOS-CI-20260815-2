import SceneKit
import SwiftUI

struct HomeSceneView: UIViewRepresentable {
    let state: HomeWorldState
    let books: [HomeRenderableBook]
    let artworks: [HomeRenderableArtwork]
    let selectedPlacementID: UUID?
    let isEditing: Bool
    let showsKokoZone: Bool
    let kokoDecision: KokoDecision
    let kokoDecisionRevision: Int
    let reduceMotion: Bool
    let onSelectPlacement: (UUID?) -> Void
    let onOpenBook: (UUID) -> Void
    let onTransformChanged: (UUID, HomeTransform) -> Void
    let onKokoTapped: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        context.coordinator.configure(view)
        context.coordinator.sync(with: self)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(with: self)
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        uiView.isPlaying = false
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HomeSceneView
        private let factory = HomeSceneFactory()
        private let scene = SCNScene()
        private let contentRoot = SCNNode()
        private let cameraTarget = SCNNode()
        private let cameraNode = SCNNode()
        private let kokoController = KokoSceneController()
        private weak var sceneView: SCNView?
        private var roomNode: SCNNode?
        private var kokoNode: SCNNode?
        private var zoneNode: SCNNode?
        private var placementNodes: [UUID: SCNNode] = [:]
        private var placements: [UUID: HomePlacement] = [:]
        private var currentTheme: HomeRoomTheme?
        private var currentSelection: UUID?
        private var lastKokoDecisionRevision = -1
        private var cameraYaw: Float = 0.68
        private var cameraPitch: Float = 0.56
        private var cameraDistance: Float = 7.2
        private var hasAppliedResponsiveFraming = false
        private var dragStartTransform: HomeTransform?
        private var rotationStart: Float?

        init(parent: HomeSceneView) {
            self.parent = parent
            super.init()
        }

        func configure(_ view: SCNView) {
            sceneView = view
            scene.rootNode.addChildNode(contentRoot)
            cameraTarget.position = SCNVector3(0, 0.88, -0.08)
            scene.rootNode.addChildNode(cameraTarget)
            let camera = SCNCamera()
            camera.fieldOfView = 52
            camera.zNear = 0.05
            camera.zFar = 80
            camera.wantsHDR = true
            camera.wantsExposureAdaptation = false
            camera.exposureOffset = -0.18
            cameraNode.camera = camera
            let constraint = SCNLookAtConstraint(target: cameraTarget)
            constraint.isGimbalLockEnabled = true
            cameraNode.constraints = [constraint]
            scene.rootNode.addChildNode(cameraNode)

            view.scene = scene
            view.pointOfView = cameraNode
            view.backgroundColor = .clear
            view.isPlaying = true
            view.rendersContinuously = true
            view.preferredFramesPerSecond = 60
            view.antialiasingMode = .multisampling4X
            view.autoenablesDefaultLighting = false
            view.allowsCameraControl = false
            view.scene?.physicsWorld.speed = 1
            updateCamera(animated: false)

            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
            let rotation = UIRotationGestureRecognizer(target: self, action: #selector(rotated(_:)))
            tap.delegate = self
            pan.delegate = self
            pinch.delegate = self
            rotation.delegate = self
            view.addGestureRecognizer(tap)
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(pinch)
            view.addGestureRecognizer(rotation)
            view.accessibilityIdentifier = "home-3d-scene"
            view.accessibilityLabel = "可自由布置的三维小家"
            view.accessibilityHint = "拖动调整视角，双指缩放；布置模式下可移动物品"
            Task { @MainActor [weak self] in
                self?.applyResponsiveFramingIfNeeded()
            }
        }

        func sync(with value: HomeSceneView) {
            guard let sceneView else { return }
            applyResponsiveFramingIfNeeded()
            if currentTheme != value.state.theme {
                roomNode?.removeFromParentNode()
                let room = factory.makeRoom(theme: value.state.theme)
                contentRoot.addChildNode(room)
                roomNode = room
                scene.background.contents = factory.backgroundImage(theme: value.state.theme)
                currentTheme = value.state.theme
            }

            placements = Dictionary(uniqueKeysWithValues: value.state.placements.map { ($0.id, $0) })
            let bookLookup = Dictionary(uniqueKeysWithValues: value.books.map { ($0.id, $0) })
            let artworkLookup = Dictionary(uniqueKeysWithValues: value.artworks.map { ($0.id, $0) })
            let validIDs = Set(value.state.placements.map(\.id))
            let staleIDs = placementNodes.keys.filter { !validIDs.contains($0) }
            for id in staleIDs {
                placementNodes.removeValue(forKey: id)?.removeFromParentNode()
            }
            for placement in value.state.placements {
                if let node = placementNodes[placement.id] {
                    factory.apply(placement.transform, to: node)
                } else {
                    let node = factory.makePlacementNode(
                        placement: placement,
                        book: placement.bookID.flatMap { bookLookup[$0] },
                        artwork: placement.artworkID.flatMap { artworkLookup[$0] }
                    )
                    placementNodes[placement.id] = node
                    contentRoot.addChildNode(node)
                    if !value.reduceMotion {
                        let finalScale = node.scale
                        node.scale = SCNVector3(finalScale.x * 0.82, finalScale.y * 0.82, finalScale.z * 0.82)
                        node.opacity = 0
                        SCNTransaction.begin()
                        SCNTransaction.animationDuration = 0.38
                        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
                        node.scale = finalScale
                        node.opacity = 1
                        SCNTransaction.commit()
                    }
                }
            }

            if kokoNode == nil {
                let koko = factory.makeKokoNode()
                contentRoot.addChildNode(koko)
                kokoNode = koko
                kokoController.install(
                    root: koko,
                    zone: value.state.koko.activityZone,
                    roamingEnabled: value.state.koko.roamingEnabled,
                    reduceMotion: value.reduceMotion,
                    placements: value.state.placements
                )
            } else {
                kokoController.update(
                    zone: value.state.koko.activityZone,
                    roamingEnabled: value.state.koko.roamingEnabled,
                    reduceMotion: value.reduceMotion,
                    placements: value.state.placements
                )
            }

            if value.showsKokoZone {
                zoneNode?.removeFromParentNode()
                let zone = factory.makeActivityZone(value.state.koko.activityZone)
                contentRoot.addChildNode(zone)
                zoneNode = zone
            } else {
                zoneNode?.removeFromParentNode()
                zoneNode = nil
            }

            if currentSelection != value.selectedPlacementID {
                if let old = currentSelection, let node = placementNodes[old] {
                    factory.setSelected(false, node: node)
                }
                currentSelection = value.selectedPlacementID
                if let currentSelection, let node = placementNodes[currentSelection] {
                    factory.setSelected(true, node: node)
                }
            }

            if lastKokoDecisionRevision != value.kokoDecisionRevision {
                lastKokoDecisionRevision = value.kokoDecisionRevision
                let target = value.kokoDecision.targetBookID.flatMap { targetBookID in
                    value.state.placements.first(where: { $0.bookID == targetBookID }).flatMap { placementNodes[$0.id] }
                }
                kokoController.perform(value.kokoDecision, target: target)
            }
            sceneView.preferredFramesPerSecond = value.reduceMotion ? 30 : 60
        }

        func stop() {
            kokoNode?.removeAllActions()
            contentRoot.removeAllActions()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view = sceneView else { return }
            let point = recognizer.location(in: view)
            let results = view.hitTest(point, options: [
                .firstFoundOnly: true,
                .boundingBoxOnly: false,
                .ignoreHiddenNodes: true
            ])
            guard let hit = results.first else {
                if parent.isEditing { parent.onSelectPlacement(nil) }
                return
            }
            var node: SCNNode? = hit.node
            while let current = node {
                if current.name == "koko" {
                    parent.onKokoTapped()
                    return
                }
                if let name = current.name,
                   name.hasPrefix("placement:"),
                   let id = UUID(uuidString: String(name.dropFirst("placement:".count))) {
                    if parent.isEditing {
                        parent.onSelectPlacement(id)
                    } else if let bookID = placements[id]?.bookID {
                        parent.onOpenBook(bookID)
                    }
                    return
                }
                node = current.parent
            }
            if parent.isEditing { parent.onSelectPlacement(nil) }
        }

        @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
            guard let view = sceneView else { return }
            let translation = recognizer.translation(in: view)
            if parent.isEditing,
               let selected = parent.selectedPlacementID,
               var placement = placements[selected],
               !placement.isLocked {
                switch recognizer.state {
                case .began:
                    dragStartTransform = placement.transform
                case .changed:
                    guard let start = dragStartTransform else { return }
                    let speed = max(0.0025, cameraDistance * 0.00078)
                    if placement.artworkID.flatMap({ id in parent.artworks.first(where: { $0.id == id }) })?.kind == .poster {
                        placement.transform.x = start.x + Float(translation.x) * speed
                        placement.transform.y = start.y - Float(translation.y) * speed
                        placement.transform.z = -2.39
                    } else {
                        let rightX = cos(cameraYaw)
                        let rightZ = -sin(cameraYaw)
                        let forwardX = sin(cameraYaw)
                        let forwardZ = cos(cameraYaw)
                        placement.transform.x = start.x + Float(translation.x) * speed * rightX + Float(translation.y) * speed * forwardX
                        placement.transform.z = start.z + Float(translation.x) * speed * rightZ + Float(translation.y) * speed * forwardZ
                    }
                    placement.transform.clamp()
                    placements[selected] = placement
                    placementNodes[selected].map { factory.apply(placement.transform, to: $0) }
                case .ended, .cancelled:
                    if let changed = placements[selected] {
                        parent.onTransformChanged(selected, changed.transform)
                    }
                    dragStartTransform = nil
                default:
                    break
                }
            } else {
                switch recognizer.state {
                case .changed:
                    cameraYaw -= Float(translation.x) * 0.0052
                    cameraPitch = min(max(cameraPitch + Float(translation.y) * 0.0035, 0.25), 0.94)
                    recognizer.setTranslation(.zero, in: view)
                    updateCamera(animated: false)
                default:
                    break
                }
            }
        }

        @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
            guard recognizer.state == .changed else { return }
            cameraDistance = min(max(cameraDistance / Float(recognizer.scale), 4.1), 13.5)
            recognizer.scale = 1
            updateCamera(animated: false)
        }

        @objc private func rotated(_ recognizer: UIRotationGestureRecognizer) {
            guard parent.isEditing,
                  let selected = parent.selectedPlacementID,
                  var placement = placements[selected],
                  !placement.isLocked
            else { return }
            switch recognizer.state {
            case .began:
                rotationStart = placement.transform.yaw
            case .changed:
                placement.transform.yaw = (rotationStart ?? placement.transform.yaw) - Float(recognizer.rotation)
                placement.transform.clamp()
                placements[selected] = placement
                placementNodes[selected].map { factory.apply(placement.transform, to: $0) }
            case .ended, .cancelled:
                if let changed = placements[selected] {
                    parent.onTransformChanged(selected, changed.transform)
                }
                rotationStart = nil
            default:
                break
            }
        }

        private func updateCamera(animated: Bool) {
            let horizontal = cameraDistance * cos(cameraPitch)
            let position = SCNVector3(
                sin(cameraYaw) * horizontal,
                max(1.7, cameraDistance * sin(cameraPitch)),
                cos(cameraYaw) * horizontal
            )
            if animated {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.45
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                cameraNode.position = position
                SCNTransaction.commit()
            } else {
                cameraNode.position = position
            }
        }

        private func applyResponsiveFramingIfNeeded() {
            guard !hasAppliedResponsiveFraming,
                  let sceneView,
                  sceneView.bounds.width > 0,
                  sceneView.bounds.height > 0
            else { return }
            let isPortrait = sceneView.bounds.height > sceneView.bounds.width
            cameraYaw = isPortrait ? 0.50 : 0.62
            cameraPitch = isPortrait ? 0.44 : 0.52
            cameraDistance = isPortrait ? 10.35 : 8.2
            cameraTarget.position = isPortrait
                ? SCNVector3(0, 0.56, -0.18)
                : SCNVector3(0, 0.88, -0.08)
            cameraNode.camera?.fieldOfView = isPortrait ? 50 : 52
            hasAppliedResponsiveFraming = true
            updateCamera(animated: false)
        }
    }
}
