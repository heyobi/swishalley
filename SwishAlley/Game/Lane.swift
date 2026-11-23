import simd

enum BallState: Equatable { case racked, held, flying, returning }

struct Ball: Equatable {
    var id: Int
    var p: SIMD3<Float>
    var v = SIMD3<Float>(repeating: 0)
    /// Visual spin (radians per second about each axis), integrated by the renderer.
    var spin = SIMD3<Float>(repeating: 0)
    var state: BallState = .racked
    var shotTime: Double = 0
    var touchedRim = false
    var touchedBoard = false
    var resolved = false
    /// Last time the ball made a sound on the floor (for repeated small bounces).
    var lastBounce: Double = 0
    var returningSince: Double = 0
    /// Below the rim inside the net after a basket.
    var inNetUntil: Double = 0
}

enum LaneEvent: Equatable {
    case floor(ball: Int, speed: Float)
    case rim(ball: Int, speed: Float)
    case board(ball: Int, speed: Float)
    case glass(ball: Int, speed: Float)
    case wall(ball: Int, speed: Float)
    case score(ball: Int, swish: Bool, bank: Bool)
    case miss(ball: Int)
    case launch(ball: Int, power: Float)
    case reracked(ball: Int)
}

/// One arcade lane: the balls, the hoop and every surface the balls touch, simulated in arena units with
/// gravity straight down the arena's y axis (the arena's floor is level with the table, so this is real down).
/// Pure logic, stepped at a fixed rate, so every rule can be unit-tested.
struct Lane {
    static let ballCount = 5
    static let substep: Float = 1.0 / 240
    static let floorRestitution: Float = 0.62
    static let rimRestitution: Float = 0.5
    static let boardRestitution: Float = 0.68
    static let glassRestitution: Float = 0.45
    /// The floor slopes gently back to the shooter, like an arcade lane's return ramp.
    static let rampAcceleration: Float = 1.7
    static let shotTimeout = 3.0

    /// Geometry of the lane; updated live while the hinge moves (balls keep flying).
    var slot: ArenaSlot
    private(set) var balls: [Ball] = []
    /// Sideways offset of the hoop (and its backboard).
    var slide: Float = 0
    private(set) var time: Double = 0
    private var nextShotID = 0

    init(slot: ArenaSlot) {
        self.slot = slot
        for i in 0..<Self.ballCount {
            balls.append(Ball(id: i, p: rackPosition(queue: i)))
        }
    }

    // MARK: Geometry

    var rackZ: Float { min(Arena.rackDistance, slot.depth - 0.1) }
    var rimCenter: SIMD3<Float> { Arena.rimCenter(slide: slide, back: slot.crease + slot.setback) }
    /// Height of a glass ceiling over the lane (duel), if any.
    var ceiling: Float? { slot.walls.filter { $0.normal.y < -0.9 }.map { $0.point.y }.min() }

    /// The perfect shot from the waiting ball right now.
    func idealLaunch() -> SIMD3<Float>? {
        guard let from = launchPoint else { return nil }
        return Ballistics.idealLaunch(from: from, to: rimCenter, ceiling: ceiling)
    }

    /// The plane of the backboard's face.
    var boardZ: Float { slot.setback }

    /// The waiting spots: 0 is the shooting spot, the rest a short queue beside it.
    func rackPosition(queue i: Int) -> SIMD3<Float> {
        let r = Arena.ballRadius
        if i == 0 { return SIMD3(0, r, rackZ) }
        let side: Float = i % 2 == 1 ? 1 : -1
        let step = Float((i + 1) / 2)
        return SIMD3(side * (0.13 + 0.115 * (step - 1)), r, min(rackZ + 0.035, slot.depth - r))
    }

    /// Index of the ball on the shooting spot, if one is ready.
    var readyBall: Int? {
        let spot = rackPosition(queue: 0)
        return balls.firstIndex { ($0.state == .racked || $0.state == .held) && simd_distance($0.p, spot) < 0.02 }
    }

