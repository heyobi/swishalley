import XCTest
import CoreGraphics
import simd
@testable import SwishAlley

/// The iPhone Duo geometry: the hinge angle becomes the angle between the two display planes, the backboard stays
/// upright and the floor flat at every angle, the rim and the floor edge sit on the real fold, and no interface
/// ever lands on the crease.
final class GeometryTests: XCTestCase {
    static let angles: [Double] = [75, 90, 100, 110, 120, 130, 145, 160, 180]
    static let foldHeights: [CGFloat] = [0, 11, 24]

    /// The Duo inner display held as an "L": the tall window, fold across it. The fold is deliberately not in the
    /// middle in some cases, to prove nothing assumes the centre.
    func duo(hinge: Double, foldY: CGFloat = 470, foldH: CGFloat = 11, insets: Insets = Insets()) -> LayoutInput {
        LayoutInput(size: CGSize(width: 669, height: 951), fold: CGRect(x: 0, y: foldY, width: 669, height: foldH), hinge: hinge,
                    closed: false, duel: false, isPad: false, nativeScale: 3, insets: insets)
    }

    private func ndcY(_ p: SIMD3<Float>, eye: SIMD3<Float>, _ s: Surface) -> Float { OffAxis(eye: eye, surface: s).ndc(p).y }

    // MARK: Hinge angle → planes

    func testHalvesMeetAtTheHingeAngle() throws {
        for a in Self.angles {
            let l = try XCTUnwrap(Layout.make(duo(hinge: a)))
            XCTAssertEqual(l.presentation, .stage)
            let up = l.viewports[0].surface, low = l.viewports[1].surface
            // The upper half rises from the fold; the lower half runs from the fold toward the viewer.
            let between = acos(simd_dot(up.vu, -low.vu)) * 180 / .pi
            XCTAssertEqual(Double(between), a, accuracy: 0.01, "angle between the halves at \(a)°")
            XCTAssertEqual(l.hinge, Float(a), accuracy: 1e-4)
            // The floor half lies flat (normal straight up) whatever the hinge does.
            XCTAssertEqual(low.normal.y, 1, accuracy: 1e-5)
            // The upright half's normal is perpendicular to the fold line and tilts from vertical by 180° − hinge.
            XCTAssertEqual(simd_dot(up.normal, SIMD3(1, 0, 0)), 0, accuracy: 1e-5)
            XCTAssertEqual(Double(acos(up.normal.y)) * 180 / .pi, 180 - a, accuracy: 0.01)
        }
    }

    func testEveryAngleInBetweenIsContinuous() throws {
        var previous: Surface?
        for tenth in 900...1300 {
            let a = Double(tenth) / 10
            let l = try XCTUnwrap(Layout.make(duo(hinge: a)))
            let up = l.viewports[0].surface
            if let p = previous {
                // 0.1° of hinge moves the top edge of the upper half by a tiny, smooth amount.
                XCTAssertLessThan(simd_distance(p.point(0.5, 1), up.point(0.5, 1)), 0.003)
            }
            previous = up
        }
    }

    /// Gravity in the lane is straight down the arena's y axis: perpendicular to the floor half at every angle,
    /// and for a duel perpendicular to the flat display.
    func testGravityIsPerpendicularToTheFloor() throws {
        for a in Self.angles {
            let l = try XCTUnwrap(Layout.make(duo(hinge: a)))
            let floorNormal = l.viewports[1].surface.normal
            let g = l.arenas[0].placement.directionToWorld(SIMD3(0, -1, 0))
            XCTAssertEqual(simd_dot(g, floorNormal), -1, accuracy: 1e-5)
        }
        var input = duo(hinge: 180)
        input.duel = true
        let d = try XCTUnwrap(Layout.make(input))
        for (i, vp) in d.viewports.enumerated() {
            let g = d.arenas[i].placement.directionToWorld(SIMD3(0, -1, 0))
            XCTAssertEqual(simd_dot(g, vp.surface.normal), -1, accuracy: 1e-5)
        }
    }

