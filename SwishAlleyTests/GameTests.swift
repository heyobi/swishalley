import XCTest
import CoreGraphics
import simd
@testable import SwishAlley

final class GameTests: XCTestCase {
    func stage(_ hinge: Double) -> SceneLayout {
        Layout.make(LayoutInput(size: CGSize(width: 669, height: 951), fold: CGRect(x: 0, y: 470, width: 669, height: 11), hinge: hinge))!
    }

    /// Runs a lane until its first shot resolves.
    @discardableResult
    func resolve(_ lane: inout Lane, seconds: Double = 5) -> [LaneEvent] {
        var all: [LaneEvent] = []
        var t = 0.0
        while t < seconds {
            let evs = lane.step(dt: 1 / 60)
            all += evs
            if evs.contains(where: { if case .score = $0 { return true }; if case .miss = $0 { return true }; return false }) { break }
            t += 1 / 60
        }
        return all
    }

    func scored(_ evs: [LaneEvent]) -> Bool { evs.contains { if case .score = $0 { return true }; return false } }
    func swished(_ evs: [LaneEvent]) -> Bool { evs.contains { if case .score(_, true, _) = $0 { return true }; return false } }

    // MARK: Physics

    func testPerfectShotScoresAtEveryHingeAngle() {
        for a in [75.0, 90, 110, 130, 150, 180] {
            var lane = Lane(slot: stage(a).arenas[0])
            let v = lane.idealLaunch()!
            lane.launch(velocity: v, power: 1)
            let evs = resolve(&lane)
            XCTAssert(scored(evs), "perfect shot at \(a)°: \(evs)")
        }
    }

    func testPerfectShotIsASwish() {
        var lane = Lane(slot: stage(110).arenas[0])
        lane.launch(velocity: lane.idealLaunch()!, power: 1)
        XCTAssert(swished(resolve(&lane)))
    }

    func testWeakShotMissesShortAndHitsTheFloor() {
        var lane = Lane(slot: stage(110).arenas[0])
        let v = lane.idealLaunch()! * 0.7
        lane.launch(velocity: v, power: 0.6)
        let evs = resolve(&lane)
        XCTAssertFalse(scored(evs))
        XCTAssert(evs.contains { if case .miss = $0 { return true }; return false })
    }

    func testHardShotHitsTheBackboard() {
        var lane = Lane(slot: stage(110).arenas[0])
        let v = lane.idealLaunch()! * 1.35
        lane.launch(velocity: v, power: 1.6)
        let evs = resolve(&lane)
        XCTAssert(evs.contains { if case .board = $0 { return true }; if case .glass = $0 { return true }; return false }, "\(evs)")
    }

    /// Below 90° the leaning glass is a wall: a high lob bounces off it.
    func testLeaningGlassIsAWall() {
        var lane = Lane(slot: stage(70).arenas[0])
        lane.launch(velocity: SIMD3(0, 3.0, -0.4), power: 1.5)
        var evs: [LaneEvent] = []
        for _ in 0..<240 { evs += lane.step(dt: 1 / 60) }
        XCTAssert(evs.contains { if case .glass = $0 { return true }; return false }, "\(evs)")
        for b in lane.balls { XCTAssertGreaterThan(lane.slot.walls[0].distance(b.p), Arena.ballRadius - 0.01) }
    }

    func testRimRattle() {
        var lane = Lane(slot: stage(110).arenas[0])
        // Aim at the front of the rim.
        let target = lane.rimCenter + SIMD3(0, 0, Arena.rimRadius)
        lane.launch(velocity: Ballistics.launch(from: lane.launchPoint!, to: target)!, power: 1)
        var evs: [LaneEvent] = []
        for _ in 0..<180 { evs += lane.step(dt: 1 / 60) }
        XCTAssert(evs.contains { if case .rim = $0 { return true }; return false }, "\(evs)")
    }

    func testBallsComeBackToTheRack() {
        var lane = Lane(slot: stage(110).arenas[0])
        lane.launch(velocity: lane.idealLaunch()!, power: 1)
        for _ in 0..<(60 * 5) { lane.step(dt: 1 / 60) }
        XCTAssert(lane.balls.allSatisfy { $0.state == .racked }, "\(lane.balls.map(\.state))")
        XCTAssertNotNil(lane.readyBall)
    }

