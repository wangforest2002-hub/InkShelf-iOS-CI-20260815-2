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
        private var usesFirstPersonCamera = true
        private var lastEditingState: Bool?
        private var firstPersonPosition = SCNVector3(-0.18, 1.52, 1.94)
        private var firstPersonYaw: Float = 2.88
        private var firstPersonPitch: Float = -0.14
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
            // The window panorama is authored in display-ready SDR. Automatic HDR
            // exposure was lifting it several stops and clipping the Tokyo view to
            // a flat cream rectangle on real iOS renderers.
            camera.wantsHDR = false
            camera.wantsExposureAdaptation = false
            camera.exposureOffset = 0
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
            pan.maximumNumberOfTouches = 1
            pinch.delegate = self
            rotation.delegate = self
            view.addGestureRecognizer(tap)
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(pinch)
            view.addGestureRecognizer(rotation)
            view.accessibilityIdentifier = "home-3d-scene"
            view.accessibilityLabel = "可自由布置的三维小家"
            view.accessibilityHint = "单指拖动环顾，双指捏合前后移动，轻点空地走过去；布置模式下可移动物品"
            Task { @MainActor [weak self] in
                self?.applyResponsiveFramingIfNeeded()
            }
        }

        func sync(with value: HomeSceneView) {
            guard let sceneView else { return }
            applyResponsiveFramingIfNeeded()
            updateCameraModeIfNeeded(isEditing: value.isEditing)
            if currentTheme != value.state.theme {
                roomNode?.removeFromParentNode()
                let room = factory.makeRoom(theme: value.state.theme)
                contentRoot.addChildNode(room)
                roomNode = room
                scene.background.contents = factory.backgroundImage(theme: value.state.theme)
                currentTheme = value.state.theme
                updateRoomShellVisibility(isEditing: value.isEditing)
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

            kokoNode?.removeFromParentNode()
            kokoNode = nil

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

            lastKokoDecisionRevision = value.kokoDecisionRevision
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
            if !parent.isEditing, isRoomFloor(hit.node) {
                moveFirstPerson(to: hit.worldCoordinates)
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
                    if usesFirstPersonCamera {
                        firstPersonYaw -= Float(translation.x) * 0.0046
                        firstPersonPitch = min(max(firstPersonPitch - Float(translation.y) * 0.0032, -0.48), 0.48)
                    } else {
                        cameraYaw -= Float(translation.x) * 0.0052
                        cameraPitch = min(max(cameraPitch + Float(translation.y) * 0.0035, 0.25), 0.94)
                    }
                    recognizer.setTranslation(.zero, in: view)
                    updateCamera(animated: false)
                default:
                    break
                }
            }
        }

        @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
            guard recognizer.state == .changed else { return }
            if usesFirstPersonCamera {
                let amount = Float(log(Double(recognizer.scale))) * 0.92
                let forward = SCNVector3(sin(firstPersonYaw), 0, cos(firstPersonYaw))
                firstPersonPosition.x = min(max(firstPersonPosition.x + forward.x * amount, -2.56), 2.56)
                firstPersonPosition.z = min(max(firstPersonPosition.z + forward.z * amount, -2.10), 2.10)
            } else {
                cameraDistance = min(max(cameraDistance / Float(recognizer.scale), 4.1), 13.5)
            }
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
            let position: SCNVector3
            let target: SCNVector3
            if usesFirstPersonCamera {
                let horizontal = cos(firstPersonPitch)
                let direction = SCNVector3(
                    sin(firstPersonYaw) * horizontal,
                    sin(firstPersonPitch),
                    cos(firstPersonYaw) * horizontal
                )
                position = firstPersonPosition
                target = SCNVector3(
                    position.x + direction.x * 4,
                    position.y + direction.y * 4,
                    position.z + direction.z * 4
                )
            } else {
                let horizontal = cameraDistance * cos(cameraPitch)
                position = SCNVector3(
                    sin(cameraYaw) * horizontal,
                    max(1.7, cameraDistance * sin(cameraPitch)),
                    cos(cameraYaw) * horizontal
                )
                target = cameraTarget.position
            }
            if animated {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.45
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                cameraNode.position = position
                cameraTarget.position = target
                SCNTransaction.commit()
            } else {
                cameraNode.position = position
                cameraTarget.position = target
            }
        }

        private func updateCameraModeIfNeeded(isEditing: Bool) {
            guard lastEditingState != isEditing else { return }
            lastEditingState = isEditing
            usesFirstPersonCamera = !isEditing
            cameraNode.camera?.fieldOfView = usesFirstPersonCamera ? 67 : 50
            if !usesFirstPersonCamera {
                cameraTarget.position = SCNVector3(0, 0.86, -0.10)
            }
            updateRoomShellVisibility(isEditing: isEditing)
            updateCamera(animated: true)
        }

        private func updateRoomShellVisibility(isEditing: Bool) {
            ["room-right-wall", "room-front-wall", "room-ceiling", "room-entryway"].forEach { name in
                roomNode?.childNode(withName: name, recursively: true)?.isHidden = isEditing
            }
        }

        private func isRoomFloor(_ node: SCNNode) -> Bool {
            var current: SCNNode? = node
            while let candidate = current {
                if candidate.name == "room-floor" { return true }
                current = candidate.parent
            }
            return false
        }

        private func moveFirstPerson(to location: SCNVector3) {
            guard usesFirstPersonCamera else { return }
            firstPersonPosition.x = min(max(location.x, -2.56), 2.56)
            firstPersonPosition.z = min(max(location.z, -2.10), 2.10)
            firstPersonPosition.y = 1.52
            updateCamera(animated: true)
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
            cameraDistance = isPortrait ? 9.35 : 8.2
            cameraTarget.position = isPortrait
                ? SCNVector3(0, 0.78, -0.18)
                : SCNVector3(0, 0.88, -0.08)
            firstPersonPosition = isPortrait
                ? SCNVector3(-0.18, 1.52, 1.94)
                : SCNVector3(-0.28, 1.55, 1.72)
            firstPersonYaw = isPortrait ? 2.88 : 2.84
            firstPersonPitch = isPortrait ? -0.14 : -0.11
            cameraNode.camera?.fieldOfView = usesFirstPersonCamera ? (isPortrait ? 59 : 66) : (isPortrait ? 50 : 52)
            hasAppliedResponsiveFraming = true
            updateCamera(animated: false)
        }
    }
}
