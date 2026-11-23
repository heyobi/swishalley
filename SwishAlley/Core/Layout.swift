import CoreGraphics
import simd

/// How the game is shown right now.
enum Presentation: String, Equatable {
    /// Half-open iPhone Duo (or opened flat with the fold across the window): the upper half shows the backboard,
    /// the lower half is the floor, both drawn as windows onto one 3-D lane fixed in the room.
    case stage
    /// One flat screen (any iPhone or iPad, the iPhone Duo outer display, or one half of a Duo held like a book):
    /// a window into an arcade lane behind the glass.
    case window
    /// Two players face to face across a phone lying flat: each half is its own lane sunk below the glass, and
    /// the two backboards meet on the fold.
    case duel
}

struct Insets: Equatable {
    var top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0
}

/// Everything the layout depends on. All rectangles are in the window's points.
struct LayoutInput: Equatable {
    var size: CGSize
    /// The division reserved region (iPhone Duo inner display), in window points.
    var fold: CGRect?
    /// Hinge angle between the halves in degrees (180 = flat), nil without a hinge.
    var hinge: Double?
    var closed = false
    var duel = false
    var isPad = false
    var nativeScale: CGFloat = 3
    var insets = Insets()
}

/// One scene view: a rectangle of the window, the physical glass it covers (world units) and the lane it shows.
struct Viewport: Equatable {
    var rect: CGRect
    var surface: Surface
    var arena: Int
}

/// One lane in the world and the physical facts the ball has to respect.
struct ArenaSlot: Equatable {
    var placement: Placement
    /// Side walls at ±halfWidth (arena units).
    var halfWidth: Float
    /// Floor from the base of the backboard to the shooter's end (arena units).
    var depth: Float
    /// Half the width of the fold strip in arena units; the rim's back edge sits this far from the board plane,
    /// i.e. exactly above the edge of the crease.
    var crease: Float
    /// Glass the ball cannot pass (arena units): the upright half of a half-open Duo, the screen in front of a
    /// window lane, the glass over a sunken duel lane.
    var walls: [Plane]
    /// Where we assume the viewer's eyes are when nothing tracks them (world units).
    var eye: SIMD3<Float>
    var player: Int
    var sunken: Bool
    /// How far the backboard stands in front of the fold. Zero at 90° and wider: the board stands exactly on the
    /// fold. Below 90° the upright half leans over the floor, so the hoop comes forward just enough to stay in
    /// front of the glass.
    var setback: Float = 0
}

/// Where 2-D interface goes. Nothing is ever placed over the crease (`noGo`).
struct HUDPanel: Equatable {
    var rect: CGRect
    /// Degrees to rotate the panel's content so its player reads it upright.
    var rotation: Double
    var player: Int
}

struct HUDLayout: Equatable {
    var panels: [HUDPanel]
    /// Menus, cards and results.
    var menu: CGRect
    /// A second fold-free area for the title and banners (the upper half on the stage), if any.
    var banner: CGRect?
    /// Touch areas that shoot, one per arena.
    var shootZones: [CGRect]
    /// The crease with its safety margin.
    var noGo: CGRect?
}

struct SceneLayout: Equatable {
    var presentation: Presentation
    var viewports: [Viewport]
    var arenas: [ArenaSlot]
    /// Window points per world unit on the glass.
    var pointsPerUnit: Float
    var metresPerUnit: Float
    var pointsPerMetre: Float
    /// Hinge angle the surfaces were built with (degrees).
    var hinge: Float
    var hud: HUDLayout
}

enum Layout {
    /// Clearance kept between any interface and the crease, in points.
    static let foldMargin: CGFloat = 22
    static let panelHeight: CGFloat = 64
    /// Nominal viewer for a phone on a table: 21 cm up, 36 cm in front of the fold.
    static let stageEye = SIMD3<Float>(0, 0.21, 0.36)
    static let viewingDistance: Float = 0.32
    /// Window lane: how far the glass leans back toward the hoop, and where it meets the floor.
    static let windowTilt: Float = 35 * .pi / 180
    static let windowNearZ: Float = 1.0
    /// Fraction of the window height where the rim should appear.
    static let windowRimTarget: Float = 0.56
    /// Duel lanes are smaller and sunk so the top of each backboard is flush with the glass on the fold.
    static let duelScale: Float = 0.7
    static let duelEyeHeight: Float = 0.45
    static let duelEyeBack: Float = 0.12

