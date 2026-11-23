import SceneKit
import UIKit
import simd

/// The 3-D scene: one or two arcade lanes (each in its own arena frame, placed in the world by the layout),
/// lights, balls with soft shadows, a cord net that swishes and rattles, sparks and the fire trail. One camera per
/// viewport gets an off-axis projection from the viewer's eye every frame, so the hoop stands in the room.
final class Gym {
    let scene = SCNScene()
    private(set) var cameras: [SCNNode] = []
    private var arenas: [ArenaNodes] = []
    private(set) var theme: ArenaTheme
    private(set) var skin: BallSkin
    private var layout: SceneLayout?
    private let lights = SCNNode()
    private var sparks: [Spark] = []
    private let effects = SCNNode()

    private struct Spark { var node: SCNNode; var p: SIMD3<Float>; var v: SIMD3<Float>; var born: Double; var life: Double; var arena: Int }

    init(theme: ArenaTheme, skin: BallSkin) {
        self.theme = theme
        self.skin = skin
        scene.background.contents = UIColor(hex: theme.wall)
        scene.rootNode.addChildNode(lights)
        scene.rootNode.addChildNode(effects)
        buildLights()
    }

    private func makeCamera() -> SCNNode {
        let c = SCNCamera()
        c.automaticallyAdjustsZRange = false
        c.zNear = 0.01
        c.zFar = 40
        c.wantsHDR = true
        c.wantsExposureAdaptation = false
        c.bloomIntensity = 1.1
        c.bloomThreshold = 0.8
        c.bloomBlurRadius = 9
        c.vignettingIntensity = 0
        let n = SCNNode()
        n.camera = c
        return n
    }

    private func buildLights() {
        lights.childNodes.forEach { $0.removeFromParentNode() }
        let amb = SCNLight(); amb.type = .ambient; amb.intensity = theme.ambient; amb.color = UIColor(white: 0.9, alpha: 1)
        let a = SCNNode(); a.light = amb; lights.addChildNode(a)
        let key = SCNLight(); key.type = .directional; key.intensity = 650; key.color = UIColor(hex: 0xfff1de)
        let k = SCNNode(); k.light = key; k.eulerAngles = SCNVector3(-1.05, 0.35, 0); lights.addChildNode(k)
        let fill = SCNLight(); fill.type = .directional; fill.intensity = 260; fill.color = UIColor(hex: theme.neonB)
        let f = SCNNode(); f.light = fill; f.eulerAngles = SCNVector3(-0.5, -2.2, 0); lights.addChildNode(f)
    }

    // MARK: Configuration

    func configure(_ l: SceneLayout) {
        let structural = layout.map { !$0.sameStructure(as: l) } ?? true
        layout = l
        while cameras.count < l.viewports.count { let c = makeCamera(); scene.rootNode.addChildNode(c); cameras.append(c) }
        if structural {
            arenas.forEach { $0.root.removeFromParentNode() }
            arenas = l.arenas.map { ArenaNodes(slot: $0, theme: theme, skin: skin) }
            arenas.forEach { scene.rootNode.addChildNode($0.root) }
            sparks.forEach { $0.node.removeFromParentNode() }
            sparks = []
        } else {
            for (i, a) in arenas.enumerated() { a.update(slot: l.arenas[i]) }
        }
    }

    func setTheme(_ t: ArenaTheme) {
        theme = t
        scene.background.contents = UIColor(hex: t.wall)
        buildLights()
        if let l = layout { layout = nil; configure(l) }
    }

    func setSkin(_ s: BallSkin) {
        skin = s
        arenas.forEach { $0.setSkin(s) }
    }

    // MARK: Frame