    var heldBall: Int? { balls.firstIndex { $0.state == .held } }

    // MARK: Input

    mutating func hold(sideways x: Float) -> Bool {
        guard let i = readyBall else { return false }
        balls[i].state = .held
        balls[i].p = rackPosition(queue: 0) + SIMD3(max(-0.25, min(0.25, x)), 0.025, 0)
        return true
    }

    mutating func moveHeld(sideways x: Float) {
        guard let i = heldBall else { return }
        balls[i].p.x = max(-0.25, min(0.25, x))
    }

    mutating func cancelHold() {
        guard let i = heldBall else { return }
        balls[i].state = .racked
        balls[i].p = rackPosition(queue: 0)
    }

    /// Launches the held (or ready) ball with an arena-space velocity.
    @discardableResult
    mutating func launch(velocity: SIMD3<Float>, power: Float) -> [LaneEvent] {
        guard let i = heldBall ?? readyBall else { return [] }
        balls[i].state = .flying
        balls[i].v = velocity
        balls[i].shotTime = time
        balls[i].touchedRim = false
        balls[i].touchedBoard = false
        balls[i].resolved = false
        // Backspin, like a real release.
        balls[i].spin = SIMD3(-14, velocity.x * 6, 0)
        return [.launch(ball: balls[i].id, power: power)]
    }

    /// Where the held/ready ball would leave from.
    var launchPoint: SIMD3<Float>? {
        guard let i = heldBall ?? readyBall else { return nil }
        return balls[i].p
    }

    // MARK: Simulation

    @discardableResult
    mutating func step(dt: Float) -> [LaneEvent] {
        var events: [LaneEvent] = []
        var remaining = min(dt, 0.1)
        while remaining > 1e-6 {
            let h = min(Self.substep, remaining)
            remaining -= h
            time += Double(h)
            for i in balls.indices { integrate(i, h: h, events: &events) }
            collideBalls(&events)
        }
        refill(&events)
        return events
    }

