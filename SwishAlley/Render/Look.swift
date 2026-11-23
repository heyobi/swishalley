import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
}

/// An arena's look. All original: warm arcade-cabinet wood and a neon-lit gym.
struct ArenaTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let free: Bool
    let floorLight: UInt32
    let floorDark: UInt32
    let lines: UInt32
    let wall: UInt32
    let wallAccent: UInt32
    let neonA: UInt32
    let neonB: UInt32
    let boardFrame: UInt32
    let rim: UInt32
    let ambient: CGFloat
    let sign: String

    static let all: [ArenaTheme] = [
        ArenaTheme(id: "gym", name: "Neon Gym", free: true, floorLight: 0xd99a5b, floorDark: 0xb87538, lines: 0xfff3d6,
                   wall: 0x1b1430, wallAccent: 0x2a1d48, neonA: 0xff3fa4, neonB: 0x37e3ff, boardFrame: 0xff3fa4, rim: 0xff6a1f,
                   ambient: 260, sign: "SWISH ALLEY"),
        ArenaTheme(id: "cabinet", name: "Retro Cabinet", free: false, floorLight: 0x8a4b2a, floorDark: 0x6b3519, lines: 0xffd36b,
                   wall: 0x2b1408, wallAccent: 0x3d1e0c, neonA: 0xffb21f, neonB: 0x2ee6b8, boardFrame: 0xffb21f, rim: 0xff5a1a,
                   ambient: 280, sign: "HI-SCORE"),
        ArenaTheme(id: "rooftop", name: "Rooftop Dusk", free: false, floorLight: 0x5a6378, floorDark: 0x434a5c, lines: 0xffe9c2,
                   wall: 0x2d1d3f, wallAccent: 0xff8a5c, neonA: 0xff8a5c, neonB: 0x8e7dff, boardFrame: 0xfff0d8, rim: 0xff5c2b,
                   ambient: 320, sign: "DUSK LEAGUE"),
        ArenaTheme(id: "pier", name: "Midnight Pier", free: false, floorLight: 0x2c4a5e, floorDark: 0x1f3646, lines: 0x9ff5ff,
                   wall: 0x07121c, wallAccent: 0x0e2233, neonA: 0x3dffd0, neonB: 0xff4f81, boardFrame: 0x3dffd0, rim: 0xff4f81,
                   ambient: 220, sign: "NIGHT RUN"),
    ]

    static func spec(_ id: String) -> ArenaTheme { all.first { $0.id == id } ?? all[0] }
}

/// A ball's look.
struct BallSkin: Identifiable, Equatable {
    let id: String
    let name: String
    let free: Bool
    let base: UInt32
    let seams: UInt32
    let stripe: UInt32?
    let glow: Bool
    let metal: CGFloat

    static let all: [BallSkin] = [
        BallSkin(id: "classic", name: "Classic", free: true, base: 0xe8701e, seams: 0x1a0d06, stripe: nil, glow: false, metal: 0),
        BallSkin(id: "retro", name: "Retro Stripe", free: false, base: 0xf4efe4, seams: 0x1c1c28, stripe: 0xe23b3b, glow: false, metal: 0),
        BallSkin(id: "glow", name: "Glow Orb", free: false, base: 0x37e3ff, seams: 0x0a2a44, stripe: nil, glow: true, metal: 0),
        BallSkin(id: "chrome", name: "Chrome", free: false, base: 0xd8dde6, seams: 0x3a3f4a, stripe: nil, glow: false, metal: 0.9),
        BallSkin(id: "sunset", name: "Sunset", free: false, base: 0xff7a59, seams: 0x40124a, stripe: 0xffc94a, glow: false, metal: 0),
    ]

    static func spec(_ id: String) -> BallSkin { all.first { $0.id == id } ?? all[0] }
}

/// Textures drawn on the device with Core Graphics (nothing to license).
enum Textures {
    private static var cache: [String: UIImage] = [:]

    private static func cached(_ key: String, _ make: () -> UIImage) -> UIImage {
        if let i = cache[key] { return i }
        let i = make()
        cache[key] = i
        return i
    }