    /// Cameras from each viewport's eye (world units).
    func updateCameras(eyes: [SIMD3<Float>]) {
        guard let l = layout else { return }
        for (i, vp) in l.viewports.enumerated() where i < cameras.count {
            let eye = i < eyes.count ? eyes[i] : l.arenas[vp.arena].eye
            let o = OffAxis(eye: eye, surface: vp.surface, near: 0.01, far: 40)
            cameras[i].simdTransform = o.cameraTransform
            cameras[i].camera?.projectionTransform = SCNMatrix4(o.projection)
        }
    }

    func update(lanes: [Lane], fire: [Bool], t: Double, dt: Float) {
        for (i, a) in arenas.enumerated() where i < lanes.count {
            a.update(lane: lanes[i], fire: i < fire.count ? fire[i] : false, t: t, dt: dt)
        }
        updateSparks(t: t, dt: dt)
    }

    // MARK: Effects

    func swish(arena i: Int, strength: Float) { guard i < arenas.count else { return }; arenas[i].net.swish(strength) }
    func rattle(arena i: Int, strength: Float) { guard i < arenas.count else { return }; arenas[i].net.rattle(strength); arenas[i].flashRim(strength) }
    func flashBoard(arena i: Int) { guard i < arenas.count else { return }; arenas[i].flashBoard() }

    /// A burst of glowing sparks around the rim (arena units).
    func burst(arena i: Int, at p: SIMD3<Float>, count: Int, colors: [UInt32], t: Double) {
        guard i < arenas.count else { return }
        for k in 0..<count {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = Textures.glowDot()
            m.multiply.contents = UIColor(hex: colors[k % colors.count])
            m.emission.contents = UIColor(hex: colors[k % colors.count])
            m.blendMode = .add
            m.writesToDepthBuffer = false
            let plane = SCNPlane(width: 0.035, height: 0.035)
            plane.materials = [m]
            let n = SCNNode(geometry: plane)
            n.constraints = [SCNBillboardConstraint()]
            arenas[i].root.addChildNode(n)
            let a = Float(k) / Float(count) * 2 * .pi + Float.random(in: -0.2...0.2)
            let v = SIMD3<Float>(cos(a) * Float.random(in: 0.3...0.75), Float.random(in: 0.4...1.2), sin(a) * Float.random(in: 0.3...0.75))
            sparks.append(Spark(node: n, p: p, v: v, born: t, life: Double.random(in: 0.6...1.1), arena: i))
        }
    }

    private func updateSparks(t: Double, dt: Float) {
        var keep: [Spark] = []
        for var s in sparks {
            let age = t - s.born
            if age > s.life { s.node.removeFromParentNode(); continue }
            s.v.y -= Arena.gravity * 0.6 * dt
            s.v *= 1 - 1.2 * dt
            s.p += s.v * dt
            s.node.simdPosition = s.p
            let k = Float(1 - age / s.life)
            s.node.opacity = CGFloat(k)
            s.node.simdScale = SIMD3(repeating: 0.5 + k)
            keep.append(s)
        }
        sparks = keep
    }
}

extension SceneLayout {
    /// Same presentation and number of lanes and views: only surfaces and walls changed (the hinge moved).
    func sameStructure(as o: SceneLayout) -> Bool {
        presentation == o.presentation && arenas.count == o.arenas.count && viewports.count == o.viewports.count
            && zip(arenas, o.arenas).allSatisfy { abs($0.depth - $1.depth) < 0.01 && abs($0.halfWidth - $1.halfWidth) < 0.01 && $0.placement == $1.placement }
    }
}

// MARK: - One lane's nodes

final class ArenaNodes {
    let root = SCNNode()
    private let hoop = SCNNode()          // backboard, rim and net; slides sideways
    private let rimNode: SCNNode
    private let boardGlass: SCNNode
    private let boardFrameMat = SCNMaterial()
    private let rimMat = SCNMaterial()
    let net: Net
    private var balls: [SCNNode] = []
    private var shadows: [SCNNode] = []
    private var trails: [[SCNNode]] = []
    private var trailHistory: [[SIMD3<Float>]] = []
    private var orientations: [simd_quatf] = []
    private let ballMat = SCNMaterial()
    private var slot: ArenaSlot
    private let theme: ArenaTheme
    private var rimFlash: Float = 0
    private var boardFlash: Float = 0
    private var skin: BallSkin
    private var showingFire = false