    static func make(_ input: LayoutInput) -> SceneLayout? {
        guard input.size.width > 20, input.size.height > 20 else { return nil }
        let ppm = PhysicalScale.pointsPerMetre(isPad: input.isPad, nativeScale: Float(input.nativeScale))
        let fold = usableFold(input)
        if input.duel { return duel(input, fold: fold, ppm: ppm) }
        if let f = fold, f.width >= f.height { return stage(input, fold: f, ppm: ppm) }
        if let f = fold { return cabinet(input, fold: f, ppm: ppm) }
        return window(input, ppm: ppm)
    }

    /// The fold counts only on the open inner display and when it runs edge to edge with screen on both sides.
    static func usableFold(_ input: LayoutInput) -> CGRect? {
        guard let f = input.fold, !input.closed, f.width > 0 || f.height > 0 else { return nil }
        if f.width >= f.height {
            guard f.minY > 80, input.size.height - f.maxY > 80 else { return nil }
        } else {
            guard f.minX > 80, input.size.width - f.maxX > 80 else { return nil }
        }
        return f
    }

    /// The crease grown by the margin, spanning the window across.
    static func noGo(_ f: CGRect, size: CGSize) -> CGRect {
        if f.width >= f.height {
            return CGRect(x: 0, y: f.minY - foldMargin, width: size.width, height: f.height + 2 * foldMargin)
        }
        return CGRect(x: f.minX - foldMargin, y: 0, width: f.width + 2 * foldMargin, height: size.height)
    }

    static func safeRect(_ input: LayoutInput) -> CGRect {
        let i = input.insets
        return CGRect(x: i.left, y: i.top, width: input.size.width - i.left - i.right, height: input.size.height - i.top - i.bottom)
    }

    // MARK: Stage (half-open iPhone Duo, fold across)

    static func stage(_ input: LayoutInput, fold f: CGRect, ppm: Float) -> SceneLayout {
        let W = Float(input.size.width), H = Float(input.size.height)
        let ppu = W                                  // the court spans the window: 1 unit = window width
        let s = W / ppm                              // metres per unit
        let angle = Float(min(max(input.hinge ?? 110, 10), 180))
        let upH = Float(f.minY) / ppu, loH = (H - Float(f.maxY)) / ppu
        let gap = Float(f.height) / 2 / ppu
        let (upper, lower) = stageSurfaces(hingeDegrees: angle, upperHeight: upH, lowerHeight: loH, gap: gap)
        let upperRect = CGRect(x: 0, y: 0, width: input.size.width, height: f.minY)
        let lowerRect = CGRect(x: 0, y: f.maxY, width: input.size.width, height: input.size.height - f.maxY)
        let slot = ArenaSlot(placement: Placement(), halfWidth: 0.5, depth: gap + loH, crease: gap,
                             walls: [Plane(point: upper.origin, normal: upper.normal)],
                             eye: stageEye / s, player: 0, sunken: false,
                             setback: boardSetback(hingeDegrees: angle, gap: gap))
        let hud = stageHUD(input, fold: f, upper: upperRect, lower: lowerRect)
        return SceneLayout(presentation: .stage,
                           viewports: [Viewport(rect: upperRect, surface: upper, arena: 0),
                                       Viewport(rect: lowerRect, surface: lower, arena: 0)],
                           arenas: [slot], pointsPerUnit: ppu, metresPerUnit: s, pointsPerMetre: ppm, hinge: angle, hud: hud)
    }

    /// Direction from the fold along the upper half for a hinge angle between the halves (180 = flat).
    static func upperDirection(hingeDegrees: Float) -> SIMD3<Float> {
        let a = hingeDegrees * .pi / 180
        return SIMD3(0, sin(a), cos(a))
    }