    private mutating func integrate(_ i: Int, h: Float, events: inout [LaneEvent]) {
        var b = balls[i]
        switch b.state {
        case .racked:
            // Settle toward the assigned rack spot.
            if let q = queueIndex(of: i) {
                let target = rackPosition(queue: q)
                b.p += (target - b.p) * min(1, h * 14)
            }
            balls[i] = b
            return
        case .held:
            return
        case .flying, .returning:
            break
        }
        let r = Arena.ballRadius
        let prev = b.p
        b.v.y -= Arena.gravity * h
        let onFloor = b.p.y <= r + 0.002
        if b.state == .returning && onFloor {
            b.v.z += Self.rampAcceleration * h
            b.v.x += (-b.p.x * 3.2 - b.v.x * 0.8) * h     // the lane funnels back to the middle
        }
        if time < b.inNetUntil {
            // The net catches the ball: drag and pull to the middle so it drops through.
            let c = rimCenter
            b.v.x += ((c.x - b.p.x) * 40 - b.v.x * 6) * h
            b.v.z += ((c.z - b.p.z) * 40 - b.v.z * 6) * h
            b.v.y *= 1 - 2.2 * h
        }
        b.p += b.v * h

        // Floor.
        if b.p.y < r {
            b.p.y = r
            if b.v.y < 0 {
                let impact = -b.v.y
                b.v.y = impact > 0.08 ? impact * Self.floorRestitution : 0
                b.v.x *= 0.96; b.v.z *= 0.96
                b.spin *= 0.8
                if impact > 0.12 && time - b.lastBounce > 0.06 {
                    events.append(.floor(ball: b.id, speed: impact))
                    b.lastBounce = time
                }
                if b.state == .flying && !b.resolved {
                    b.resolved = true
                    events.append(.miss(ball: b.id))
                }
                if b.state == .flying { b.state = .returning; b.returningSince = time }
            }
            if b.v.y == 0 { b.v.x *= 1 - 0.6 * h; b.v.z *= 1 - (b.state == .returning ? 0.2 : 0.6) * h }
        }
        // Side walls and the far end behind the shooter.
        let hw = slot.halfWidth - r
        if abs(b.p.x) > hw {
            let speed = abs(b.v.x)
            b.p.x = max(-hw, min(hw, b.p.x))
            if b.p.x * b.v.x > 0 { b.v.x = -b.v.x * 0.55 }
            if speed > 0.2 { events.append(.wall(ball: b.id, speed: speed)) }
        }
        let back = slot.depth + 0.3
        if b.p.z > back { b.p.z = back; if b.v.z > 0 { b.v.z = -b.v.z * 0.4 } }
        // Physical glass.
        for w in slot.walls {
            let d = w.distance(b.p)
            if d < r {
                b.p += w.normal * (r - d)
                let vn = simd_dot(b.v, w.normal)
                if vn < 0 {
                    b.v -= (1 + Self.glassRestitution) * vn * w.normal
                    if -vn > 0.15 { events.append(.glass(ball: b.id, speed: -vn)) }
                }
            }
        }
        // Backboard (a thin box in front of the plane x/y range).
        let lo = SIMD3<Float>(slide - Arena.boardHalfWidth, Arena.boardBottom, boardZ - Arena.boardThickness)
        let hi = SIMD3<Float>(slide + Arena.boardHalfWidth, Arena.boardTop, boardZ)
        let q = simd_clamp(b.p, lo, hi)
        let dq = b.p - q
        let dist = simd_length(dq)
        if dist < r {
            let n = dist > 1e-5 ? dq / dist : SIMD3<Float>(0, 0, 1)
            b.p = q + n * r
            let vn = simd_dot(b.v, n)
            if vn < 0 {
                b.v -= (1 + Self.boardRestitution) * vn * n
                b.touchedBoard = b.touchedBoard || b.state == .flying
                if -vn > 0.1 { events.append(.board(ball: b.id, speed: -vn)) }
            }
        }
        // Rim: a torus around the vertical axis through the rim centre.
        let c = rimCenter
        let rel = b.p - c
        let radial = (rel.x * rel.x + rel.z * rel.z).squareRoot()
        let ring = radial > 1e-5 ? c + SIMD3(rel.x / radial, 0, rel.z / radial) * Arena.rimRadius : c + SIMD3(Arena.rimRadius, 0, 0)
        let dr = b.p - ring
        let dRing = simd_length(dr)
        let reach = r + Arena.rimTube
        if dRing < reach {
            let n = dRing > 1e-5 ? dr / dRing : SIMD3<Float>(0, 1, 0)
            b.p = ring + n * reach
            let vn = simd_dot(b.v, n)
            if vn < 0 {
                let tangential = b.v - vn * n
                b.v = tangential * 0.86 - Self.rimRestitution * vn * n
                if b.state == .flying { b.touchedRim = true }
                if -vn > 0.06 { events.append(.rim(ball: b.id, speed: -vn)) }
                b.spin += SIMD3(n.z, 0, -n.x) * 8
            }
        }
        // Net: below the rim the ball stays inside the cord.
        let netTop = c.y, netBottom = c.y - Arena.netDepth
        if b.p.y < netTop && b.p.y > netBottom && prev.y >= netBottom {
            let rel2 = b.p - c
            let rad2 = (rel2.x * rel2.x + rel2.z * rel2.z).squareRoot()
            let inner = Arena.rimRadius - Arena.rimTube - r * 0.35
            if prev.y >= netTop - 0.001 || time < b.inNetUntil {
                if rad2 > inner && rad2 < Arena.rimRadius + r {
                    let k = inner / rad2
                    b.p.x = c.x + rel2.x * k
                    b.p.z = c.z + rel2.z * k
                }
            }
        }
        // Basket: the centre crosses the rim plane downward inside the ring.
        if b.state == .flying && !b.resolved && prev.y >= c.y && b.p.y < c.y && b.v.y < 0 {
            let t = (prev.y - c.y) / max(prev.y - b.p.y, 1e-6)
            let x = prev + (b.p - prev) * t
            let rad = ((x.x - c.x) * (x.x - c.x) + (x.z - c.z) * (x.z - c.z)).squareRoot()
            if rad < Arena.rimRadius - Arena.rimTube {
                b.resolved = true
                b.inNetUntil = time + 0.32
                events.append(.score(ball: b.id, swish: !b.touchedRim && !b.touchedBoard, bank: b.touchedBoard))
            }
        }
        // A shot that never comes down (stuck on the rim, say) still ends.
        if b.state == .flying && time - b.shotTime > Self.shotTimeout {
            if !b.resolved { b.resolved = true; events.append(.miss(ball: b.id)) }
            b.state = .returning
            b.returningSince = time
        }
        if b.state == .flying && b.resolved && time > b.inNetUntil && b.p.y < c.y - Arena.netDepth {
            b.state = .returning
            b.returningSince = time
        }
        b.spin *= 1 - 0.3 * h
        balls[i] = b
    }

