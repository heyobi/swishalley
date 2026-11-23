import simd

/// The arcade lane in its own frame ("arena units", the court is 1 wide): origin on the floor at the middle of
/// the base of the backboard, x to the shooter's right, y up (against gravity), z from the backboard toward the
/// shooter. On a half-open iPhone Duo the base of the backboard is the fold, so the floor ends exactly at the
/// crease and the rim hangs straight above it.
enum Arena {
    static let ballRadius: Float = 0.05
    static let rimRadius: Float = 0.09          // to the middle of the tube
    static let rimTube: Float = 0.008
    static let rimHeight: Float = 0.38
    static let boardHalfWidth: Float = 0.28
    static let boardBottom: Float = 0.26
    static let boardTop: Float = 0.58
    static let boardThickness: Float = 0.025
    /// Where the shooter's ball waits, measured from the base of the backboard.
    static let rackDistance: Float = 0.60
    /// Gravity in arena units per second squared (tuned for a ~0.7 s shot).
    static let gravity: Float = 3.5
    /// Launch elevation of a perfect shot from the usual distance; closer shots go up steeper.
    static let idealElevation: Float = 72 * .pi / 180
    static func elevation(distance d: Float) -> Float {
        idealElevation + max(0, 0.42 - d) * 40 * .pi / 180
    }
    /// Net length below the rim.
    static let netDepth: Float = 0.13

    /// Rim centre for a hoop shifted sideways by `slide`, with its back edge `back` from the backboard plane.
    /// The back of the tube touches the plane through the fold: `back` is the half-width of the crease strip.
    static func rimCenter(slide: Float = 0, back: Float = 0) -> SIMD3<Float> {
        SIMD3(slide, rimHeight, back + rimRadius + rimTube)
    }
}

/// A plane the ball must stay in front of (signed distance >= ball radius along `normal`).
struct Plane: Equatable {
    var point: SIMD3<Float>
    var normal: SIMD3<Float>
    func distance(_ p: SIMD3<Float>) -> Float { simd_dot(p - point, normal) }
}

/// Places one arena in the world (the frame the display surfaces live in): yaw about the vertical axis, then a
/// uniform scale, then a translation. World units are the same as arena units for the stage and the window.
struct Placement: Equatable {
    var origin = SIMD3<Float>(0, 0, 0)
    var yaw: Float = 0
    var scale: Float = 1

    var rotation: simd_quatf { simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) }

    func toWorld(_ p: SIMD3<Float>) -> SIMD3<Float> { origin + rotation.act(p * scale) }
    func toArena(_ p: SIMD3<Float>) -> SIMD3<Float> { rotation.inverse.act(p - origin) / scale }
    func directionToArena(_ d: SIMD3<Float>) -> SIMD3<Float> { rotation.inverse.act(d) }
    func directionToWorld(_ d: SIMD3<Float>) -> SIMD3<Float> { rotation.act(d) }
    func planeToArena(_ p: Plane) -> Plane { Plane(point: toArena(p.point), normal: simd_normalize(directionToArena(p.normal))) }

    var matrix: simd_float4x4 {
        let r = simd_float4x4(rotation)
        var m = r * simd_float4x4(diagonal: SIMD4(scale, scale, scale, 1))
        m.columns.3 = SIMD4(origin, 1)
        return m
    }
}

/// Projectile helpers for the arena.
enum Ballistics {
    /// Launch velocity that reaches `target` from `from` at elevation `theta` (radians; by default the ideal
    /// elevation for the distance) under gravity `g`,
    /// or nil if no such shot exists (target too high for that angle).
    static func launch(from: SIMD3<Float>, to target: SIMD3<Float>, theta fixed: Float? = nil, g: Float = Arena.gravity) -> SIMD3<Float>? {
        let dx = target.x - from.x, dz = target.z - from.z
        let d = (dx * dx + dz * dz).squareRoot()
        guard d > 1e-4 else { return nil }
        let theta = fixed ?? Arena.elevation(distance: d)
        let dh = target.y - from.y
        let c = cos(theta), t = tan(theta)
        let denom = 2 * c * c * (d * t - dh)
        guard denom > 1e-5 else { return nil }
        let v = (g * d * d / denom).squareRoot()
        let horizontal = v * c
        return SIMD3(dx / d * horizontal, v * sin(theta), dz / d * horizontal)
    }

    /// The perfect shot for this distance; under a glass ceiling (a duel lane) the arc is flattened just enough
    /// that its top clears the glass.
    static func idealLaunch(from: SIMD3<Float>, to target: SIMD3<Float>, ceiling: Float?) -> SIMD3<Float>? {
        let dx = target.x - from.x, dz = target.z - from.z
        var theta = Arena.elevation(distance: (dx * dx + dz * dz).squareRoot())
        var best = launch(from: from, to: target, theta: theta)
        guard let c = ceiling else { return best }
        let floor: Float = 55 * .pi / 180
        while let v = best, from.y + v.y * v.y / (2 * Arena.gravity) + Arena.ballRadius > c - 0.015, theta > floor {
            theta -= .pi / 360
            best = launch(from: from, to: target, theta: theta) ?? best
        }
        return best
    }

    /// Position after time `t` without collisions.
    static func position(_ p0: SIMD3<Float>, _ v0: SIMD3<Float>, t: Float, g: Float = Arena.gravity) -> SIMD3<Float> {
        p0 + v0 * t + SIMD3(0, -0.5 * g * t * t, 0)
    }
}
