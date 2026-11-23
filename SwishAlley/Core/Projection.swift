import simd

/// A flat physical display rectangle in world space (metres): its lower-left corner and the full-length vectors
/// along its right and up edges, as seen by someone looking at it. The two halves of a folding display are two
/// surfaces; a normal display is one.
struct Surface: Equatable {
    var origin: SIMD3<Float>
    var right: SIMD3<Float>
    var up: SIMD3<Float>

    var width: Float { simd_length(right) }
    var height: Float { simd_length(up) }
    var vr: SIMD3<Float> { simd_normalize(right) }
    var vu: SIMD3<Float> { simd_normalize(up) }
    /// Unit normal pointing toward the viewer side.
    var normal: SIMD3<Float> { simd_normalize(simd_cross(right, up)) }

    /// The point at fractions (u across, v up) of the rectangle.
    func point(_ u: Float, _ v: Float) -> SIMD3<Float> { origin + right * u + up * v }

    /// Signed distance of a point in front of the surface plane (positive on the viewer side).
    func distance(_ p: SIMD3<Float>) -> Float { simd_dot(p - origin, normal) }

    /// Where the ray from `eye` through `p` meets the surface plane, as (u, v) fractions; nil if parallel.
    func hit(from eye: SIMD3<Float>, through p: SIMD3<Float>) -> SIMD2<Float>? {
        let dir = p - eye
        let denom = simd_dot(dir, normal)
        if abs(denom) < 1e-9 { return nil }
        let t = simd_dot(origin - eye, normal) / denom
        let q = eye + dir * t - origin
        return SIMD2(simd_dot(q, vr) / width, simd_dot(q, vu) / height)
    }
}

/// Off-axis (asymmetric frustum) projection for a viewer at `eye` looking through `surface`, after Kooima,
/// "Generalized Perspective Projection" (2008). The camera sits at the eye with its axes parallel to the surface,
/// so the rendered image fills the physical rectangle exactly and the virtual scene appears fixed in space.
struct OffAxis {
    /// Camera-to-world transform (columns: right, up, normal, eye). The camera looks along -normal.
    var cameraTransform: simd_float4x4
    /// OpenGL-style projection matrix (clip z in -1…1, w = -z_eye).
    var projection: simd_float4x4
    /// The eye actually used (pushed in front of the surface if it was behind or too close).
    var eye: SIMD3<Float>

    static let minDistance: Float = 0.05

    init(eye rawEye: SIMD3<Float>, surface s: Surface, near n: Float = 0.01, far f: Float = 4) {
        let vr = s.vr, vu = s.vu, vn = s.normal
        var eye = rawEye
        let d0 = s.distance(eye)
        if d0 < Self.minDistance { eye += vn * (Self.minDistance - d0) }
        let pa = s.origin, pb = s.origin + s.right, pc = s.origin + s.up
        let va = pa - eye, vb = pb - eye, vc = pc - eye
        let d = -simd_dot(va, vn)
        let l = simd_dot(vr, va) * n / d
        let r = simd_dot(vr, vb) * n / d
        let b = simd_dot(vu, va) * n / d
        let t = simd_dot(vu, vc) * n / d
        projection = OffAxis.frustum(l: l, r: r, b: b, t: t, n: n, f: f)
        cameraTransform = simd_float4x4(columns: (
            SIMD4(vr, 0), SIMD4(vu, 0), SIMD4(vn, 0), SIMD4(eye, 1)))
        self.eye = eye
    }

    static func frustum(l: Float, r: Float, b: Float, t: Float, n: Float, f: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(2 * n / (r - l), 0, 0, 0),
            SIMD4(0, 2 * n / (t - b), 0, 0),
            SIMD4((r + l) / (r - l), (t + b) / (t - b), -(f + n) / (f - n), -1),
            SIMD4(0, 0, -2 * f * n / (f - n), 0)))
    }

    /// Normalised device coordinates (x, y in -1…1 across the surface) of a world point.
    func ndc(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let view = cameraTransform.inverse
        let c = projection * (view * SIMD4(p, 1))
        return SIMD3(c.x, c.y, c.z) / c.w
    }
}

/// Converts on-screen points to metres. Apple does not publish a points-per-metre API; the pixel densities of
/// current devices are close enough that this table keeps the virtual scale within a few percent.
enum PhysicalScale {
    /// Points per metre for an idiom and native scale.
    static func pointsPerMetre(isPad: Bool, nativeScale: Float, isMini: Bool = false) -> Float {
        let ppi: Float = isPad ? (isMini ? 326 : 264) : 460
        return ppi / nativeScale / 0.0254
    }
}