    /// The backboard is drawn upright and the floor flat for the viewer: the board's vertical edge, projected from
    /// the eye through the upper glass, lands where a vertical line in the room would, at every hinge angle. With
    /// an off-axis camera per half this is the same as: a point's image on each glass lies on the sight line.
    func testBackboardStaysUprightForTheViewer() throws {
        for a in [90.0, 110, 130] {
            let l = try XCTUnwrap(Layout.make(duo(hinge: a)))
            let up = l.viewports[0].surface
            let eye = l.arenas[0].eye
            let bottom = SIMD3<Float>(0.2, Arena.boardBottom, 0), top = SIMD3<Float>(0.2, Arena.boardTop, 0)
            for p in [bottom, top] {
                let hit = try XCTUnwrap(up.hit(from: eye, through: p))
                let o = OffAxis(eye: eye, surface: up)
                let ndc = o.ndc(p)
                XCTAssertEqual(ndc.x, hit.x * 2 - 1, accuracy: 1e-3)
                XCTAssertEqual(ndc.y, hit.y * 2 - 1, accuracy: 1e-3)
            }
            // The board stands at 90° to the floor plane, independent of the hinge.
            XCTAssertEqual(simd_dot(simd_normalize(top - bottom), l.viewports[1].surface.normal), 1, accuracy: 1e-6)
        }
    }

    /// From the nominal viewer the hoop is on the upright half and the ball rack on the floor half, at every angle
    /// the stage is used for.
    func testHoopOnUpperHalfRackOnLowerHalf() throws {
        for a in [80.0, 90, 110, 130, 150] {
            let l = try XCTUnwrap(Layout.make(duo(hinge: a)))
            let lane = Lane(slot: l.arenas[0])
            let up = l.viewports[0].surface, low = l.viewports[1].surface
            let eye = l.arenas[0].eye
            for p in [lane.rimCenter, SIMD3(0, Arena.boardBottom, lane.boardZ)] {
                let h = try XCTUnwrap(up.hit(from: eye, through: p), "\(a)°")
                XCTAssert(h.y > 0.05 && h.y < 0.98, "hoop part at v=\(h.y) on the upper half at \(a)°")
                XCTAssert(h.x > 0 && h.x < 1)
            }
            let rack = try XCTUnwrap(low.hit(from: eye, through: lane.rackPosition(queue: 0)))
            XCTAssert(rack.y > 0.04 && rack.y < 0.6, "rack at v=\(rack.y) on the lower half at \(a)°")
        }
    }

    /// The two halves join without a seam: a point on the fold appears at the top edge of the floor view and the
    /// bottom edge of the upright view.
    func testSeamAtTheFold() throws {
        for a in Self.angles {
            let l = try XCTUnwrap(Layout.make(duo(hinge: a, foldH: 0)))
            let eye = l.arenas[0].eye
            let p = SIMD3<Float>(0.21, 0, 0)
            XCTAssertEqual(ndcY(p, eye: eye, l.viewports[1].surface), 1, accuracy: 1e-3)
            XCTAssertEqual(ndcY(p, eye: eye, l.viewports[0].surface), -1, accuracy: 1e-3)
        }
    }

    // MARK: Fold position

    func testFloorEndsAndRimSitsOnTheRealFold() throws {
        for fh in Self.foldHeights {
            for foldY: CGFloat in [470, 430, 512] {
                for a in [90.0, 110, 130] {
                    let input = duo(hinge: a, foldY: foldY, foldH: fh)
                    let l = try XCTUnwrap(Layout.make(input))
                    let slot = l.arenas[0]
                    let ppu = l.pointsPerUnit
                    // The crease is half the reserved region, in lane units.
                    XCTAssertEqual(slot.crease, Float(fh) / 2 / ppu, accuracy: 1e-6)
                    // The floor half's far edge is the crease edge…
                    let low = l.viewports[1].surface
                    XCTAssertEqual(low.point(0.5, 1).z, slot.crease, accuracy: 1e-6)
                    // …and the view showing it starts exactly below the reserved region.
                    XCTAssertEqual(l.viewports[1].rect.minY, foldY + fh, accuracy: 0.001)
                    XCTAssertEqual(l.viewports[0].rect.maxY, foldY, accuracy: 0.001)
                    // The backboard stands on the fold and the rim's back edge is straight above the crease edge.
                    XCTAssertEqual(slot.setback, 0)
                    let lane = Lane(slot: slot)
                    XCTAssertEqual(lane.rimCenter.z - Arena.rimRadius - Arena.rimTube, slot.crease, accuracy: 1e-6)
                    XCTAssertEqual(lane.boardZ, 0)
                    // The lane is as deep as the floor half really is.
                    XCTAssertEqual(slot.depth * ppu, Float(input.size.height - foldY - fh) + Float(fh) / 2, accuracy: 0.01)
                }
            }
        }
    }

