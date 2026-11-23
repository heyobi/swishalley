import CoreGraphics
import simd

struct TouchSample: Equatable {
    var t: Double
    var p: CGPoint
}

/// Turns a finger flick on the glass into a shot. The direction is where the flick points on the lane's floor
/// (found by casting rays from the viewer's eye through the touched glass, so it is right on a tilted window, the
/// floor half of a half-open Duo and an opponent's upside-down half alike). The speed of the flick, in real
/// metres per second, sets the power: the same flick feels the same on an iPhone, an iPad and an iPhone Duo.
enum Flick {
    /// Flick speed that gives a perfectly judged shot.
    static let referenceSpeed: Float = 0.42
    /// Slower than this is not a shot.
    static let minimumSpeed: Float = 0.12
    /// Help with near misses (0 = none, 1 = every shot perfect).
    static let assist: Float = 0.55
    static let speedWindow: Float = 0.09
    static let angleWindow: Float = 7 * .pi / 180

    /// Finger velocity (points per second) over the last ~80 ms.
    static func velocity(_ samples: [TouchSample]) -> CGVector? {
        guard let last = samples.last else { return nil }
        let recent = samples.filter { last.t - $0.t <= 0.085 }
        guard let first = recent.first, last.t - first.t > 0.008 else {
            guard samples.count >= 2 else { return nil }
            let a = samples[samples.count - 2]
            let dt = max(last.t - a.t, 0.008)
            return CGVector(dx: (last.p.x - a.p.x) / dt, dy: (last.p.y - a.p.y) / dt)
        }
        let dt = last.t - first.t
        return CGVector(dx: (last.p.x - first.p.x) / dt, dy: (last.p.y - first.p.y) / dt)
    }

    /// The world point on the glass under a window point.
    static func glassPoint(_ p: CGPoint, in vp: Viewport) -> SIMD3<Float> {
        let u = Float((p.x - vp.rect.minX) / max(vp.rect.width, 1))
        let v = Float(1 - (p.y - vp.rect.minY) / max(vp.rect.height, 1))
        return vp.surface.point(u, v)
    }

    /// Where the sight line through a window point meets the horizontal plane `height` (arena units) of a lane.
    static func lanePoint(_ p: CGPoint, in vp: Viewport, eye: SIMD3<Float>, placement: Placement, height: Float) -> SIMD3<Float>? {
        let e = placement.toArena(eye)
        let q = placement.toArena(glassPoint(p, in: vp))
        let d = q - e
        guard abs(d.y) > 1e-6 else { return nil }
        let t = (height - e.y) / d.y
        guard t > 0 else { return nil }
        return e + d * t
    }

    struct Shot: Equatable {
        var velocity: SIMD3<Float>
        /// Flick speed relative to a perfect one.
        var power: Float
    }

    /// The shot for a flick released at `release` with finger velocity `velocity` (points per second).
    static func shot(release: CGPoint, velocity: CGVector, viewport vp: Viewport, eye: SIMD3<Float>, placement: Placement,
                     from launch: SIMD3<Float>, target: SIMD3<Float>, ceiling: Float? = nil, pointsPerMetre: Float, assist: Float = Flick.assist) -> Shot? {
        let speedPts = Float((velocity.dx * velocity.dx + velocity.dy * velocity.dy).squareRoot())
        let speed = speedPts / pointsPerMetre
        guard speed >= minimumSpeed else { return nil }
        let lead: CGFloat = 0.06
        let start = CGPoint(x: release.x - velocity.dx * lead, y: release.y - velocity.dy * lead)
        guard let a = lanePoint(start, in: vp, eye: eye, placement: placement, height: launch.y),
              let b = lanePoint(release, in: vp, eye: eye, placement: placement, height: launch.y) else { return nil }
        var dir = SIMD2<Float>(b.x - a.x, b.z - a.z)
        guard simd_length(dir) > 1e-5 else { return nil }
        dir = simd_normalize(dir)
        guard dir.y < -0.2 else { return nil }          // must point toward the hoop (−z)
        guard let ideal = Ballistics.idealLaunch(from: launch, to: target, ceiling: ceiling) else { return nil }
        let idealDir = simd_normalize(SIMD2(ideal.x, ideal.z))
        var err = atan2(idealDir.x * dir.y - idealDir.y * dir.x, simd_dot(dir, idealDir))   // angle from the ideal line to the flick
        if abs(err) < angleWindow { err *= 1 - assist }
        let power = speed / referenceSpeed
        var factor = 1 + (power - 1) * 0.55
        if abs(factor - 1) < speedWindow { factor = 1 + (factor - 1) * (1 - assist) }
        factor = max(0.45, min(1.6, factor))
        let ca = cos(err), sa = sin(err)
        let rotated = SIMD2(idealDir.x * ca - idealDir.y * sa, idealDir.x * sa + idealDir.y * ca)
        let horizontal = simd_length(SIMD2(ideal.x, ideal.z)) * factor
        let v = SIMD3(rotated.x * horizontal, ideal.y * factor, rotated.y * horizontal)
        return Shot(velocity: v, power: power)
    }
}