    private static func render(_ size: CGSize, opaque: Bool = true, _ draw: (CGContext) -> Void) -> UIImage {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: f).image { draw($0.cgContext) }
    }

    /// Hardwood planks across the lane with lane lines, a key and a free-throw arc. The image covers the floor
    /// from z = -1 (behind the board) to z = 1.3; `v` runs along z.
    static func floor(_ t: ArenaTheme) -> UIImage {
        cached("floor-\(t.id)") {
            render(CGSize(width: 512, height: 1152)) { c in
                let w: CGFloat = 512, h: CGFloat = 1152
                var rng = SplitMix(seed: 7)
                let planks = 16
                let pw = w / CGFloat(planks)
                for i in 0..<planks {
                    var y: CGFloat = -CGFloat(rng.next() % 300)
                    while y < h {
                        let len = CGFloat(180 + rng.next() % 260)
                        let mix = CGFloat(rng.next() % 1000) / 1000
                        let col = blend(t.floorLight, t.floorDark, mix * 0.8)
                        c.setFillColor(col.cgColor)
                        c.fill(CGRect(x: CGFloat(i) * pw, y: y, width: pw, height: len))
                        // grain
                        c.setStrokeColor(UIColor(white: 0, alpha: 0.07).cgColor)
                        c.setLineWidth(1)
                        for _ in 0..<3 {
                            let gx = CGFloat(i) * pw + CGFloat(rng.next() % UInt64(pw))
                            c.move(to: CGPoint(x: gx, y: y)); c.addLine(to: CGPoint(x: gx + 2, y: y + len)); c.strokePath()
                        }
                        c.setFillColor(UIColor(white: 0, alpha: 0.28).cgColor)
                        c.fill(CGRect(x: CGFloat(i) * pw, y: y + len - 1.5, width: pw, height: 1.5))
                        y += len
                    }
                    c.setFillColor(UIColor(white: 0, alpha: 0.25).cgColor)
                    c.fill(CGRect(x: CGFloat(i) * pw, y: 0, width: 1.2, height: h))
                }
                // z → image y: z = -1 at 0, z = 1.3 at h.
                func Y(_ z: CGFloat) -> CGFloat { (z + 1) / 2.3 * h }
                func X(_ x: CGFloat) -> CGFloat { (x + 0.5) * w }
                let line = UIColor(hex: t.lines, alpha: 0.85)
                c.setStrokeColor(line.cgColor)
                c.setLineWidth(6)
                // Key (paint) in front of the board and the free-throw circle.
                let key = CGRect(x: X(-0.2), y: Y(0), width: X(0.2) - X(-0.2), height: Y(0.42) - Y(0))
                c.setFillColor(UIColor(hex: t.neonA, alpha: 0.18).cgColor)
                c.fill(key)
                c.stroke(key)
                c.strokeEllipse(in: CGRect(x: X(-0.2), y: Y(0.42) - (Y(0.62) - Y(0.42)) / 2 - 0, width: X(0.2) - X(-0.2), height: Y(0.62) - Y(0.42)))
                // Three-point style arc.
                c.addArc(center: CGPoint(x: X(0), y: Y(0.06)), radius: (Y(0.72) - Y(0.06)), startAngle: 0.15, endAngle: .pi - 0.15, clockwise: false)
                c.strokePath()
                // Side lines.
                c.setLineWidth(8)
                c.stroke(CGRect(x: X(-0.48), y: Y(-0.98), width: X(0.48) - X(-0.48), height: Y(1.28) - Y(-0.98)))
                // Varnish sheen.
                let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor(white: 1, alpha: 0.10).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
                c.drawLinearGradient(g, start: CGPoint(x: w / 2, y: Y(0)), end: CGPoint(x: w / 2, y: Y(0.9)), options: [])
            }
        }
    }

    /// The gym wall: dark tiles with a glowing sign. Pure decoration behind the backboard.
    static func wall(_ t: ArenaTheme) -> UIImage {
        cached("wall-\(t.id)") {
            render(CGSize(width: 1024, height: 512)) { c in
                let w: CGFloat = 1024, h: CGFloat = 512
                c.setFillColor(UIColor(hex: t.wall).cgColor)
                c.fill(CGRect(x: 0, y: 0, width: w, height: h))
                // Cinder blocks.
                c.setStrokeColor(UIColor(hex: t.wallAccent).cgColor)
                c.setLineWidth(3)
                let bh: CGFloat = 32, bw: CGFloat = 96
                var row = 0
                var y: CGFloat = 0
                while y < h {
                    c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: w, y: y)); c.strokePath()
                    var x: CGFloat = row % 2 == 0 ? 0 : bw / 2
                    while x < w {
                        c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: x, y: y + bh)); c.strokePath()
                        x += bw
                    }
                    y += bh; row += 1
                }
                // Two neon stripes.
                for (yy, col) in [(h * 0.86, t.neonB), (h * 0.9, t.neonA)] {
                    c.setFillColor(UIColor(hex: col).cgColor)
                    c.fill(CGRect(x: 0, y: yy, width: w, height: 6))
                }
            }
        }
    }

    /// Neon tube lettering on transparent background (used with an additive, emissive material).
    static func sign(_ text: String, color: UInt32) -> UIImage {
        cached("sign-\(text)-\(color)") {
            render(CGSize(width: 1024, height: 256), opaque: false) { c in
                let font = UIFont.systemFont(ofSize: 150, weight: .heavy).withRounded()
                let para = NSMutableParagraphStyle(); para.alignment = .center
                let col = UIColor(hex: color)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: para, .kern: 6]
                let rect = CGRect(x: 0, y: 40, width: 1024, height: 200)
                c.setShadow(offset: .zero, blur: 28, color: col.cgColor)
                for _ in 0..<3 { (text as NSString).draw(in: rect, withAttributes: attrs) }
                let inner: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: col.withAlphaComponent(0.6), .paragraphStyle: para, .kern: 6]
                (text as NSString).draw(in: rect, withAttributes: inner)
            }
        }
    }

    /// Backboard glass print: a frame and the shooter's square.
    static func board(_ t: ArenaTheme) -> UIImage {
        cached("board-\(t.id)") {
            render(CGSize(width: 512, height: 296), opaque: false) { c in
                let w: CGFloat = 512, h: CGFloat = 296
                c.setFillColor(UIColor(white: 1, alpha: 0.10).cgColor)
                c.fill(CGRect(x: 0, y: 0, width: w, height: h))
                c.setStrokeColor(UIColor.white.cgColor)
                c.setLineWidth(14)
                c.stroke(CGRect(x: 7, y: 7, width: w - 14, height: h - 14))
                c.setLineWidth(10)
                // Square above the rim (rim at y=0.38 of a board spanning 0.26…0.58).
                let rimY = (0.58 - 0.38) / 0.32 * h
                c.stroke(CGRect(x: w * 0.36, y: rimY - h * 0.38, width: w * 0.28, height: h * 0.38))
            }
        }
    }

    /// Net cords: a diamond lattice on transparent background, wrapping around the net tube.
    static func net() -> UIImage {
        cached("net") {
            render(CGSize(width: 512, height: 128), opaque: false) { c in
                c.setStrokeColor(UIColor.white.cgColor)
                c.setLineWidth(5)
                c.setLineCap(.round)
                let n = 12
                let cw: CGFloat = 512 / CGFloat(n)
                for i in 0...n {
                    let x = CGFloat(i) * cw
                    for k in 0..<2 {
                        let y0 = CGFloat(k) * 64
                        c.move(to: CGPoint(x: x, y: y0)); c.addLine(to: CGPoint(x: x + cw / 2, y: y0 + 64)); c.strokePath()
                        c.move(to: CGPoint(x: x, y: y0)); c.addLine(to: CGPoint(x: x - cw / 2, y: y0 + 64)); c.strokePath()
                    }
                }
                c.setLineWidth(7)
                c.move(to: CGPoint(x: 0, y: 3)); c.addLine(to: CGPoint(x: 512, y: 3)); c.strokePath()
            }
        }
    }

    /// Equirectangular ball skin: pebbled leather and the classic seams.
    static func ball(_ s: BallSkin) -> UIImage {
        cached("ball-\(s.id)") {
            render(CGSize(width: 512, height: 256)) { c in
                let w: CGFloat = 512, h: CGFloat = 256
                c.setFillColor(UIColor(hex: s.base).cgColor)
                c.fill(CGRect(x: 0, y: 0, width: w, height: h))
                var rng = SplitMix(seed: 3)
                for _ in 0..<2600 {
                    let x = CGFloat(rng.next() % 512), y = CGFloat(rng.next() % 256)
                    c.setFillColor(UIColor(white: rng.next() % 2 == 0 ? 0 : 1, alpha: 0.06).cgColor)
                    c.fillEllipse(in: CGRect(x: x, y: y, width: 3, height: 3))
                }
                if let st = s.stripe {
                    c.setFillColor(UIColor(hex: st).cgColor)
                    c.fill(CGRect(x: 0, y: h * 0.3, width: w, height: h * 0.12))
                    c.fill(CGRect(x: 0, y: h * 0.58, width: w, height: h * 0.12))
                }
                c.setStrokeColor(UIColor(hex: s.seams).cgColor)
                c.setLineWidth(7)
                c.move(to: CGPoint(x: 0, y: h / 2)); c.addLine(to: CGPoint(x: w, y: h / 2)); c.strokePath()
                for x in [w * 0.25, w * 0.75] {
                    c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x, y: h)); c.strokePath()
                }
                for sign: CGFloat in [-1, 1] {
                    c.move(to: CGPoint(x: 0, y: h / 2 + sign * h * 0.33))
                    for i in 1...64 {
                        let u = CGFloat(i) / 64
                        c.addLine(to: CGPoint(x: u * w, y: h / 2 + sign * h * 0.33 * cos(u * 2 * .pi)))
                    }
                    c.strokePath()
                }
            }
        }
    }

    /// Soft round shadow.
    static func blob() -> UIImage {
        cached("blob") {
            render(CGSize(width: 128, height: 128), opaque: false) { c in
                let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                   colors: [UIColor(white: 0, alpha: 0.7).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
                c.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
            }
        }
    }

    /// A soft glow dot for sparks and the fire trail.
    static func glowDot() -> UIImage {
        cached("glowdot") {
            render(CGSize(width: 64, height: 64), opaque: false) { c in
                let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                   colors: [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
                c.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
            }
        }
    }

    static func blend(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> UIColor {
        let ca = UIColor(hex: a), cb = UIColor(hex: b)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        ca.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        cb.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
    }
}

/// Small deterministic random numbers for textures.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension UIFont {
    func withRounded() -> UIFont {
        guard let d = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: d, size: pointSize)
    }
}