    /// Below 90° the upright half leans over the floor; the hoop comes forward just enough to stay in front of the
    /// glass, so a ball can still reach it.
    func testLeaningGlassPushesTheHoopForward() throws {
        let l = try XCTUnwrap(Layout.make(duo(hinge: 75)))
        let slot = l.arenas[0]
        XCTAssertGreaterThan(slot.setback, 0)
        let glass = slot.walls[0]
        let topFront = SIMD3<Float>(0, Arena.boardTop, slot.setback)
        XCTAssertGreaterThanOrEqual(glass.distance(topFront), -1e-4)
    }

    func testInterfaceNeverOnTheCrease() throws {
        let insetsList = [Insets(), Insets(top: 24, left: 0, bottom: 20, right: 0)]
        for ins in insetsList {
            for fh in Self.foldHeights {
                for a in [90.0, 120, 180] {
                    // Half-open stage.
                    try checkHUD(duo(hinge: a, foldH: fh, insets: ins))
                    // Book pose: fold down the window → cabinet layout.
                    try checkHUD(LayoutInput(size: CGSize(width: 951, height: 669), fold: CGRect(x: 470, y: 0, width: fh, height: 669),
                                             hinge: a, insets: ins))
                    // Duel, both orientations.
                    var d = duo(hinge: a, foldH: fh, insets: ins)
                    d.duel = true
                    try checkHUD(d)
                    try checkHUD(LayoutInput(size: CGSize(width: 951, height: 669), fold: CGRect(x: 470, y: 0, width: fh, height: 669),
                                             hinge: a, duel: true, insets: ins))
                }
            }
        }
    }

    private func checkHUD(_ input: LayoutInput, file: StaticString = #filePath, line: UInt = #line) throws {
        let l = try XCTUnwrap(Layout.make(input), file: file, line: line)
        let ng = try XCTUnwrap(l.hud.noGo, file: file, line: line)
        let f = input.fold!
        XCTAssert(ng.contains(f) || f.width == 0 || f.height == 0, file: file, line: line)
        var rects = l.hud.panels.map(\.rect) + l.hud.shootZones + [l.hud.menu]
        if let b = l.hud.banner { rects.append(b) }
        let safe = Layout.safeRect(input)
        for r in rects where r.width > 0 && r.height > 0 {
            XCTAssertFalse(r.intersects(ng), "\(r) crosses the crease \(ng) in \(l.presentation)", file: file, line: line)
            XCTAssertTrue(safe.insetBy(dx: -0.5, dy: -0.5).contains(r), "\(r) outside the safe area", file: file, line: line)
        }
        // Scene views never span the crease either.
        for vp in l.viewports {
            XCTAssertFalse(vp.rect.insetBy(dx: 0.5, dy: 0.5).intersects(f.insetBy(dx: f.width == 0 ? 0 : 0.5, dy: f.height == 0 ? 0 : 0.5)) && f.width > 0 && f.height > 0,
                           "view \(vp.rect) spans the fold", file: file, line: line)
        }
        XCTAssertFalse(l.hud.panels.isEmpty, file: file, line: line)
        for p in l.hud.panels { XCTAssertGreaterThan(min(p.rect.width, p.rect.height), 40, file: file, line: line) }
    }

    func testCabinetKeepsTheHoopOffTheFold() throws {
        let input = LayoutInput(size: CGSize(width: 951, height: 669), fold: CGRect(x: 470, y: 0, width: 11, height: 669), hinge: 120)
        let l = try XCTUnwrap(Layout.make(input))
        XCTAssertEqual(l.presentation, .window)
        XCTAssertEqual(l.viewports.count, 1)
        XCTAssertGreaterThanOrEqual(l.viewports[0].rect.minX, 481)
        XCTAssertLessThan(l.hud.menu.maxX, 470 - Layout.foldMargin + 0.5)
    }

    func testClosedDuoUsesOneScreen() throws {
        var input = duo(hinge: 0)
        input.closed = true
        let l = try XCTUnwrap(Layout.make(input))
        XCTAssertEqual(l.presentation, .window)
        XCTAssertNil(l.hud.noGo)
    }

    // MARK: Duel