    init(slot: ArenaSlot, theme: ArenaTheme, skin: BallSkin) {
        self.slot = slot
        self.theme = theme
        self.skin = skin
        rimNode = SCNNode()
        boardGlass = SCNNode()
        net = Net()
        root.simdTransform = slot.placement.matrix
        buildRoom()
        buildHoop()
        buildBalls(skin)
        update(slot: slot)
    }

    func update(slot s: ArenaSlot) {
        slot = s
        root.simdTransform = s.placement.matrix
        hoop.simdPosition = SIMD3(hoop.simdPosition.x, 0, s.setback)
        rimNode.simdPosition = SIMD3(0, Arena.rimHeight, s.crease + Arena.rimRadius + Arena.rimTube)
        net.node.simdPosition = rimNode.simdPosition
    }

    // MARK: Building

    private func mat(_ c: UIColor, lambert: Bool = true) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = lambert ? .lambert : .physicallyBased
        m.diffuse.contents = c
        return m
    }

    private func neon(_ hex: UInt32, _ intensity: CGFloat = 2.2) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(hex: hex)
        m.emission.contents = UIColor(hex: hex)
        m.emission.intensity = intensity
        return m
    }

    private func add(_ g: SCNGeometry, _ m: SCNMaterial, at p: SIMD3<Float>, euler: SIMD3<Float> = .zero, to parent: SCNNode? = nil) -> SCNNode {
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.simdPosition = p
        n.simdEulerAngles = euler
        (parent ?? root).addChildNode(n)
        return n
    }

    private func buildRoom() {
        let hw = slot.halfWidth
        let depth = slot.depth
        let far: Float = slot.sunken ? 0 : -1
        let length = depth + 0.3 - far
        // Floor.
        let fm = SCNMaterial()
        fm.lightingModel = .lambert
        fm.diffuse.contents = Textures.floor(theme)
        fm.diffuse.wrapS = .repeat
        fm.diffuse.wrapT = .clamp
        let width = 2 * hw
        // Map the texture's fixed lane coordinates (x −0.5…0.5, z −1…1.3) onto this floor.
        let su = width, sv = length / 2.3
        let tu = 0.5 - hw, tv = (far + 1) / 2.3
        fm.diffuse.contentsTransform = SCNMatrix4Mult(SCNMatrix4MakeScale(su, sv, 1), SCNMatrix4MakeTranslation(tu, tv, 0))
        let floor = SCNPlane(width: CGFloat(width), height: CGFloat(length))
        _ = add(floor, fm, at: SIMD3(0, 0, far + length / 2), euler: SIMD3(-.pi / 2, 0, 0))

        let wallMat = SCNMaterial()
        wallMat.lightingModel = .lambert
        wallMat.diffuse.contents = Textures.wall(theme)
        wallMat.diffuse.wrapS = .repeat
        wallMat.diffuse.wrapT = .repeat
        if slot.sunken {
            // A pit under the glass: walls up to the glass on every side, the fold wall behind the board.
            let top = Arena.boardTop
            wallMat.diffuse.contentsTransform = SCNMatrix4MakeScale(2, 1, 1)
            _ = add(SCNPlane(width: CGFloat(width), height: CGFloat(top)), wallMat, at: SIMD3(0, top / 2, 0))
            let near = SCNPlane(width: CGFloat(width), height: CGFloat(top))
            _ = add(near, wallMat, at: SIMD3(0, top / 2, depth), euler: SIMD3(0, .pi, 0))
            for side: Float in [-1, 1] {
                _ = add(SCNPlane(width: CGFloat(depth), height: CGFloat(top)), wallMat, at: SIMD3(side * hw, top / 2, depth / 2), euler: SIMD3(0, -side * .pi / 2, 0))
                _ = add(SCNBox(width: 0.02, height: 0.012, length: CGFloat(depth), chamferRadius: 0.004), neon(side < 0 ? theme.neonA : theme.neonB),
                        at: SIMD3(side * (hw - 0.012), 0.012, depth / 2))
            }
            _ = add(SCNBox(width: CGFloat(width), height: 0.012, length: 0.02, chamferRadius: 0.004), neon(theme.neonB, 1.6), at: SIMD3(0, top - 0.01, 0.012))
        } else {
            // Gym back wall far behind the board, with a neon sign; cabinet rails along the lane.
            let wallZ: Float = -0.9
            wallMat.diffuse.contentsTransform = SCNMatrix4MakeScale(3, 2, 1)
            _ = add(SCNPlane(width: 6, height: 4), wallMat, at: SIMD3(0, 2 - 0.001, wallZ))
            let signMat = SCNMaterial()
            signMat.lightingModel = .constant
            signMat.diffuse.contents = Textures.sign(theme.sign, color: theme.neonA)
            signMat.emission.contents = Textures.sign(theme.sign, color: theme.neonA)
            signMat.emission.intensity = 1.6
            signMat.blendMode = .add
            signMat.writesToDepthBuffer = false
            _ = add(SCNPlane(width: 1.6, height: 0.4), signMat, at: SIMD3(0, 1.05, wallZ + 0.01))
            for side: Float in [-1, 1] {
                // Side walls of the room, so wide windows never see the void.
                _ = add(SCNPlane(width: 3, height: 4), wallMat, at: SIMD3(side * 2.2, 2, 0.4), euler: SIMD3(0, -side * .pi / 2, 0))
                // Lane rails with a neon strip on top.
                let rail = SCNBox(width: 0.04, height: 0.07, length: CGFloat(depth + 0.9), chamferRadius: 0.01)
                _ = add(rail, mat(UIColor(hex: theme.wallAccent)), at: SIMD3(side * (hw + 0.02), 0.035, (depth - 0.9) / 2))
                _ = add(SCNBox(width: 0.012, height: 0.01, length: CGFloat(depth + 0.9), chamferRadius: 0.004), neon(side < 0 ? theme.neonA : theme.neonB),
                        at: SIMD3(side * (hw + 0.02), 0.075, (depth - 0.9) / 2))
            }
            // Floor beyond the lane on both sides.
            let outside = mat(UIColor(hex: theme.wallAccent))
            for side: Float in [-1, 1] {
                _ = add(SCNPlane(width: 2, height: CGFloat(length)), outside, at: SIMD3(side * (hw + 1), -0.002, far + length / 2), euler: SIMD3(-.pi / 2, 0, 0))
            }
        }
        // Ball tray at the shooter's end.
        let rackZ = min(Arena.rackDistance, depth - 0.1)
        let tray = SCNBox(width: 0.62, height: 0.012, length: 0.14, chamferRadius: 0.006)
        _ = add(tray, mat(UIColor(hex: 0x151018)), at: SIMD3(0, 0.006, rackZ + 0.02))
        _ = add(SCNBox(width: 0.62, height: 0.006, length: 0.008, chamferRadius: 0.002), neon(theme.neonB, 1.4), at: SIMD3(0, 0.014, rackZ + 0.09))
    }

    private func buildHoop() {
        root.addChildNode(hoop)
        let bw = 2 * Arena.boardHalfWidth, bh = Arena.boardTop - Arena.boardBottom
        let glass = SCNMaterial()
        glass.lightingModel = .physicallyBased
        glass.diffuse.contents = Textures.board(theme)
        glass.metalness.contents = 0.1
        glass.roughness.contents = 0.08
        glass.transparencyMode = .dualLayer
        glass.isDoubleSided = true
        glass.blendMode = .alpha
        let g = SCNBox(width: CGFloat(bw), height: CGFloat(bh), length: CGFloat(Arena.boardThickness * 0.5), chamferRadius: 0.004)
        g.materials = [glass]
        boardGlass.geometry = g
        boardGlass.simdPosition = SIMD3(0, (Arena.boardTop + Arena.boardBottom) / 2, -Arena.boardThickness * 0.5)
        hoop.addChildNode(boardGlass)
        // Neon frame around the board.
        boardFrameMat.lightingModel = .constant
        boardFrameMat.diffuse.contents = UIColor(hex: theme.boardFrame)
        boardFrameMat.emission.contents = UIColor(hex: theme.boardFrame)
        boardFrameMat.emission.intensity = 1.4
        let t: Float = 0.012
        for (w, h, p) in [(bw + t, t, SIMD3<Float>(0, Arena.boardTop, 0)), (bw + t, t, SIMD3(0, Arena.boardBottom, 0)),
                          (t, bh, SIMD3(-bw / 2, (Arena.boardTop + Arena.boardBottom) / 2, 0)), (t, bh, SIMD3(bw / 2, (Arena.boardTop + Arena.boardBottom) / 2, 0))] {
            let b = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(t), chamferRadius: 0.003)
            b.materials = [boardFrameMat]
            let n = SCNNode(geometry: b)
            n.simdPosition = p + SIMD3(0, 0, -Arena.boardThickness * 0.25)
            hoop.addChildNode(n)
        }
        // Support pole behind the board, down to the floor.
        let pole = SCNCylinder(radius: 0.018, height: CGFloat(Arena.boardBottom + 0.05))
        pole.materials = [mat(UIColor(hex: 0x2a2a34), lambert: false)]
        let pn = SCNNode(geometry: pole)
        pn.simdPosition = SIMD3(0, (Arena.boardBottom + 0.05) / 2, -Arena.boardThickness - 0.03)
        hoop.addChildNode(pn)
        // Rim.
        rimMat.lightingModel = .physicallyBased
        rimMat.diffuse.contents = UIColor(hex: theme.rim)
        rimMat.metalness.contents = 0.6
        rimMat.roughness.contents = 0.35
        rimMat.emission.contents = UIColor(hex: theme.rim)
        rimMat.emission.intensity = 0
        let torus = SCNTorus(ringRadius: CGFloat(Arena.rimRadius), pipeRadius: CGFloat(Arena.rimTube))
        torus.ringSegmentCount = 48
        torus.pipeSegmentCount = 12
        torus.materials = [rimMat]
        rimNode.geometry = torus
        hoop.addChildNode(rimNode)
        // Bracket from the board to the rim.
        let bracket = SCNBox(width: 0.05, height: 0.01, length: 0.03, chamferRadius: 0.002)
        bracket.materials = [rimMat]
        let bn = SCNNode(geometry: bracket)
        bn.simdPosition = SIMD3(0, -0.006, -Arena.rimRadius - 0.006)
        rimNode.addChildNode(bn)
        hoop.addChildNode(net.node)
    }

    private func buildBalls(_ skin: BallSkin) {
        setSkin(skin)
        let blob = SCNMaterial()
        blob.lightingModel = .constant
        blob.diffuse.contents = Textures.blob()
        blob.writesToDepthBuffer = false
        blob.blendMode = .alpha
        for _ in 0..<Lane.ballCount {
            let s = SCNSphere(radius: CGFloat(Arena.ballRadius))
            s.segmentCount = 36
            s.materials = [ballMat]
            let n = SCNNode(geometry: s)
            root.addChildNode(n)
            balls.append(n)
            orientations.append(simd_quatf(angle: Float.random(in: 0...6), axis: simd_normalize(SIMD3(0.3, 1, 0.2))))
            let sh = SCNNode(geometry: SCNPlane(width: CGFloat(Arena.ballRadius * 2.6), height: CGFloat(Arena.ballRadius * 2.6)))
            sh.geometry?.materials = [blob]
            sh.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
            sh.renderingOrder = 5
            root.addChildNode(sh)
            shadows.append(sh)
            var trail: [SCNNode] = []
            for k in 0..<7 {
                let tm = SCNMaterial()
                tm.lightingModel = .constant
                tm.diffuse.contents = Textures.glowDot()
                tm.multiply.contents = UIColor(hex: k < 3 ? 0xffd34a : 0xff5a1a)
                tm.blendMode = .add
                tm.writesToDepthBuffer = false
                let p = SCNPlane(width: CGFloat(Arena.ballRadius * 2.4), height: CGFloat(Arena.ballRadius * 2.4))
                p.materials = [tm]
                let tn = SCNNode(geometry: p)
                tn.constraints = [SCNBillboardConstraint()]
                tn.isHidden = true
                root.addChildNode(tn)
                trail.append(tn)
            }
            trails.append(trail)
            trailHistory.append([])
        }
    }

    func setSkin(_ s: BallSkin) {
        skin = s
        showingFire = false
        ballMat.lightingModel = .physicallyBased
        ballMat.diffuse.contents = Textures.ball(s)
        ballMat.roughness.contents = s.metal > 0 ? 0.2 : 0.62
        ballMat.metalness.contents = s.metal
        ballMat.emission.contents = s.glow ? Textures.ball(s) : UIColor.black
        ballMat.emission.intensity = s.glow ? 0.9 : 0
    }

    func flashRim(_ s: Float) { rimFlash = max(rimFlash, min(1, s)) }
    func flashBoard() { boardFlash = 1 }

    // MARK: Frame

    func update(lane: Lane, fire: Bool, t: Double, dt: Float) {
        hoop.simdPosition = SIMD3(lane.slide, 0, lane.slot.setback)
        for (i, b) in lane.balls.enumerated() where i < balls.count {
            let n = balls[i]
            n.simdPosition = b.p
            let w = b.spin
            let speed = simd_length(w)
            if speed > 1e-3 {
                orientations[i] = simd_normalize(simd_quatf(angle: speed * dt, axis: w / speed) * orientations[i])
            }
            n.simdOrientation = orientations[i]
            let h = max(0, b.p.y - Arena.ballRadius)
            let sh = shadows[i]
            sh.simdPosition = SIMD3(b.p.x, 0.002, b.p.z)
            let k = 1 + h * 2.2
            sh.simdScale = SIMD3(k, k, 1)
            sh.opacity = CGFloat(max(0.15, 0.85 - h * 1.4))
            // Fire trail for the shooter's balls in the air.
            let flying = b.state == .flying
            if fire && flying {
                trailHistory[i].insert(b.p, at: 0)
                if trailHistory[i].count > 14 { trailHistory[i].removeLast() }
            } else if !trailHistory[i].isEmpty {
                trailHistory[i].removeLast()
            }
            for (k, tn) in trails[i].enumerated() {
                let idx = k * 2
                if idx < trailHistory[i].count {
                    tn.isHidden = false
                    tn.simdPosition = trailHistory[i][idx]
                    let f = 1 - Float(k) / Float(trails[i].count)
                    tn.simdScale = SIMD3(repeating: 0.5 + f)
                    tn.opacity = CGFloat(0.85 * f)
                } else {
                    tn.isHidden = true
                }
            }
        }
        if fire {
            if !showingFire { showingFire = true; ballMat.emission.contents = UIColor(hex: 0xff6a1f) }
            ballMat.emission.intensity = CGFloat(0.35 + 0.25 * sin(t * 12))
        } else if showingFire {
            setSkin(skin)
        }
        rimFlash = max(0, rimFlash - dt * 3)
        boardFlash = max(0, boardFlash - dt * 2.4)
        rimMat.emission.intensity = CGFloat(rimFlash * 1.2 + (fire ? 0.6 : 0))
        boardFrameMat.emission.intensity = CGFloat(1.4 + boardFlash * 2.5)
        net.update(t: t, dt: dt)
    }
}