    func testRapidFireFiveBalls() {
        var lane = Lane(slot: stage(110).arenas[0])
        var shots = 0
        var scores = 0
        for _ in 0..<(60 * 8) {
            if lane.readyBall != nil, let v = lane.idealLaunch() {
                lane.launch(velocity: v, power: 1)
                shots += 1
            }
            for e in lane.step(dt: 1 / 60) { if case .score = e { scores += 1 } }
        }
        let states = lane.balls.map { "\($0.state) \($0.p)" }.joined(separator: "; ")
        XCTAssertGreaterThan(shots, 6, states)
        // Balls in the air collide with each other (as in a real arcade lane), so a stream of shots scores less.
        XCTAssertGreaterThan(scores, shots / 4, states)
    }

    func testMovingHoopStillScores() {
        var lane = Lane(slot: stage(110).arenas[0])
        lane.slide = 0.18
        lane.launch(velocity: lane.idealLaunch()!, power: 1)
        XCTAssert(scored(resolve(&lane)))
    }

    func testDuelAndWindowLanesScore() {
        let duel = Layout.make(LayoutInput(size: CGSize(width: 669, height: 951), fold: CGRect(x: 0, y: 470, width: 669, height: 11), hinge: 180, duel: true))!
        let window = Layout.make(LayoutInput(size: CGSize(width: 402, height: 874)))!
        for slot in duel.arenas + window.arenas {
            var lane = Lane(slot: slot)
            lane.launch(velocity: lane.idealLaunch()!, power: 1)
            let evs = resolve(&lane)
            XCTAssert(scored(evs), "\(slot.sunken ? "duel" : "window") lane: \(evs)")
            // The sunken lane's glass ceiling is never crossed.
            for b in lane.balls { for w in slot.walls { XCTAssertGreaterThan(w.distance(b.p), Arena.ballRadius - 0.01) } }
        }
    }

    // MARK: Flicks

    /// Window points of the ball on the lower half, and a flick from there toward the hoop.
    func flick(layout l: SceneLayout, viewport: Int, arena: Int, speedFactor: Float, angle: Float = 0) -> Flick.Shot? {
        let vp = l.viewports[viewport]
        let slot = l.arenas[arena]
        let lane = Lane(slot: slot)
        // Screen direction toward the hoop: project the rack and a point 0.1 ahead of it.
        func screen(_ p: SIMD3<Float>) -> CGPoint {
            let w = slot.placement.toWorld(p)
            let h = vp.surface.hit(from: slot.eye, through: w)!
            return CGPoint(x: vp.rect.minX + CGFloat(h.x) * vp.rect.width, y: vp.rect.maxY - CGFloat(h.y) * vp.rect.height)
        }
        let a = screen(lane.rackPosition(queue: 0))
        let b = screen(lane.rackPosition(queue: 0) + SIMD3(0, 0, -0.1))
        var dx = Float(b.x - a.x), dy = Float(b.y - a.y)
        let n = (dx * dx + dy * dy).squareRoot()
        dx /= n; dy /= n
        let c = cos(angle), s = sin(angle)
        let rx = dx * c - dy * s, ry = dx * s + dy * c
        let speed = Flick.referenceSpeed * speedFactor * l.pointsPerMetre
        return Flick.shot(release: a, velocity: CGVector(dx: CGFloat(rx * speed), dy: CGFloat(ry * speed)), viewport: vp, eye: slot.eye,
                          placement: slot.placement, from: lane.launchPoint!, target: lane.rimCenter, ceiling: lane.ceiling, pointsPerMetre: l.pointsPerMetre)
    }

    func testReferenceFlickScoresOnTheStage() throws {
        let l = stage(110)
        let shot = try XCTUnwrap(flick(layout: l, viewport: 1, arena: 0, speedFactor: 1))
        var lane = Lane(slot: l.arenas[0])
        lane.launch(velocity: shot.velocity, power: shot.power)
        XCTAssert(scored(resolve(&lane)))
    }