    func testDuelBackboardsMeetOnTheFold() throws {
        for (size, fold) in [(CGSize(width: 669, height: 951), CGRect(x: 0, y: 470, width: 669, height: 11)),
                             (CGSize(width: 951, height: 669), CGRect(x: 470, y: 0, width: 11, height: 669))] {
            let input = LayoutInput(size: size, fold: fold, hinge: 180, duel: true)
            let l = try XCTUnwrap(Layout.make(input))
            XCTAssertEqual(l.presentation, .duel)
            XCTAssertEqual(l.viewports.count, 2)
            for (i, vp) in l.viewports.enumerated() {
                let slot = l.arenas[i]
                let lane = Lane(slot: slot)
                // The top edge of the backboard is flush with the glass and lies on the fold line.
                let topWorld = slot.placement.toWorld(SIMD3(0.1, Arena.boardTop, 0))
                XCTAssertEqual(topWorld.y, 0, accuracy: 1e-5)
                XCTAssertEqual(size.height > size.width ? topWorld.z : topWorld.x, 0, accuracy: 1e-5, "board top on the fold for player \(i)")
                // Hoop and rack visible inside the player's own half.
                for (p, name) in [(lane.rimCenter, "rim"), (lane.rackPosition(queue: 0), "rack")] {
                    let h = try XCTUnwrap(vp.surface.hit(from: slot.eye, through: slot.placement.toWorld(p)))
                    XCTAssert(h.x > 0.05 && h.x < 0.95 && h.y > 0.05 && h.y < 0.97, "\(name) at \(h) for player \(i)")
                }
                // Each view sits on its own side of the fold.
                XCTAssertFalse(vp.rect.intersects(fold.insetBy(dx: 0.5, dy: 0.5)))
            }
            // Panels face their players.
            XCTAssertEqual(l.hud.panels.map(\.rotation), size.height > size.width ? [0, 180] : [-90, 90])
        }
    }

    func testDuelWithoutFoldSplitsTheMiddle() throws {
        let l = try XCTUnwrap(Layout.make(LayoutInput(size: CGSize(width: 402, height: 874), duel: true)))
        XCTAssertEqual(l.viewports[0].rect.minY, 437, accuracy: 0.01)
        XCTAssertEqual(l.viewports[1].rect.maxY, 437, accuracy: 0.01)
    }

    // MARK: Single screen

    func testWindowLaneOnEveryScreen() throws {
        let screens: [(CGSize, Bool)] = [(CGSize(width: 402, height: 874), false), (CGSize(width: 874, height: 402), false),
                                         (CGSize(width: 1032, height: 1376), true), (CGSize(width: 1376, height: 1032), true),
                                         (CGSize(width: 466, height: 678), false)]
        for (size, pad) in screens {
            let l = try XCTUnwrap(Layout.make(LayoutInput(size: size, isPad: pad, nativeScale: pad ? 2 : 3)))
            XCTAssertEqual(l.presentation, .window)
            let vp = l.viewports[0], slot = l.arenas[0]
            let lane = Lane(slot: slot)
            let rim = try XCTUnwrap(vp.surface.hit(from: slot.eye, through: lane.rimCenter))
            XCTAssertEqual(rim.y, Layout.windowRimTarget, accuracy: 0.02, "rim height on \(size)")
            let rack = try XCTUnwrap(vp.surface.hit(from: slot.eye, through: lane.rackPosition(queue: 0)))
            XCTAssert(rack.y > 0.1 && rack.y < 0.45, "rack at \(rack.y) on \(size)")
            // A perfect shot never touches the screen glass.
            let from = lane.rackPosition(queue: 0)
            let v = try XCTUnwrap(Ballistics.launch(from: from, to: lane.rimCenter))
            for k in 0..<60 {
                let p = Ballistics.position(from, v, t: Float(k) * 0.015)
                XCTAssertGreaterThan(slot.walls[0].distance(p), Arena.ballRadius, "shot touches the glass on \(size)")
            }
        }
    }

    // MARK: Projection basics (from Tinyfolk)

    func testOffAxisCornersMapToImageCorners() {
        let s = Surface(origin: SIMD3(-0.5, -1, 0), right: SIMD3(1, 0, 0), up: SIMD3(0, 2, 0))
        for eye in [SIMD3<Float>(0, 0, 3), SIMD3(0.8, -0.6, 2.5)] {
            let o = OffAxis(eye: eye, surface: s)
            XCTAssertEqual(o.ndc(s.point(0, 0)).x, -1, accuracy: 1e-3)
            XCTAssertEqual(o.ndc(s.point(1, 1)).y, 1, accuracy: 1e-3)
        }
    }

    func testPlacementRoundTrip() {
        let p = Placement(origin: SIMD3(0.1, -0.4, 0.2), yaw: 1.3, scale: 0.7)
        let x = SIMD3<Float>(0.3, 0.2, -0.5)
        let back = p.toArena(p.toWorld(x))
        XCTAssertEqual(simd_distance(back, x), 0, accuracy: 1e-5)
    }
}