    /// The two halves of a half-open Duo in the arena frame (court 1 wide). The lower half lies on the table
    /// (y = 0) from the crease toward the viewer; the upper half rises from the fold at the hinge angle. Each
    /// surface's origin is the bottom-left corner of its view as the viewer reads it.
    static func stageSurfaces(hingeDegrees: Float, upperHeight: Float, lowerHeight: Float, gap: Float) -> (upper: Surface, lower: Surface) {
        let u = upperDirection(hingeDegrees: hingeDegrees)
        let upper = Surface(origin: SIMD3(-0.5, 0, 0) + u * gap, right: SIMD3(1, 0, 0), up: u * upperHeight)
        let lower = Surface(origin: SIMD3(-0.5, 0, gap + lowerHeight), right: SIMD3(1, 0, 0), up: SIMD3(0, 0, -lowerHeight))
        return (upper, lower)
    }

    /// Distance the hoop assembly has to come forward so the top of the backboard clears the leaning glass.
    static func boardSetback(hingeDegrees: Float, gap: Float) -> Float {
        guard hingeDegrees < 90 else { return 0 }
        let a = hingeDegrees * .pi / 180
        let top = Arena.boardTop + 0.03
        // The glass passes height y at z = y·cot(angle).
        return max(0, top * cos(a) / max(sin(a), 0.2))
    }

    static func stageHUD(_ input: LayoutInput, fold f: CGRect, upper: CGRect, lower: CGRect) -> HUDLayout {
        let safe = safeRect(input)
        let ng = noGo(f, size: input.size)
        let upperFree = upper.intersection(safe).divided(atDistance: max(0, upper.maxY - ng.minY), from: .maxYEdge).remainder
        let lowerFree = lower.intersection(safe).divided(atDistance: max(0, ng.maxY - lower.minY), from: .minYEdge).remainder
        // Score and clock along the top of the upright half, well clear of the crease.
        var panelArea = upperFree.insetBy(dx: 16, dy: 0)
        panelArea.origin.y += 10
        panelArea.size.height = min(panelHeight, max(0, upperFree.height - 10))
        var panels = [HUDPanel(rect: panelArea, rotation: 0, player: 0)]
        if panelArea.height < 44 {
            // Very short upper half: put the panel at the bottom of the floor half instead.
            panels = [HUDPanel(rect: CGRect(x: lowerFree.minX + 16, y: lowerFree.maxY - panelHeight - 8,
                                            width: lowerFree.width - 32, height: panelHeight), rotation: 0, player: 0)]
        }
        return HUDLayout(panels: panels, menu: lowerFree.insetBy(dx: 12, dy: 8), banner: upperFree.insetBy(dx: 12, dy: 8),
                         shootZones: [lowerFree], noGo: ng)
    }

    // MARK: Window (one flat screen)

    static func window(_ input: LayoutInput, ppm: Float) -> SceneLayout {
        let rect = CGRect(origin: .zero, size: input.size)
        let (vp, slot, ppu, s) = windowLane(rect: rect, ppm: ppm)
        let safe = safeRect(input)
        var panel = safe.insetBy(dx: 16, dy: 0)
        panel.origin.y += 8
        panel.size.height = panelHeight
        let zoneTop = max(safe.minY, input.size.height * 0.3)
        let zone = CGRect(x: safe.minX, y: zoneTop, width: safe.width, height: safe.maxY - zoneTop)
        let hud = HUDLayout(panels: [HUDPanel(rect: panel, rotation: 0, player: 0)], menu: safe.insetBy(dx: 12, dy: 12),
                            banner: nil, shootZones: [zone], noGo: nil)
        return SceneLayout(presentation: .window, viewports: [vp], arenas: [slot], pointsPerUnit: ppu, metresPerUnit: s,
                           pointsPerMetre: ppm, hinge: 180, hud: hud)
    }

