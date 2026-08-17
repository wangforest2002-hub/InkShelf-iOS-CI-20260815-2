import SceneKit

@MainActor
final class KokoSceneController {
    private weak var root: SCNNode?
    private var zone = KokoActivityZone()
    private var reduceMotion = false
    private var roamingEnabled = true
    private var restRotations: [String: SCNVector3] = [:]
    private var expressionNodes: [SCNNode] = []
    private var obstacles: [KokoObstacle] = []
    private var randomSeed: UInt64 = 0xC0C0_2026

    private let animatedBones = [
        "J_Bip_C_Hips", "J_Bip_C_Spine", "J_Bip_C_Chest", "J_Bip_C_UpperChest",
        "J_Bip_C_Neck", "J_Bip_C_Head",
        "J_Bip_L_UpperArm", "J_Bip_L_LowerArm", "J_Bip_L_Hand",
        "J_Bip_R_UpperArm", "J_Bip_R_LowerArm", "J_Bip_R_Hand",
        "J_Bip_L_UpperLeg", "J_Bip_L_LowerLeg", "J_Bip_L_Foot",
        "J_Bip_R_UpperLeg", "J_Bip_R_LowerLeg", "J_Bip_R_Foot"
    ]

    func install(
        root: SCNNode,
        zone: KokoActivityZone,
        roamingEnabled: Bool,
        reduceMotion: Bool,
        placements: [HomePlacement]
    ) {
        self.root = root
        self.zone = zone
        self.roamingEnabled = roamingEnabled
        self.reduceMotion = reduceMotion
        obstacles = makeObstacles(from: placements)
        root.position = SCNVector3(zone.centerX, 0, zone.centerZ + min(0.45, zone.depth * 0.18))
        root.eulerAngles.y = .pi
        configureComfortableBasePose()
        restRotations = Dictionary(uniqueKeysWithValues: animatedBones.compactMap { name in
            root.childNode(withName: name, recursively: true).map { (name, $0.eulerAngles) }
        })
        expressionNodes = root.childNodesWithMorphers()
        startBreathing()
        startBlinking()
    }

    func update(
        zone: KokoActivityZone,
        roamingEnabled: Bool,
        reduceMotion: Bool,
        placements: [HomePlacement]
    ) {
        self.zone = zone
        self.roamingEnabled = roamingEnabled
        self.reduceMotion = reduceMotion
        obstacles = makeObstacles(from: placements)
        guard let root else { return }
        root.position = clamped(root.position)
        if reduceMotion {
            root.removeAction(forKey: "koko-breathe")
            resetPose(animated: false)
        } else if root.action(forKey: "koko-breathe") == nil {
            startBreathing()
        }
    }