    func testOpponentFlicksTowardTheFoldFromTheirSide() throws {
        for (size, fold) in [(CGSize(width: 669, height: 951), CGRect(x: 0, y: 470, width: 669, height: 11)),
                             (CGSize(width: 951, height: 669), CGRect(x: 470, y: 0, width: 11, height: 669))] {
            let l = Layout.make(LayoutInput(size: size, fold: fold, hinge: 180, duel: true))!
            for i in 0..<2 {
                let shot = try XCTUnwrap(flick(layout: l, viewport: i, arena: i, speedFactor: 1), "player \(i) \(size)")
                var lane = Lane(slot: l.arenas[i])
                lane.launch(velocity: shot.velocity, power: shot.power)
                XCTAssert(scored(resolve(&lane)), "player \(i) \(size)")
            }
        }
    }

    func testOverpoweredAndCrookedFlicksMiss() throws {
        let l = stage(110)
        for (factor, angle) in [(Float(1.9), Float(0)), (0.45, 0), (1, 0.45)] {
            let shot = try XCTUnwrap(flick(layout: l, viewport: 1, arena: 0, speedFactor: factor, angle: angle))
            var lane = Lane(slot: l.arenas[0])
            lane.launch(velocity: shot.velocity, power: shot.power)
            XCTAssertFalse(scored(resolve(&lane)), "factor \(factor) angle \(angle)")
        }
    }

    func testFlickAwayFromTheHoopIsNotAShot() {
        let l = stage(110)
        XCTAssertNil(flick(layout: l, viewport: 1, arena: 0, speedFactor: 1, angle: .pi))
    }

    func testSameFlickFeelsTheSameOnEveryDevice() throws {
        let phone = Layout.make(LayoutInput(size: CGSize(width: 402, height: 874)))!
        let pad = Layout.make(LayoutInput(size: CGSize(width: 1032, height: 1376), isPad: true, nativeScale: 2))!
        for l in [phone, pad] {
            let shot = try XCTUnwrap(flick(layout: l, viewport: 0, arena: 0, speedFactor: 1))
            XCTAssertEqual(shot.power, 1, accuracy: 0.01)
            var lane = Lane(slot: l.arenas[0])
            lane.launch(velocity: shot.velocity, power: shot.power)
            XCTAssert(scored(resolve(&lane)))
        }
    }

    func testFlickVelocityFromSamples() throws {
        let samples = (0..<10).map { TouchSample(t: Double($0) * 0.01, p: CGPoint(x: 100, y: 500 - Double($0) * 20)) }
        let v = try XCTUnwrap(Flick.velocity(samples))
        XCTAssertEqual(v.dy, -2000, accuracy: 1)
        XCTAssertEqual(v.dx, 0, accuracy: 0.001)
    }

    // MARK: Rules

    func play(_ m: inout Match, seconds: Double) -> [MatchEvent] {
        var all: [MatchEvent] = []
        var t = 0.0
        while t < seconds { all += m.update(dt: 0.05); t += 0.05 }
        return all
    }

    func testClassicRound() {
        var m = Match(mode: .classic)
        XCTAssertFalse(m.canShoot(0))
        let start = play(&m, seconds: 2.5)
        XCTAssert(start.contains(.go))
        XCTAssert(m.canShoot(0))
        XCTAssertEqual(m.basket(player: 0, swish: false).first, .basket(player: 0, points: 2, swish: false, onFire: false, double: false))
        XCTAssertEqual(m.players[0].points, 2)
        _ = m.basket(player: 0, swish: true)                 // 3
        let third = m.basket(player: 0, swish: false)        // 2, fire starts
        XCTAssert(third.contains(.fireOn(player: 0)))
        XCTAssertEqual(m.basket(player: 0, swish: false).first, .basket(player: 0, points: 3, swish: false, onFire: true, double: false))
        XCTAssertEqual(m.miss(player: 0), [.fireOff(player: 0)])
        XCTAssertEqual(m.players[0].streak, 0)
        XCTAssertEqual(m.hoopSlide(player: 0), 0)
        // The final stretch: double points and a moving hoop.
        let evs = play(&m, seconds: 50.5)
        XCTAssert(evs.contains(.finalStretch))
        XCTAssert(m.isFinalStretch)
        XCTAssertEqual(m.basket(player: 0, swish: false).first, .basket(player: 0, points: 4, swish: false, onFire: false, double: true))
        _ = play(&m, seconds: 1.5)
        XCTAssertNotEqual(m.hoopSlide(player: 0), 0)
        let end = play(&m, seconds: 10)
        XCTAssert(end.contains(.buzzer))
        XCTAssertEqual(m.phase, .over)
        XCTAssertFalse(m.canShoot(0))
        XCTAssertEqual(end.filter { if case .secondTick = $0 { return true }; return false }.count, 5)
    }