    /// A lane behind a flat rectangle of glass. The glass leans back toward the hoop (as if you look down the
    /// lane), meets the floor at the near end and is shifted so the rim lands at the same height on every screen.
    static func windowLane(rect: CGRect, ppm: Float) -> (Viewport, ArenaSlot, Float, Float) {
        let wm = Float(rect.width) / ppm, hm = Float(rect.height) / ppm
        let s = min(wm, hm * 0.62)                   // metres per unit: the lane fits the narrow way
        let wu = wm / s, hu = hm / s
        let b = windowTilt
        let up = SIMD3<Float>(0, cos(b), -sin(b))
        let n = SIMD3<Float>(0, sin(b), cos(b))
        let edge = SIMD3<Float>(0, 0, windowNearZ)
        let distance = viewingDistance / s
        func make(_ yoff: Float) -> (Surface, SIMD3<Float>) {
            let bottom = edge - up * hu * yoff
            let surface = Surface(origin: bottom - SIMD3(wu / 2, 0, 0), right: SIMD3(wu, 0, 0), up: up * hu)
            return (surface, bottom + up * hu / 2 + n * distance)
        }
        let rim = Arena.rimCenter()
        var lo: Float = 0, hi: Float = 0.45
        for _ in 0..<28 {
            let mid = (lo + hi) / 2
            let (sf, eye) = make(mid)
            let v = sf.hit(from: eye, through: rim)?.y ?? 0
            if v < windowRimTarget { lo = mid } else { hi = mid }
        }
        let (surface, eye) = make((lo + hi) / 2)
        let slot = ArenaSlot(placement: Placement(), halfWidth: 0.5, depth: windowNearZ, crease: 0,
                             walls: [Plane(point: edge, normal: -n)], eye: eye, player: 0, sunken: false)
        return (Viewport(rect: rect, surface: surface, arena: 0), slot, Float(rect.width) / wu, s)
    }

    // MARK: Cabinet (iPhone Duo with the fold running down the window)

    /// The lane fills one half and the scoreboard the other, so the crease never cuts the hoop or the score.
    static func cabinet(_ input: LayoutInput, fold f: CGRect, ppm: Float) -> SceneLayout {
        let game = CGRect(x: f.maxX, y: 0, width: input.size.width - f.maxX, height: input.size.height)
        let side = CGRect(x: 0, y: 0, width: f.minX, height: input.size.height)
        let (vp, slot, ppu, s) = windowLane(rect: game, ppm: ppm)
        let safe = safeRect(input)
        let ng = noGo(f, size: input.size)
        let sideFree = side.intersection(safe).divided(atDistance: max(0, side.maxX - ng.minX), from: .maxXEdge).remainder
        let gameFree = game.intersection(safe).divided(atDistance: max(0, ng.maxX - game.minX), from: .minXEdge).remainder
        var panel = sideFree.insetBy(dx: 16, dy: 0)
        panel.origin.y += 12
        panel.size.height = panelHeight
        let zoneTop = max(gameFree.minY, game.height * 0.3)
        let zone = CGRect(x: gameFree.minX, y: zoneTop, width: gameFree.width, height: gameFree.maxY - zoneTop)
        let hud = HUDLayout(panels: [HUDPanel(rect: panel, rotation: 0, player: 0)], menu: sideFree.insetBy(dx: 12, dy: 12),
                            banner: nil, shootZones: [zone], noGo: ng)
        return SceneLayout(presentation: .window, viewports: [vp], arenas: [slot], pointsPerUnit: ppu, metresPerUnit: s,
                           pointsPerMetre: ppm, hinge: Float(input.hinge ?? 180), hud: hud)
    }

    // MARK: Duel (flat, face to face)

