import SceneKit
import UIKit
import simd

/// Little rendered previews for the Locker: the real ball, object and arena, not a colour swatch. Rendered once
/// off screen with SceneKit and cached.
@MainActor
enum Thumbnails {
    private static var cache: [String: UIImage] = [:]
    private static let renderer: SCNRenderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)

    private static func lights(_ scene: SCNScene, ambient: CGFloat = 300) {
        let a = SCNLight(); a.type = .ambient; a.intensity = ambient
        let an = SCNNode(); an.light = a; scene.rootNode.addChildNode(an)
        let k = SCNLight(); k.type = .directional; k.intensity = 900; k.color = UIColor(hex: 0xfff1de)
        let kn = SCNNode(); kn.light = k; kn.simdEulerAngles = SIMD3(-0.7, 0.6, 0); scene.rootNode.addChildNode(kn)
        let r = SCNLight(); r.type = .directional; r.intensity = 400; r.color = UIColor(hex: 0x37e3ff)
        let rn = SCNNode(); rn.light = r; rn.simdEulerAngles = SIMD3(-0.2, -2.4, 0); scene.rootNode.addChildNode(rn)
    }

    private static func snap(_ scene: SCNScene, camera: SCNNode, size: CGSize) -> UIImage {
        renderer.scene = scene
        renderer.pointOfView = camera
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }

    private static func objectCamera(_ scene: SCNScene, distance: Float = 0.2) -> SCNNode {
        let c = SCNCamera()
        c.fieldOfView = 34
        c.zNear = 0.01
        c.zFar = 5
        let n = SCNNode()
        n.camera = c
        n.simdPosition = SIMD3(0, 0.05, distance)
        n.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(n)
        return n
    }

    static func ball(_ skin: BallSkin) -> UIImage {
        let key = "ball-\(skin.id)"
        if let i = cache[key] { return i }
        let scene = SCNScene()
        scene.background.contents = UIColor(hex: 0x1b1430)
        lights(scene)
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = Textures.ball(skin)
        m.roughness.contents = skin.metal > 0 ? 0.2 : 0.6
        m.metalness.contents = skin.metal
        if skin.glow { m.emission.contents = Textures.ball(skin); m.emission.intensity = 0.8 }
        let s = SCNSphere(radius: CGFloat(Arena.ballRadius)); s.segmentCount = 48; s.materials = [m]
        let n = SCNNode(geometry: s)
        n.simdEulerAngles = SIMD3(0.3, 0.6, 0.15)
        scene.rootNode.addChildNode(n)
        let img = snap(scene, camera: objectCamera(scene, distance: 0.19), size: CGSize(width: 180, height: 180))
        cache[key] = img
        return img
    }

    static func object(_ kind: Projectile) -> UIImage {
        let key = "obj-\(kind.rawValue)"
        if let i = cache[key] { return i }
        let scene = SCNScene()
        scene.background.contents = UIColor(hex: 0x1b1430)
        lights(scene)
        let n = Props.make(kind)
        n.simdEulerAngles = SIMD3(0.15, -0.7, 0)
        scene.rootNode.addChildNode(n)
        let img = snap(scene, camera: objectCamera(scene, distance: 0.21), size: CGSize(width: 180, height: 180))
        cache[key] = img
        return img
    }

    /// The arena as a small window into its lane, seen the way the game shows it.
    static func arena(_ theme: ArenaTheme) -> UIImage {
        let key = "arena-\(theme.id)"
        if let i = cache[key] { return i }
        let scene = SCNScene()
        scene.background.contents = UIColor(hex: theme.wall)
        let a = SCNLight(); a.type = .ambient; a.intensity = theme.ambient
        let an = SCNNode(); an.light = a; scene.rootNode.addChildNode(an)
        let k = SCNLight(); k.type = .directional; k.intensity = 650; k.color = UIColor(hex: 0xfff1de)
        let kn = SCNNode(); kn.light = k; kn.simdEulerAngles = SIMD3(-1.05, 0.35, 0); scene.rootNode.addChildNode(kn)
        let size = CGSize(width: 320, height: 240)
        let ppm = PhysicalScale.pointsPerMetre(isPad: false, nativeScale: 3)
        let (vp, slot, _, _) = Layout.windowLane(rect: CGRect(origin: .zero, size: size), ppm: ppm)
        let nodes = ArenaNodes(slot: slot, theme: theme, skin: BallSkin.spec("classic"))
        nodes.update(lane: Lane(slot: slot), fire: false, t: 0, dt: 0)
        scene.rootNode.addChildNode(nodes.root)
        let cam = SCNCamera()
        cam.automaticallyAdjustsZRange = false
        cam.zNear = 0.01
        cam.zFar = 40
        let o = OffAxis(eye: slot.eye, surface: vp.surface, near: 0.01, far: 40)
        cam.projectionTransform = SCNMatrix4(o.projection)
        let cn = SCNNode()
        cn.camera = cam
        cn.simdTransform = o.cameraTransform
        scene.rootNode.addChildNode(cn)
        let img = snap(scene, camera: cn, size: size)
        cache[key] = img
        return img
    }
}