    func testDuelTurnsAlternate() {
        var m = Match(mode: .duelTurns)
        _ = play(&m, seconds: 2.5)
        XCTAssert(m.canShoot(0))
        XCTAssertFalse(m.canShoot(1))
        let evs = play(&m, seconds: 15.2 + Match.turnBreak)
        XCTAssert(evs.contains(.turn(player: 1)))
        XCTAssert(m.canShoot(1))
        XCTAssertFalse(m.canShoot(0))
        _ = play(&m, seconds: (15 + Match.turnBreak) * 6)
        XCTAssertEqual(m.phase, .over)
    }

    func testDuelRaceBothShootAndWinner() {
        var m = Match(mode: .duelRace)
        _ = play(&m, seconds: 2.5)
        XCTAssert(m.canShoot(0) && m.canShoot(1))
        _ = m.basket(player: 1, swish: false)
        _ = play(&m, seconds: 46)
        XCTAssertEqual(m.winner, 1)
    }

    func testOvertimeAddsTime() {
        var m = Match(mode: .overtime)
        _ = play(&m, seconds: 2.5)
        let before = m.timeLeft
        _ = m.basket(player: 0, swish: false)
        XCTAssertEqual(m.timeLeft, before + Match.overtimeBonus, accuracy: 1e-9)
    }

    func testPracticeHasNoClock() {
        var m = Match(mode: .practice)
        _ = play(&m, seconds: 120)
        XCTAssertEqual(m.phase, .playing)
    }

    func testBestsAndReviewOnlyAfterABest() {
        let d = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let b = Bests(defaults: d)
        XCTAssertFalse(b.record(.classic, score: 0))
        XCTAssertTrue(b.record(.classic, score: 30))
        XCTAssertFalse(b.record(.classic, score: 20))
        XCTAssertFalse(b.record(.duelRace, score: 99))
        XCTAssertFalse(ReviewGate.shouldAsk(afterBest: false, defaults: d))
        XCTAssertFalse(ReviewGate.shouldAsk(afterBest: true, defaults: d))     // fewer than three rounds
        d.set(3, forKey: "rounds")
        XCTAssertTrue(ReviewGate.shouldAsk(afterBest: true, defaults: d))
        XCTAssertFalse(ReviewGate.shouldAsk(afterBest: true, defaults: d))    // once per version
    }

    // MARK: Sound

    func testSynthMakesSound() throws {
        let s = Synth()
        try s.startOffline()
        s.play("neon")
        let music = try s.renderOffline(seconds: 2)
        XCTAssertGreaterThan(music.rms, 0.01)
        XCTAssertLessThan(music.peak, 1.0)
        s.play(nil)
        _ = try s.renderOffline(seconds: 1)
        for v in [Voice.swish, .rim, .board, .bounce, .buzzer, .chime] {
            s.sfx(v, freq: 500, vel: 0.9, dur: 0.2)
            let r = try s.renderOffline(seconds: 0.3)
            XCTAssertGreaterThan(r.rms, 0.002, "\(v)")
        }
    }

    func testTracksAreOriginalLoops() {
        for t in Tracks.all {
            XCTAssertFalse(t.events.isEmpty)
            XCTAssert(t.events.allSatisfy { $0.beat >= 0 && $0.beat < t.loopBeats }, t.id)
        }
    }

    // MARK: Rack, Wild Toss, bonuses

    /// Racked balls keep a stable order and never overlap or jitter (build 1 feedback).
    func testRackIsStableAndBallsNeverOverlap() {
        var lane = Lane(slot: stage(110).arenas[0])
        for _ in 0..<3 {
            lane.launch(velocity: lane.idealLaunch()!, power: 1)
            for _ in 0..<20 { lane.step(dt: 1 / 60) }
        }
        for _ in 0..<(60 * 5) { lane.step(dt: 1 / 60) }
        var previous = lane.balls.map(\.p)
        for _ in 0..<60 {
            lane.step(dt: 1 / 60)
            let racked = lane.balls.filter { $0.state == .racked }
            for a in racked { for b in racked where a.id < b.id { XCTAssertGreaterThan(simd_distance(a.p, b.p), Arena.ballRadius * 1.9) } }
            let now = lane.balls.map(\.p)
            for (x, y) in zip(previous, now) { XCTAssertLessThan(simd_distance(x, y), 0.002, "a racked ball moved") }
            previous = now
        }
        XCTAssertEqual(Set(lane.order), Set(lane.balls.indices))
    }