// MARK: - Net

/// A tapered tube of cords under the rim. It swishes (a ripple running down) when the ball drops through and
/// rattles (a quick jiggle) when the rim is hit. Vertices are rebuilt only while it moves.
final class Net {
    let node = SCNNode()
    private let strands = 24
    private let rings = 7
    private var swishAmp: Float = 0
    private var swishPhase: Float = 0
    private var rattleAmp: Float = 0
    private var element: SCNGeometryElement!
    private var uvs: SCNGeometrySource!
    private let material = SCNMaterial()
    private var moving = true

    init() {
        material.lightingModel = .constant
        material.diffuse.contents = Textures.net()
        material.diffuse.wrapS = .repeat
        material.isDoubleSided = true
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        material.writesToDepthBuffer = false
        var tex: [SIMD2<Float>] = []
        var idx: [UInt16] = []
        for r in 0..<rings {
            for s in 0...strands {
                tex.append(SIMD2(Float(s) / Float(strands) * 2, Float(r) / Float(rings - 1)))
            }
        }
        let row = strands + 1
        for r in 0..<(rings - 1) {
            for s in 0..<strands {
                let a = UInt16(r * row + s), b = UInt16(r * row + s + 1), c = UInt16((r + 1) * row + s), d = UInt16((r + 1) * row + s + 1)
                idx += [a, c, b, b, c, d]
            }
        }
        uvs = SCNGeometrySource(data: Data(bytes: tex, count: tex.count * MemoryLayout<SIMD2<Float>>.stride), semantic: .texcoord,
                                vectorCount: tex.count, usesFloatComponents: true, componentsPerVector: 2, bytesPerComponent: 4,
                                dataOffset: 0, dataStride: MemoryLayout<SIMD2<Float>>.stride)
        element = SCNGeometryElement(indices: idx, primitiveType: .triangles)
        rebuild()
    }