    private mutating func collideBalls(_ events: inout [LaneEvent]) {
        let r = Arena.ballRadius
        for i in balls.indices where balls[i].state == .flying || balls[i].state == .returning {
            for j in balls.indices where j != i && (j > i || balls[j].state == .held || (balls[j].state == .racked && balls[i].state == .flying)) {
                let d = balls[i].p - balls[j].p
                let dist = simd_length(d)
                guard dist < 2 * r, dist > 1e-5 else { continue }
                let n = d / dist
                let movable = balls[j].state == .flying || balls[j].state == .returning
                let push = 2 * r - dist
                if movable {
                    balls[i].p += n * push / 2
                    balls[j].p -= n * push / 2
                    let rel = simd_dot(balls[i].v - balls[j].v, n)
                    if rel < 0 {
                        let imp = -(1 + 0.8) * rel / 2
                        balls[i].v += n * imp
                        balls[j].v -= n * imp
                    }
                } else {
                    balls[i].p += n * push
                    let rel = simd_dot(balls[i].v, n)
                    if rel < 0 { balls[i].v -= (1 + 0.5) * rel * n }
                }
            }
        }
    }

    /// Balls back at the shooter's end go into the rack queue.
    private mutating func refill(_ events: inout [LaneEvent]) {
        for i in balls.indices where balls[i].state == .returning {
            let b = balls[i]
            // Anywhere in the tray area counts as home: the ball joins the queue and rolls to its spot.
            let home = b.p.z >= rackZ - 0.15 && b.p.y < Arena.ballRadius + 0.03 && b.v.y <= 0.05
            let lost = time - b.returningSince > 2.5
            if home || lost {
                balls[i].state = .racked
                balls[i].v = .zero
                balls[i].spin = .zero
                if lost { balls[i].p = rackPosition(queue: Self.ballCount - 1) }
                events.append(.reracked(ball: b.id))
            }
        }
    }

    /// Queue position of a racked ball: racked balls in id order after the one on the spot.
    private func queueIndex(of i: Int) -> Int? {
        let racked = balls.indices.filter { balls[$0].state == .racked || balls[$0].state == .held }
        // The ball nearest the shooting spot keeps it.
        let spot = rackPosition(queue: 0)
        let ordered = racked.sorted { simd_distance(balls[$0].p, spot) < simd_distance(balls[$1].p, spot) }
        return ordered.firstIndex(of: i)
    }

    /// Puts every ball back in the rack (new round).
    mutating func reset() {
        for i in balls.indices {
            balls[i] = Ball(id: balls[i].id, p: rackPosition(queue: i))
        }
        slide = 0
    }
}