    func perform(_ decision: KokoDecision, target: SCNNode?) {
        guard let root else { return }
        root.removeAction(forKey: "koko-intention")
        stopWalkCycle()
        resetPose(animated: !reduceMotion)
        setExpression(for: decision.action)

        let destination = destination(for: decision.action, target: target)
        let movement = moveAction(from: root.position, to: destination)
        let focus = focusPoint(for: decision.action, target: target, destination: destination)
        let orientation = turnAction(from: destination, toward: focus)
        let pose = poseAction(for: decision.action, duration: decision.duration)
        let returnToNeutral = SCNAction.run { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resetPose(animated: true)
            }
        }
        let sequence: SCNAction
        if reduceMotion {
            root.position = destination
            face(focus)
            sequence = .sequence([pose, returnToNeutral])
        } else {
            sequence = .sequence([movement, orientation, pose, returnToNeutral])
        }
        root.runAction(sequence, forKey: "koko-intention")
    }

    private func configureComfortableBasePose() {
        guard let root else { return }
        // VRM files use a T-pose as their bind pose. Lowering both arms at
        // runtime keeps the full original rig intact for later gestures.
        root.childNode(withName: "J_Bip_L_UpperArm", recursively: true)?.eulerAngles.z += 1.18
        root.childNode(withName: "J_Bip_R_UpperArm", recursively: true)?.eulerAngles.z -= 1.18
        root.childNode(withName: "J_Bip_L_LowerArm", recursively: true)?.eulerAngles.z += 0.10
        root.childNode(withName: "J_Bip_R_LowerArm", recursively: true)?.eulerAngles.z -= 0.10
        root.childNode(withName: "J_Bip_C_Head", recursively: true)?.eulerAngles.x -= 0.035
    }

    private func startBreathing() {
        guard let root, !reduceMotion else { return }
        let breathe = SCNAction.sequence([
            .scale(to: 1.006, duration: 1.9),
            .scale(to: 1.0, duration: 2.2)
        ])
        breathe.timingMode = .easeInEaseOut
        root.runAction(.repeatForever(breathe), forKey: "koko-breathe")
    }

    private func startBlinking() {
        guard let root, !reduceMotion else { return }
        let blink = SCNAction.sequence([
            .wait(duration: 3.2, withRange: 2.4),
            .run { [weak self] _ in self?.setMorph(named: "Blink", weight: 1) },
            .wait(duration: 0.10),
            .run { [weak self] _ in self?.setMorph(named: "Blink", weight: 0) }
        ])
        root.runAction(.repeatForever(blink), forKey: "koko-blink")
    }

    private func destination(for action: KokoAction, target: SCNNode?) -> SCNVector3 {
        guard roamingEnabled else {
            return clamped(SCNVector3(zone.centerX, 0, zone.centerZ))
        }
        switch action {
        case .greet, .wave:
            return resolvedDestination(SCNVector3(zone.centerX - 0.72, 0, zone.centerZ + 0.58))
        case .admireBook, .read:
            if let target {
                let world = target.presentation.position
                return resolvedDestination(SCNVector3(world.x + 0.42, 0, world.z + 0.62))
            }
            return randomPoint()
        case .lookOutWindow:
            return resolvedDestination(SCNVector3(1.25, 0, -1.55))
        case .sit:
            return resolvedDestination(SCNVector3(0.95, 0, 0.85))
        case .tidy:
            return resolvedDestination(SCNVector3(-0.35, 0, -0.75))
        case .rest:
            return resolvedDestination(SCNVector3(0.65, 0, 0.95))
        case .stroll:
            return randomPoint()
        }
    }

    private func moveAction(from start: SCNVector3, to end: SCNVector3) -> SCNAction {
        guard let root else { return .wait(duration: 0) }
        let dx = end.x - start.x
        let dz = end.z - start.z
        let distance = sqrt(dx * dx + dz * dz)
        guard distance > 0.06 else { return .wait(duration: 0.18) }
        startWalkCycle(on: root)
        var cursor = start
        var actions: [SCNAction] = []
        for point in route(from: start, to: end) {
            let segmentX = point.x - cursor.x
            let segmentZ = point.z - cursor.z
            let segmentDistance = sqrt(segmentX * segmentX + segmentZ * segmentZ)
            let turn = SCNAction.rotateTo(
                x: 0,
                y: CGFloat(atan2(segmentX, segmentZ)),
                z: 0,
                duration: 0.30,
                usesShortestUnitArc: true
            )
            turn.timingMode = .easeInEaseOut
            let move = SCNAction.move(to: point, duration: TimeInterval(max(0.45, segmentDistance / 0.72)))
            move.timingMode = .easeInEaseOut
            actions.append(contentsOf: [turn, move])
            cursor = point
        }
        actions.append(.run { [weak self] _ in self?.stopWalkCycle() })
        return .sequence(actions)
    }

    private func focusPoint(for action: KokoAction, target: SCNNode?, destination: SCNVector3) -> SCNVector3 {
        switch action {
        case .admireBook, .read:
            return target?.presentation.position ?? SCNVector3(0, 0.8, -2.1)
        case .lookOutWindow:
            return SCNVector3(1.35, 1.45, -2.5)
        case .tidy:
            return SCNVector3(destination.x - 0.4, 0.4, destination.z - 0.5)
        case .greet, .wave, .sit, .rest:
            return SCNVector3(0, 1.2, 2.8)
        case .stroll:
            return SCNVector3(destination.x, 1.1, destination.z + 1)
        }
    }

    private func turnAction(from position: SCNVector3, toward target: SCNVector3) -> SCNAction {
        let yaw = atan2(target.x - position.x, target.z - position.z)
        let action = SCNAction.rotateTo(
            x: 0,
            y: CGFloat(yaw),
            z: 0,
            duration: 0.34,
            usesShortestUnitArc: true
        )
        action.timingMode = .easeInEaseOut
        return action
    }

    private func startWalkCycle(on root: SCNNode) {
        guard !reduceMotion else { return }
        let leftUpper = root.childNode(withName: "J_Bip_L_UpperLeg", recursively: true)
        let rightUpper = root.childNode(withName: "J_Bip_R_UpperLeg", recursively: true)
        let leftArm = root.childNode(withName: "J_Bip_L_UpperArm", recursively: true)
        let rightArm = root.childNode(withName: "J_Bip_R_UpperArm", recursively: true)
        runBoneCycle(leftUpper, amount: 0.28, key: "walk-left-leg")
        runBoneCycle(rightUpper, amount: -0.28, key: "walk-right-leg")
        runBoneCycle(leftArm, amount: -0.12, key: "walk-left-arm")
        runBoneCycle(rightArm, amount: 0.12, key: "walk-right-arm")
        root.runAction(.repeatForever(.wait(duration: 0.6)), forKey: "koko-walk-cycle")
    }

    private func runBoneCycle(_ bone: SCNNode?, amount: CGFloat, key: String) {
        guard let bone else { return }
        let forward = SCNAction.rotateBy(x: amount, y: 0, z: 0, duration: 0.30)
        let backward = SCNAction.rotateBy(x: -amount * 2, y: 0, z: 0, duration: 0.60)
        let center = SCNAction.rotateBy(x: amount, y: 0, z: 0, duration: 0.30)
        for action in [forward, backward, center] { action.timingMode = .easeInEaseOut }
        bone.runAction(.repeatForever(.sequence([forward, backward, center])), forKey: key)
    }

    private func stopWalkCycle() {
        guard let root else { return }
        root.removeAction(forKey: "koko-walk-cycle")
        for name in ["J_Bip_L_UpperLeg", "J_Bip_R_UpperLeg", "J_Bip_L_UpperArm", "J_Bip_R_UpperArm"] {
            let bone = root.childNode(withName: name, recursively: true)
            bone?.removeAction(forKey: "walk-left-leg")
            bone?.removeAction(forKey: "walk-right-leg")
            bone?.removeAction(forKey: "walk-left-arm")
            bone?.removeAction(forKey: "walk-right-arm")
        }
    }

    private func poseAction(for action: KokoAction, duration: TimeInterval) -> SCNAction {
        guard let root else { return .wait(duration: duration) }
        let settle = SCNAction.wait(duration: min(max(duration, 4), 45))
        switch action {
        case .greet, .wave:
            let upper = root.childNode(withName: "J_Bip_R_UpperArm", recursively: true)
            let lower = root.childNode(withName: "J_Bip_R_LowerArm", recursively: true)
            let raise = SCNAction.run { _ in
                upper?.runAction(.rotateBy(x: -0.20, y: 0, z: 1.15, duration: 0.42))
                lower?.runAction(.rotateBy(x: 0, y: 0, z: 0.72, duration: 0.42))
            }
            let wave = SCNAction.repeat(
                .sequence([
                    .run { _ in lower?.runAction(.rotateBy(x: 0, y: 0.30, z: 0, duration: 0.24)) },
                    .wait(duration: 0.25),
                    .run { _ in lower?.runAction(.rotateBy(x: 0, y: -0.30, z: 0, duration: 0.24)) },
                    .wait(duration: 0.25)
                ]),
                count: 3
            )
            return .sequence([raise, .wait(duration: 0.48), wave, settle])
        case .admireBook:
            let head = root.childNode(withName: "J_Bip_C_Head", recursively: true)
            return .group([
                settle,
                .sequence([
                    .run { _ in head?.runAction(.rotateBy(x: 0.12, y: -0.12, z: 0, duration: 0.8)) },
                    .wait(duration: max(1, duration * 0.45)),
                    .run { _ in head?.runAction(.rotateBy(x: -0.12, y: 0.24, z: 0, duration: 0.9)) }
                ])
            ])
        case .read:
            let leftUpper = root.childNode(withName: "J_Bip_L_UpperArm", recursively: true)
            let rightUpper = root.childNode(withName: "J_Bip_R_UpperArm", recursively: true)
            let leftLower = root.childNode(withName: "J_Bip_L_LowerArm", recursively: true)
            let rightLower = root.childNode(withName: "J_Bip_R_LowerArm", recursively: true)
            return .sequence([
                .run { _ in
                    leftUpper?.runAction(.rotateBy(x: -0.58, y: 0.08, z: -0.20, duration: 0.7))
                    rightUpper?.runAction(.rotateBy(x: -0.58, y: -0.08, z: 0.20, duration: 0.7))
                    leftLower?.runAction(.rotateBy(x: -0.55, y: 0, z: 0, duration: 0.7))
                    rightLower?.runAction(.rotateBy(x: -0.55, y: 0, z: 0, duration: 0.7))
                },
                settle
            ])
        case .tidy:
            let chest = root.childNode(withName: "J_Bip_C_Chest", recursively: true)
            let head = root.childNode(withName: "J_Bip_C_Head", recursively: true)
            return .sequence([
                .run { _ in
                    chest?.runAction(.rotateBy(x: 0.18, y: 0, z: 0, duration: 0.6))
                    head?.runAction(.rotateBy(x: -0.10, y: 0.14, z: 0, duration: 0.6))
                },
                settle
            ])
        case .lookOutWindow:
            let head = root.childNode(withName: "J_Bip_C_Head", recursively: true)
            return .group([
                settle,
                .sequence([
                    .wait(duration: 1.1),
                    .run { _ in head?.runAction(.rotateBy(x: 0, y: 0.17, z: 0.025, duration: 1.1)) }
                ])
            ])
        case .sit, .rest:
            let hips = root.childNode(withName: "J_Bip_C_Hips", recursively: true)
            let leftUpper = root.childNode(withName: "J_Bip_L_UpperLeg", recursively: true)
            let rightUpper = root.childNode(withName: "J_Bip_R_UpperLeg", recursively: true)
            let leftLower = root.childNode(withName: "J_Bip_L_LowerLeg", recursively: true)
            let rightLower = root.childNode(withName: "J_Bip_R_LowerLeg", recursively: true)
            return .sequence([
                .moveBy(x: 0, y: -0.34, z: 0, duration: 0.75),
                .run { _ in
                    hips?.runAction(.rotateBy(x: -0.10, y: 0, z: 0, duration: 0.65))
                    leftUpper?.runAction(.rotateBy(x: -0.88, y: 0, z: 0, duration: 0.65))
                    rightUpper?.runAction(.rotateBy(x: -0.88, y: 0, z: 0, duration: 0.65))
                    leftLower?.runAction(.rotateBy(x: 1.20, y: 0, z: 0, duration: 0.65))
                    rightLower?.runAction(.rotateBy(x: 1.20, y: 0, z: 0, duration: 0.65))
                },
                settle,
                .moveBy(x: 0, y: 0.34, z: 0, duration: 0.7)
            ])
        case .stroll:
            return settle
        }
    }

    private func resetPose(animated: Bool) {
        guard let root else { return }
        for (name, rotation) in restRotations {
            guard let bone = root.childNode(withName: name, recursively: true) else { continue }
            bone.removeAllActions()
            if animated {
                let action = SCNAction.rotateTo(
                    x: CGFloat(rotation.x),
                    y: CGFloat(rotation.y),
                    z: CGFloat(rotation.z),
                    duration: 0.34,
                    usesShortestUnitArc: true
                )
                action.timingMode = .easeInEaseOut
                bone.runAction(action)
            } else {
                bone.eulerAngles = rotation
            }
        }
        setAllExpressionsToZero()
    }

    private func setExpression(for action: KokoAction) {
        let name: String?
        switch action {
        case .greet, .wave: name = "Joy"
        case .admireBook, .read: name = "Fun"
        case .lookOutWindow, .rest: name = nil
        case .stroll, .tidy, .sit: name = "Joy"
        }
        if let name { setMorph(named: name, weight: 0.62) }
    }

    private func setAllExpressionsToZero() {
        for node in expressionNodes {
            guard let morpher = node.morpher else { continue }
            for index in morpher.targets.indices { morpher.setWeight(0, forTargetAt: index) }
        }
    }

    private func setMorph(named name: String, weight: CGFloat) {
        for node in expressionNodes {
            guard let morpher = node.morpher else { continue }
            for (index, target) in morpher.targets.enumerated()
                where target.name?.localizedCaseInsensitiveContains(name) == true {
                morpher.setWeight(weight, forTargetAt: index)
            }
        }
    }

    private func face(_ target: SCNVector3) {
        guard let root else { return }
        let dx = target.x - root.position.x
        let dz = target.z - root.position.z
        root.eulerAngles.y = atan2(dx, dz)
    }

    private func clamped(_ position: SCNVector3) -> SCNVector3 {
        let margin: Float = 0.28
        let minX = zone.centerX - zone.width / 2 + margin
        let maxX = zone.centerX + zone.width / 2 - margin
        let minZ = zone.centerZ - zone.depth / 2 + margin
        let maxZ = zone.centerZ + zone.depth / 2 - margin
        return SCNVector3(
            min(max(position.x, minX), maxX),
            max(0, position.y),
            min(max(position.z, minZ), maxZ)
        )
    }

    private func randomPoint() -> SCNVector3 {
        for _ in 0..<8 {
            let unitX = nextRandomUnit()
            let unitZ = nextRandomUnit()
            let candidate = clamped(SCNVector3(
                zone.centerX + (unitX - 0.5) * max(0.3, zone.width - 0.7),
                0,
                zone.centerZ + (unitZ - 0.5) * max(0.3, zone.depth - 0.7)
            ))
            if isClear(candidate, margin: 0.30) { return candidate }
        }
        return resolvedDestination(SCNVector3(zone.centerX, 0, zone.centerZ))
    }

    private func resolvedDestination(_ proposed: SCNVector3) -> SCNVector3 {
        var result = clamped(proposed)
        for obstacle in obstacles {
            let dx = result.x - obstacle.x
            let dz = result.z - obstacle.z
            let distance = max(sqrt(dx * dx + dz * dz), 0.001)
            let safeRadius = obstacle.radius + 0.30
            guard distance < safeRadius else { continue }
            result.x = obstacle.x + dx / distance * safeRadius
            result.z = obstacle.z + dz / distance * safeRadius
            result = clamped(result)
        }
        return result
    }

    private func route(from start: SCNVector3, to end: SCNVector3) -> [SCNVector3] {
        guard let obstacle = obstacles.first(where: {
            distanceFromSegment(x: $0.x, z: $0.z, start: start, end: end) < $0.radius + 0.26
        }) else { return [end] }

        let dx = end.x - start.x
        let dz = end.z - start.z
        let length = max(sqrt(dx * dx + dz * dz), 0.001)
        let offset = obstacle.radius + 0.42
        let perpendicularX = -dz / length
        let perpendicularZ = dx / length
        let first = resolvedDestination(SCNVector3(
            obstacle.x + perpendicularX * offset,
            0,
            obstacle.z + perpendicularZ * offset
        ))
        let second = resolvedDestination(SCNVector3(
            obstacle.x - perpendicularX * offset,
            0,
            obstacle.z - perpendicularZ * offset
        ))
        let firstCost = planarDistance(start, first) + planarDistance(first, end)
        let secondCost = planarDistance(start, second) + planarDistance(second, end)
        return [firstCost <= secondCost ? first : second, end]
    }

    private func isClear(_ point: SCNVector3, margin: Float) -> Bool {
        obstacles.allSatisfy { obstacle in
            let dx = point.x - obstacle.x
            let dz = point.z - obstacle.z
            return sqrt(dx * dx + dz * dz) >= obstacle.radius + margin
        }
    }

    private func distanceFromSegment(x: Float, z: Float, start: SCNVector3, end: SCNVector3) -> Float {
        let dx = end.x - start.x
        let dz = end.z - start.z
        let denominator = dx * dx + dz * dz
        guard denominator > 0.0001 else {
            let pointX = x - start.x
            let pointZ = z - start.z
            return sqrt(pointX * pointX + pointZ * pointZ)
        }
        let t = min(max(((x - start.x) * dx + (z - start.z) * dz) / denominator, 0), 1)
        let pointX = x - (start.x + dx * t)
        let pointZ = z - (start.z + dz * t)
        return sqrt(pointX * pointX + pointZ * pointZ)
    }

    private func planarDistance(_ first: SCNVector3, _ second: SCNVector3) -> Float {
        let dx = first.x - second.x
        let dz = first.z - second.z
        return sqrt(dx * dx + dz * dz)
    }

    private func makeObstacles(from placements: [HomePlacement]) -> [KokoObstacle] {
        placements.compactMap { placement in
            guard placement.kind == .furniture,
                  let furniture = placement.furniture,
                  ![.rug, .cushion].contains(furniture)
            else { return nil }
            let baseRadius: Float
            switch furniture {
            case .sofa, .bed: baseRadius = 0.78
            case .bookshelf, .displayCabinet, .desk, .screen: baseRadius = 0.58
            case .lowTable: baseRadius = 0.48
            case .stool: baseRadius = 0.31
            case .floorLamp, .plant: baseRadius = 0.24
            case .rug, .cushion: return nil
            }
            return KokoObstacle(
                x: placement.transform.x,
                z: placement.transform.z,
                radius: baseRadius * placement.transform.scale
            )
        }
    }

    private func nextRandomUnit() -> Float {
        randomSeed = randomSeed &* 6_364_136_223_846_793_005 &+ 1
        return Float((randomSeed >> 40) & 0xFF_FFFF) / Float(0xFF_FFFF)
    }
}

private struct KokoObstacle {
    let x: Float
    let z: Float
    let radius: Float
}

private extension SCNNode {
    func childNodesWithMorphers() -> [SCNNode] {
        var nodes: [SCNNode] = []
        enumerateChildNodes { node, _ in
            if node.morpher != nil { nodes.append(node) }
        }
        return nodes
    }
}