    func swish(_ s: Float) { swishAmp = max(swishAmp, min(1, s)); swishPhase = 0; moving = true }
    func rattle(_ s: Float) { rattleAmp = max(rattleAmp, min(1, s)); moving = true }

    func update(t: Double, dt: Float) {
        guard moving else { return }
        swishPhase += dt * 9
        swishAmp = max(0, swishAmp - dt * 1.6)
        rattleAmp = max(0, rattleAmp - dt * 3.5)
        rebuild(t: Float(t))
        if swishAmp == 0 && rattleAmp == 0 { moving = false; rebuild() }
    }

    private func rebuild(t: Float = 0) {
        var verts: [SIMD3<Float>] = []
        let top = Arena.rimRadius - Arena.rimTube * 0.5
        for r in 0..<rings {
            let f = Float(r) / Float(rings - 1)
            var radius = top * (1 - 0.4 * f)
            var y = -Arena.netDepth * f
            // Swish: a bulge travelling down and a stretch.
            let wave = exp(-pow((f * 3 - swishPhase + 0.5), 2) * 2)
            radius += swishAmp * wave * 0.03
            y -= swishAmp * f * 0.035
            let jig = rattleAmp * sin(t * 55 + f * 4) * 0.012 * f
            for s in 0...strands {
                let a = Float(s) / Float(strands) * 2 * .pi
                verts.append(SIMD3(cos(a) * radius + jig, y, sin(a) * radius))
            }
        }
        let vs = SCNGeometrySource(vertices: verts.map { SCNVector3($0.x, $0.y, $0.z) })
        let g = SCNGeometry(sources: [vs, uvs], elements: [element])
        g.materials = [material]
        node.geometry = g
    }
}