    func testWatermelonSplatsAndANewOnePopsUp() {
        var lane = Lane(slot: stage(110).arenas[0])
        lane.wild = true
        lane.reset()
        XCTAssert(lane.balls.allSatisfy { $0.kind != .ball })
        // Force a melon on the spot and lob it short so it lands hard.
        var evs: [LaneEvent] = []
        var tries = 0
        while !evs.contains(where: { if case .splat = $0 { return true }; return false }) && tries < 12 {
            tries += 1
            for _ in 0..<(60 * 2) where lane.readyBall == nil { lane.step(dt: 1 / 60) }
            lane.launch(velocity: SIMD3(0, 2.2, -0.2), power: 1)
            for _ in 0..<(60 * 2) { evs += lane.step(dt: 1 / 60) }
        }
        XCTAssert(evs.contains { if case .splat(_, let k, _) = $0 { return k.breaks }; return false }, "\(evs)")
        XCTAssert(evs.contains { if case .miss = $0 { return true }; return false })
    }

    func testGoldenBallGivesABiggerHoop() {
        var m = Match(mode: .classic)
        var evs: [MatchEvent] = []
        var t = 0.0
        while t < 12 { evs += m.update(dt: 0.05); t += 0.05 }
        XCTAssert(evs.contains(.goldenBall(player: 0)))
        let bonus = m.goldenScored(player: 0)
        XCTAssertEqual(bonus, [.bonus(player: 0, kind: .bigHoop)])
        XCTAssertEqual(m.hoopScale(player: 0), 1.4)
        // A bigger rim still keeps its back edge on the crease, and a perfect shot still goes in.
        var lane = Lane(slot: stage(110).arenas[0])
        lane.rimScale = 1.4
        XCTAssertEqual(lane.rimCenter.z - lane.rimRadius - Arena.rimTube, lane.slot.crease, accuracy: 1e-6)
        lane.launch(velocity: lane.idealLaunch()!, power: 1)
        XCTAssert(scored(resolve(&lane)))
        // The next golden ball doubles points.
        _ = m.update(dt: Match.bonusLength + 0.1)
        XCTAssertEqual(m.goldenScored(player: 0), [.bonus(player: 0, kind: .double)])
        XCTAssertEqual(m.basket(player: 0, swish: false).first, .basket(player: 0, points: 4, swish: false, onFire: false, double: true))
    }

    func testGoldenFlagTravelsWithTheBall() {
        var lane = Lane(slot: stage(110).arenas[0])
        lane.markGolden()
        XCTAssertEqual(lane.balls.filter(\.golden).count, 1)
        var evs: [LaneEvent] = []
        for _ in 0..<4 {
            for _ in 0..<(60 * 2) where lane.readyBall == nil { lane.step(dt: 1 / 60) }
            lane.launch(velocity: lane.idealLaunch()!, power: 1)
            for _ in 0..<90 { evs += lane.step(dt: 1 / 60) }
        }
        XCTAssert(evs.contains { if case .golden = $0 { return true }; return false }, "\(evs)")
    }

    func testUnstoppableAtSixInARow() {
        var m = Match(mode: .practice)
        _ = m.update(dt: 3)
        var evs: [MatchEvent] = []
        for _ in 0..<6 { evs += m.basket(player: 0, swish: false) }
        XCTAssert(evs.contains(.unstoppable(player: 0)))
        XCTAssertEqual(m.basket(player: 0, swish: false).first, .basket(player: 0, points: 4, swish: false, onFire: true, double: false))
    }

    /// Paid content is things to play with, never a clock.
    func testOnlyWildTossNeedsPro() {
        XCTAssertEqual(Mode.allCases.filter(\.isPro), [.wildToss])
    }
}
