import SceneKit
import UIKit
import simd

/// The Wild Toss objects and their debris, built from primitives (all original, nothing to license). Every object
/// fits the ball's size so the physics stays the same.
enum Props {
    static func mat(_ c: UIColor, rough: CGFloat = 0.55, metal: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = c
        m.roughness.contents = rough
        m.metalness.contents = metal
        return m
    }

    private static func add(_ g: SCNGeometry, _ m: SCNMaterial, to parent: SCNNode, at p: SIMD3<Float> = .zero,
                            scale: SIMD3<Float> = SIMD3(repeating: 1), euler: SIMD3<Float> = .zero) {
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.simdPosition = p
        n.simdScale = scale
        n.simdEulerAngles = euler
        parent.addChildNode(n)
    }

    static func make(_ kind: Projectile) -> SCNNode {
        let n = SCNNode()
        let r = CGFloat(Arena.ballRadius)
        switch kind {
        case .ball:
            break
        case .melon:
            let m = mat(.white, rough: 0.35)
            m.diffuse.contents = Textures.melon()
            let s = SCNSphere(radius: r); s.segmentCount = 32
            add(s, m, to: n, scale: SIMD3(1.28, 0.98, 0.98))
        case .duck:
            let yellow = mat(UIColor(hex: 0xffd23f), rough: 0.3)
            let body = SCNSphere(radius: r * 0.92); body.segmentCount = 28
            add(body, yellow, to: n, at: SIMD3(0, -0.006, 0), scale: SIMD3(1.15, 0.85, 1))
            let head = SCNSphere(radius: r * 0.55); head.segmentCount = 24
            add(head, yellow, to: n, at: SIMD3(0.018, 0.032, 0))
            add(SCNCone(topRadius: 0, bottomRadius: r * 0.22, height: r * 0.45), mat(UIColor(hex: 0xff7a1a), rough: 0.4), to: n,
                at: SIMD3(0.046, 0.03, 0), euler: SIMD3(0, 0, -.pi / 2))
            for z: Float in [-0.012, 0.012] {
                add(SCNSphere(radius: r * 0.08), mat(UIColor(hex: 0x111111), rough: 0.2), to: n, at: SIMD3(0.034, 0.042, z))
            }
            add(SCNSphere(radius: r * 0.35), yellow, to: n, at: SIMD3(-0.045, 0.004, 0), scale: SIMD3(1, 0.7, 0.6))
        case .toaster:
            let chrome = mat(UIColor(hex: 0xd9dde4), rough: 0.18, metal: 0.9)
            add(SCNBox(width: r * 1.8, height: r * 1.4, length: r * 1.15, chamferRadius: r * 0.3), chrome, to: n)
            let dark = mat(UIColor(hex: 0x1d1d22), rough: 0.6)
            for x: Float in [-0.017, 0.017] {
                add(SCNBox(width: r * 0.5, height: r * 0.06, length: r * 0.8, chamferRadius: 0.002), dark, to: n, at: SIMD3(x, Float(r) * 0.7, 0))
                add(SCNBox(width: r * 0.42, height: r * 0.3, length: r * 0.72, chamferRadius: 0.003), mat(UIColor(hex: 0xd99a4e), rough: 0.9), to: n,
                    at: SIMD3(x, Float(r) * 0.76, 0))
            }
            add(SCNBox(width: r * 0.15, height: r * 0.35, length: r * 0.12, chamferRadius: 0.002), dark, to: n, at: SIMD3(Float(r) * 0.92, 0, 0))
        case .pumpkin:
            let m = mat(.white, rough: 0.6)
            m.diffuse.contents = Textures.pumpkin()
            let s = SCNSphere(radius: r); s.segmentCount = 32
            add(s, m, to: n, scale: SIMD3(1.16, 0.88, 1.16))
            add(SCNCylinder(radius: r * 0.12, height: r * 0.45), mat(UIColor(hex: 0x5a7a2a), rough: 0.8), to: n,
                at: SIMD3(0.004, Float(r) * 0.95, 0), euler: SIMD3(0, 0, 0.25))
        }
        n.castsShadow = false
        return n
    }

    /// Pieces for a splat: (geometry, material) list.
    static func debris(_ kind: Projectile) -> [(SCNGeometry, SCNMaterial)] {
        var out: [(SCNGeometry, SCNMaterial)] = []
        switch kind {
        case .melon:
            let red = mat(UIColor(hex: 0xf0424f), rough: 0.5), rind = mat(UIColor(hex: 0x2f8a3a), rough: 0.5)
            let seed = mat(UIColor(hex: 0x1a1210), rough: 0.3)
            for k in 0..<9 { out.append((SCNBox(width: 0.028, height: 0.02, length: 0.022 + CGFloat(k % 3) * 0.006, chamferRadius: 0.004), red)) }
            for _ in 0..<5 { out.append((SCNBox(width: 0.03, height: 0.006, length: 0.018, chamferRadius: 0.002), rind)) }
            for _ in 0..<8 { out.append((SCNSphere(radius: 0.0035), seed)) }
        case .pumpkin:
            let flesh = mat(UIColor(hex: 0xf28a1d), rough: 0.6), pale = mat(UIColor(hex: 0xf6e3b0), rough: 0.5)
            for k in 0..<10 { out.append((SCNBox(width: 0.03, height: 0.018, length: 0.02 + CGFloat(k % 3) * 0.006, chamferRadius: 0.005), flesh)) }
            for _ in 0..<7 { out.append((SCNSphere(radius: 0.004), pale)) }
        default:
            break
        }
        return out
    }

    static func toast() -> (SCNGeometry, SCNMaterial) {
        (SCNBox(width: 0.04, height: 0.006, length: 0.036, chamferRadius: 0.004), mat(UIColor(hex: 0xd99a4e), rough: 0.9))
    }
}