    static func duel(_ input: LayoutInput, fold: CGRect?, ppm: Float) -> SceneLayout {
        let size = input.size
        // The centre line: the real fold, else the middle of the long side.
        let line: CGRect
        if let f = fold { line = f }
        else if size.height >= size.width { line = CGRect(x: 0, y: size.height / 2, width: size.width, height: 0) }
        else { line = CGRect(x: size.width / 2, y: 0, width: 0, height: size.height) }
        let across = line.width >= line.height       // centre line runs left-right: players at bottom and top
        let center = CGPoint(x: line.midX, y: line.midY)
        let along = Float(across ? size.width : size.height)
        let ppu = along                              // 1 world unit = the length of the centre line
        let s = along / ppm
        let gap = Float(across ? line.height : line.width) / 2 / ppu

        // Table frame: x along the window's x, z toward the window's bottom edge, y out of the glass.
        func world(_ p: CGPoint) -> SIMD3<Float> {
            SIMD3(Float(p.x - center.x) / ppu, 0, Float(p.y - center.y) / ppu)
        }
        func surface(_ r: CGRect) -> Surface {
            let o = world(CGPoint(x: r.minX, y: r.maxY))
            return Surface(origin: o, right: world(CGPoint(x: r.maxX, y: r.maxY)) - o, up: world(CGPoint(x: r.minX, y: r.minY)) - o)
        }
        let rects: [CGRect]
        let yaws: [Float]
        let rotations: [Double]
        if across {
            rects = [CGRect(x: 0, y: line.maxY, width: size.width, height: size.height - line.maxY),
                     CGRect(x: 0, y: 0, width: size.width, height: line.minY)]
            yaws = [0, .pi]
            rotations = [0, 180]
        } else {
            rects = [CGRect(x: line.maxX, y: 0, width: size.width - line.maxX, height: size.height),
                     CGRect(x: 0, y: 0, width: line.minX, height: size.height)]
            yaws = [.pi / 2, -.pi / 2]
            rotations = [-90, 90]
        }
        let k = duelScale
        var slots: [ArenaSlot] = []
        var viewports: [Viewport] = []
        for i in 0..<2 {
            let r = rects[i]
            let depthWorld = Float(across ? r.height : r.width) / ppu + gap
            let placement = Placement(origin: SIMD3(0, -Arena.boardTop * k, 0), yaw: yaws[i], scale: k)
            let eyeLocal = SIMD3<Float>(0, duelEyeHeight / s, depthWorld + duelEyeBack / s)
            let eye = placement.rotation.act(eyeLocal)
            let glass = placement.planeToArena(Plane(point: .zero, normal: SIMD3(0, -1, 0)))
            let foldWall = Plane(point: .zero, normal: SIMD3(0, 0, 1))
            slots.append(ArenaSlot(placement: placement, halfWidth: 0.5 / k, depth: depthWorld / k, crease: gap / k,
                                   walls: [glass, foldWall], eye: eye, player: i, sunken: true))
            viewports.append(Viewport(rect: r, surface: surface(r), arena: i))
        }
        // Interface: each player's panel along their own edge, read from their side.
        let safe = safeRect(input)
        let ng = fold.map { noGo($0, size: size) } ?? noGo(line, size: size)
        var panels: [HUDPanel] = []
        var zones: [CGRect] = []
        for i in 0..<2 {
            let free = freePart(rects[i], safe: safe, noGo: ng)
            zones.append(free)
            let p: CGRect
            if across {
                p = i == 0 ? CGRect(x: free.minX + 16, y: free.maxY - panelHeight - 6, width: free.width - 32, height: panelHeight)
                           : CGRect(x: free.minX + 16, y: free.minY + 6, width: free.width - 32, height: panelHeight)
            } else {
                p = i == 0 ? CGRect(x: free.maxX - panelHeight - 6, y: free.minY + 16, width: panelHeight, height: free.height - 32)
                           : CGRect(x: free.minX + 6, y: free.minY + 16, width: panelHeight, height: free.height - 32)
            }
            panels.append(HUDPanel(rect: p, rotation: rotations[i], player: i))
        }
        let hud = HUDLayout(panels: panels, menu: zones[0].insetBy(dx: 12, dy: 12), banner: zones[1].insetBy(dx: 12, dy: 12),
                            shootZones: zones, noGo: ng)
        return SceneLayout(presentation: .duel, viewports: viewports, arenas: slots, pointsPerUnit: ppu, metresPerUnit: s,
                           pointsPerMetre: ppm, hinge: Float(input.hinge ?? 180), hud: hud)
    }

    /// The part of a half that is inside the safe area and clear of the crease.
    static func freePart(_ r: CGRect, safe: CGRect, noGo ng: CGRect) -> CGRect {
        var free = r.intersection(safe)
        if free.intersects(ng) {
            let pieces = [CGRect(x: free.minX, y: free.minY, width: free.width, height: max(0, ng.minY - free.minY)),
                          CGRect(x: free.minX, y: ng.maxY, width: free.width, height: max(0, free.maxY - ng.maxY)),
                          CGRect(x: free.minX, y: free.minY, width: max(0, ng.minX - free.minX), height: free.height),
                          CGRect(x: ng.maxX, y: free.minY, width: max(0, free.maxX - ng.maxX), height: free.height)]
            free = pieces.filter { !$0.intersects(ng) }.max { $0.width * $0.height < $1.width * $1.height } ?? .zero
        }
        return free
    }
}
