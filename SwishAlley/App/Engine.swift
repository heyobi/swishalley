import SwiftUI
import SceneKit
import simd

enum TrackingState: Equatable { case off, needsPermission, denied, running, unavailable }
enum Screen: Equatable { case menu, playing, results }

struct Banner: Equatable, Identifiable {
    let id = UUID()
    var text: String
    var detail: String?
    var player: Int
    var hot: Bool
}

struct Results: Equatable {
    var mode: Mode
    var players: [PlayerScore]
    var best: Int
    var newBest: Bool
    var winner: Int?
}

/// Ties the game together: device geometry and the live hinge angle → layout (surfaces, lanes, interface),
/// finger flicks → shots, lane physics → rules, sound, haptics and effects, the camera → the viewer's eye.
/// One instance for the app, driven by GameView's display link.
@MainActor
final class Engine: ObservableObject {
    // Choices (persisted).
    @Published var themeID: String { didSet { save("theme", themeID); gym.setTheme(ArenaTheme.spec(themeID)) } }
    @Published var skinID: String { didSet { save("skin", skinID); gym.setSkin(BallSkin.spec(skinID)) } }
    @Published var trackID: String { didSet { save("track", trackID); if screen == .playing { playMusic() } } }
    @Published var musicOn: Bool { didSet { save("music", musicOn); playMusic() } }
    @Published var soundOn: Bool { didSet { save("sound", soundOn); Synth.shared.sfxVolume = soundOn ? 0.9 : 0 } }
    @Published var duelStyle: Mode = .duelRace

    // State for the interface.
    @Published private(set) var screen: Screen = .menu
    @Published private(set) var match: Match?
    @Published private(set) var results: Results?
    @Published private(set) var layout: SceneLayout?
    @Published private(set) var tracking: TrackingState = .off
    @Published private(set) var hasHinge = false
    @Published private(set) var shownHinge: Double?
    @Published private(set) var hingeClosed = false
    @Published var banners: [Banner] = []
    @Published var askReview = false
    @Published var pro = false
    @Published var shotSheet: SheetKind?
    @Published private(set) var diagnostics = ""

    // Debug / simulator / screenshot controls.
    @Published var hingeOverride: Double?
    @Published var simulateEye: SIMD3<Float>?
    @Published var attract = true
    /// Screenshot tour: stop physics and the clock (cameras and the hinge keep updating), keep banners up.
    var frozen = false
    var holdBanners = false
    /// Every raw hinge sample, for the simulator verification log.
    var onHingeSample: ((Double, Bool) -> Void)?

    let gym: Gym
    let tracker = FaceTracker()
    private(set) var lanes: [Lane] = []
    private var input = LayoutInput(size: .zero)
    private var hingeTarget: Double?
    private var hingeSpring = Spring1(110, omega: 14)
    private var viewers = ViewerTracker()
    private var eyeSmooth: Spring3?
    private var latestFrame: FaceTracker.Frame?
    private var frameConsumed = true
    private var time: Double = 0
    private var nextAttract: Double = 2
    private var resultsAt: Double?
    private var touches: [ObjectIdentifier: TouchTrack] = [:]
    private var eyes: [SIMD3<Float>] = []
    private let bests = Bests()

    private struct TouchTrack { var arena: Int; var viewport: Int; var samples: [TouchSample]; var holding: Bool }

    struct Geometry: Equatable {
        var size: CGSize = .zero
        var fold: CGRect?
        var insets = Insets()
        var isPad = false
        var nativeScale: CGFloat = 3
        var interface: UIInterfaceOrientation = .portrait
    }
    var geometry = Geometry() {
        didSet { if geometry.interface != oldValue.interface { tracker.setContext(interface: geometry.interface, key: contextKey) } }
    }

    init() {
        let d = UserDefaults.standard
        let theme = d.string(forKey: "theme") ?? "gym"
        let skin = d.string(forKey: "skin") ?? "classic"
        themeID = theme
        skinID = skin
        trackID = d.string(forKey: "track") ?? "neon"
        musicOn = d.object(forKey: "music") as? Bool ?? true
        soundOn = d.object(forKey: "sound") as? Bool ?? true
        gym = Gym(theme: ArenaTheme.spec(theme), skin: BallSkin.spec(skin))
        tracker.onFrame = { [weak self] f in self?.latestFrame = f; self?.frameConsumed = false; self?.diagnostics = f.diagnostics }
        tracker.onRunning = { [weak self] running in
            guard let self else { return }
            if running { self.tracking = .running } else if self.tracking == .running { self.tracking = .off }
        }
        refreshTrackingState()
    }

    private func save(_ key: String, _ value: Any) { UserDefaults.standard.set(value, forKey: key) }

    // MARK: Lifecycle

    func activate() {
        Synth.shared.start()
        Synth.shared.sfxVolume = soundOn ? 0.9 : 0
        playMusic()
        refreshTrackingState()
        if FaceTracker.authorized && UserDefaults.standard.object(forKey: "tracking") as? Bool ?? true && wantsTracking { tracker.start() }
    }

    func deactivate() {
        tracker.stop()
        Synth.shared.pause()
        if screen == .playing { pauseToMenu() }
    }

    private func playMusic() {
        guard musicOn else { Synth.shared.play(nil); return }
        Synth.shared.play(screen == .playing ? trackID : "lobby")
    }

    // MARK: Tracking

    private var wantsTracking: Bool { layout?.presentation != .duel && !(match?.mode.isDuel ?? false) }

    func refreshTrackingState() {
        if !FaceTracker.available { tracking = .unavailable }
        else if FaceTracker.denied { tracking = .denied }
        else if !FaceTracker.authorized { tracking = .needsPermission }
        else if tracking != .running { tracking = .off }
    }

    func enableTracking() {
        UserDefaults.standard.set(true, forKey: "tracking")
        if FaceTracker.authorized { tracker.start(); return }
        tracker.requestAccess { [weak self] ok in
            guard let self else { return }
            self.refreshTrackingState()
            if ok && self.wantsTracking { self.tracker.start() }
        }
    }

    func disableTracking() {
        UserDefaults.standard.set(false, forKey: "tracking")
        tracker.stop()
        tracking = .off
    }

    var trackingPreferred: Bool { UserDefaults.standard.object(forKey: "tracking") as? Bool ?? true }

    private var contextKey: String {
        if geometry.isPad { return "pad" }
        if hasHinge { return geometry.fold != nil ? "inner" : "outer" }
        return "phone"
    }

    // MARK: Hinge

    /// Every hinge sample (iPhone Duo, iOS 27.1). The angle is followed continuously, not just open/closed.
    func hingeChanged(angle: Double, closed: Bool) {
        if !hasHinge { hingeSpring = Spring1(Float(angle), omega: 14) }
        hasHinge = true
        onHingeSample?(angle, closed)
        hingeTarget = angle
        hingeClosed = closed
        tracker.setContext(interface: geometry.interface, key: contextKey)
    }

    /// Hinge samples arrive at the system's pace (about 10 a second in the simulator); a critically damped
    /// spring turns them into smooth motion without overshoot.
    private func smoothedHinge(dt: Float) -> Double? {
        if let o = hingeOverride { return o }
        guard let target = hingeTarget else { return nil }
        let v = hingeSpring.step(to: Float(target), dt: dt)
        return Double(v)
    }

    // MARK: Modes

    func start(_ mode: Mode) {
        if mode.isPro && !pro { shotSheet = .paywall; return }
        var m = Match(mode: mode)
        _ = m.update(dt: 0)
        match = m
        results = nil
        resultsAt = nil
        screen = .playing
        banners = []
        input.duel = mode.isDuel
        rebuildLayout(force: true)
        for i in lanes.indices { lanes[i].reset() }
        if mode.isDuel { tracker.stop() } else if FaceTracker.authorized && trackingPreferred { tracker.start() }
        playMusic()
        Haptics.shared.tap()
        Synth.shared.sfx(.chime, freq: 660, vel: 0.4, dur: 0.3)
    }

    func pauseToMenu() {
        match = nil
        screen = .menu
        input.duel = false
        rebuildLayout(force: true)
        playMusic()
        if FaceTracker.authorized && trackingPreferred { tracker.start() }
    }

    func playAgain() {
        if let m = results?.mode ?? match?.mode { start(m) }
    }

    func closeResults() {
        results = nil
        pauseToMenu()
    }

    // MARK: Layout

    private func rebuildLayout(force: Bool = false) {
        var i = input
        i.size = geometry.size
        i.fold = geometry.fold
        i.insets = geometry.insets
        i.isPad = geometry.isPad
        i.nativeScale = geometry.nativeScale
        i.hinge = shownHinge
        i.closed = hingeClosed && hingeOverride == nil
        guard force || i != input || layout == nil else { return }
        input = i
        guard let l = Layout.make(i) else { return }
        let structural = layout.map { !$0.sameStructure(as: l) } ?? true
        layout = l
        gym.configure(l)
        if structural || lanes.count != l.arenas.count {
            lanes = l.arenas.map { Lane(slot: $0) }
            touches = [:]
            eyeSmooth = nil
            viewers.reset()
        } else {
            for k in lanes.indices { lanes[k].slot = l.arenas[k] }
        }
    }

    // MARK: Frame

    func tick(t: Double, dt: Float) {
        time = t
        let h = smoothedHinge(dt: dt)
        if let h, abs((shownHinge ?? -1) - h) > 0.02 { shownHinge = h }
        rebuildLayout()
        guard let l = layout else { return }

        if frozen {
            eyes = l.viewports.map { vp in eye(for: vp, layout: l, t: t, dt: dt) }
            gym.updateCameras(eyes: eyes)
            gym.update(lanes: lanes, fire: lanes.map { match?.players[safe: $0.slot.player]?.onFire ?? false }, t: t, dt: 0)
            return
        }
        // Rules.
        if var m = match {
            let evs = m.update(dt: Double(dt))
            match = m
            for e in evs { handle(e) }
            for k in lanes.indices { lanes[k].slide = m.hoopSlide(player: lanes[k].slot.player) }
            if m.phase == .over && results == nil {
                if resultsAt == nil { resultsAt = t + 1.6 }
                if let at = resultsAt, t >= at { finish() }
            }
        } else if attract && screen == .menu && !lanes.isEmpty, t >= nextAttract {
            nextAttract = t + 2.8
            demoShot(lane: 0)
        }

        // Physics.
        for k in lanes.indices {
            let evs = lanes[k].step(dt: dt)
            for e in evs { handle(e, arena: k) }
        }

        // Eyes and cameras.
        eyes = l.viewports.map { vp in eye(for: vp, layout: l, t: t, dt: dt) }
        gym.updateCameras(eyes: eyes)
        let fire = lanes.map { lane in match?.players[safe: lane.slot.player]?.onFire ?? false }
        gym.update(lanes: lanes, fire: fire, t: t, dt: dt)
        let hot = (match?.isFinalStretch ?? false) || fire.contains(true)
        Synth.shared.energy = hot ? 1 : 0
    }

    private func eye(for vp: Viewport, layout l: SceneLayout, t: Double, dt: Float) -> SIMD3<Float> {
        let slot = l.arenas[vp.arena]
        if l.presentation == .duel { return slot.eye }
        var target = slot.eye
        if let sim = simulateEye {
            target = sim / l.metresPerUnit
        } else if tracking == .running {
            if let f = latestFrame, !frameConsumed {
                frameConsumed = true
                let dets = f.faces.map { box -> Detection in
                    Detection(position: worldEye(fromCamera: f.camera.position(of: box), layout: l), looking: abs(box.yaw ?? 0) < 0.42)
                }
                _ = viewers.update(dets, t: f.time)
            }
            if let p = viewers.primary, p.confirmed { target = p.position }
        }
        var s = eyeSmooth ?? Spring3(target, omega: 10)
        if vp == l.viewports.first {
            _ = s.step(to: target, dt: dt)
            eyeSmooth = s
        }
        return s.value
    }

    /// Where the front camera is in window points: the middle of the edge with the deepest safe-area inset,
    /// top middle when there is none (under-display cameras, iPad).
    private func cameraPoint() -> CGPoint {
        let g = geometry
        let i = g.insets
        let m = max(i.top, i.bottom, i.left, i.right)
        if m < 1 || m == i.top { return CGPoint(x: g.size.width / 2, y: max(4, i.top * 0.5)) }
        if m == i.bottom { return CGPoint(x: g.size.width / 2, y: g.size.height - i.bottom * 0.5) }
        if m == i.left { return CGPoint(x: i.left * 0.5, y: g.size.height / 2) }
        return CGPoint(x: g.size.width - i.right * 0.5, y: g.size.height / 2)
    }

    /// A camera-relative face position (metres) in world units.
    private func worldEye(fromCamera local: SIMD3<Float>, layout l: SceneLayout) -> SIMD3<Float> {
        let c = cameraPoint()
        let vp = l.viewports.first { $0.rect.contains(c) } ?? l.viewports[0]
        let u = Float((c.x - vp.rect.minX) / max(vp.rect.width, 1))
        let v = Float(1 - (c.y - vp.rect.minY) / max(vp.rect.height, 1))
        return CameraMount.eye(local / l.metresPerUnit, on: vp.surface, u: u, v: v)
    }

    // MARK: Touches

    func touchBegan(_ id: ObjectIdentifier, at p: CGPoint, t: Double) {
        guard let l = layout, screen == .playing, let m = match else { return }
        guard let arena = l.hud.shootZones.firstIndex(where: { $0.contains(p) }), arena < lanes.count,
              m.canShoot(lanes[arena].slot.player) else { return }
        guard let vpIndex = l.viewports.lastIndex(where: { $0.arena == arena && $0.rect.contains(p) }) else { return }
        // One finger per lane.
        if touches.values.contains(where: { $0.arena == arena }) { return }
        var holding = false
        if let x = sideways(p, viewport: vpIndex, arena: arena) { holding = lanes[arena].hold(sideways: x * 0.4) }
        touches[id] = TouchTrack(arena: arena, viewport: vpIndex, samples: [TouchSample(t: t, p: p)], holding: holding)
    }

    func touchMoved(_ id: ObjectIdentifier, at p: CGPoint, t: Double) {
        guard var tr = touches[id] else { return }
        tr.samples.append(TouchSample(t: t, p: p))
        if tr.samples.count > 24 { tr.samples.removeFirst(tr.samples.count - 24) }
        touches[id] = tr
        if tr.holding, let x = sideways(p, viewport: tr.viewport, arena: tr.arena) { lanes[tr.arena].moveHeld(sideways: x * 0.4) }
    }

    func touchEnded(_ id: ObjectIdentifier, at p: CGPoint, t: Double) {
        guard var tr = touches.removeValue(forKey: id), let l = layout else { return }
        tr.samples.append(TouchSample(t: t, p: p))
        let k = tr.arena
        guard k < lanes.count, var m = match, m.canShoot(lanes[k].slot.player),
              let vel = Flick.velocity(tr.samples), let from = lanes[k].launchPoint else {
            if tr.arena < lanes.count { lanes[tr.arena].cancelHold() }
            return
        }
        let vp = l.viewports[tr.viewport]
        let eye = tr.viewport < eyes.count ? eyes[tr.viewport] : l.arenas[k].eye
        if let shot = Flick.shot(release: p, velocity: vel, viewport: vp, eye: eye, placement: l.arenas[k].placement,
                                 from: from, target: lanes[k].rimCenter, ceiling: lanes[k].ceiling, pointsPerMetre: l.pointsPerMetre) {
            let evs = lanes[k].launch(velocity: shot.velocity, power: shot.power)
            m.shot(player: lanes[k].slot.player)
            match = m
            for e in evs { handle(e, arena: k) }
        } else {
            lanes[k].cancelHold()
        }
    }

    func touchCancelled(_ id: ObjectIdentifier) {
        guard let tr = touches.removeValue(forKey: id), tr.arena < lanes.count else { return }
        lanes[tr.arena].cancelHold()
    }

    private func sideways(_ p: CGPoint, viewport: Int, arena: Int) -> Float? {
        guard let l = layout, viewport < l.viewports.count else { return nil }
        let eye = viewport < eyes.count ? eyes[viewport] : l.arenas[arena].eye
        return Flick.lanePoint(p, in: l.viewports[viewport], eye: eye, placement: l.arenas[arena].placement, height: Arena.ballRadius)?.x
    }

    /// A clean demo shot (menus and screenshots).
    func demoShot(lane k: Int, factor: Float = Float.random(in: 0.98...1.02), aim: Float = 0) {
        guard k < lanes.count, var v = lanes[k].idealLaunch() else { return }
        v.x += aim
        v *= factor
        let evs = lanes[k].launch(velocity: v, power: factor)
        for e in evs { handle(e, arena: k) }
    }

    // MARK: Events

    private var playerCount: Int { match?.players.count ?? 1 }

    private func handle(_ e: LaneEvent, arena k: Int) {
        let player = k < lanes.count ? lanes[k].slot.player : 0
        let pan: Float = layout?.presentation == .duel ? (player == 0 ? -0.3 : 0.3) : 0
        let quiet: Float = screen == .menu ? 0.45 : 1
        switch e {
        case .launch(_, let power):
            Synth.shared.sfx(.whoosh, freq: 1, vel: 0.18 * quiet, pan: pan, dur: 0.16)
            if screen == .playing { Haptics.shared.launch(power) }
        case .floor(_, let speed):
            Synth.shared.sfx(.bounce, freq: 92 + Float.random(in: -6...6), vel: min(1, 0.25 + speed * 0.5) * quiet, pan: pan, dur: 0.12)
            if screen == .playing { Haptics.shared.bounce(speed) }
        case .rim(_, let speed):
            Synth.shared.sfx(.rim, freq: 540 + Float.random(in: -30...30), vel: min(1, 0.3 + speed * 0.6) * quiet, pan: pan, dur: 0.5)
            gym.rattle(arena: k, strength: min(1, speed))
            if screen == .playing { Haptics.shared.rim(speed) }
        case .board(_, let speed):
            Synth.shared.sfx(.board, freq: 130, vel: min(1, 0.3 + speed * 0.5) * quiet, pan: pan, dur: 0.15)
            gym.flashBoard(arena: k)
            if screen == .playing { Haptics.shared.board(speed) }
        case .glass(_, let speed):
            Synth.shared.sfx(.glass, freq: 260, vel: min(1, 0.3 + speed * 0.5) * quiet, pan: pan, dur: 0.15)
            if screen == .playing { Haptics.shared.glass(speed) }
        case .wall(_, let speed):
            Synth.shared.sfx(.board, freq: 180, vel: min(0.6, 0.15 + speed * 0.3) * quiet, pan: pan, dur: 0.1)
        case .score(_, let swish, _):
            Synth.shared.sfx(.swish, freq: swish ? 3000 : 2200, vel: (swish ? 0.95 : 0.7) * quiet, pan: pan, dur: 0.3)
            gym.swish(arena: k, strength: swish ? 1 : 0.7)
            let rim = k < lanes.count ? lanes[k].rimCenter : SIMD3(0, Arena.rimHeight, 0.1)
            let theme = ArenaTheme.spec(themeID)
            gym.burst(arena: k, at: rim, count: swish ? 22 : 12, colors: [theme.neonA, theme.neonB, 0xffffff], t: time)
            guard screen == .playing, var m = match else { break }
            Haptics.shared.swish()
            let evs = m.basket(player: player, swish: swish)
            match = m
            for me in evs { handle(me) }
        case .miss:
            guard screen == .playing, var m = match else { break }
            let evs = m.miss(player: player)
            match = m
            for me in evs { handle(me) }
        case .reracked:
            Synth.shared.sfx(.tick, freq: 1400, vel: 0.12 * quiet, pan: pan, dur: 0.02)
        }
    }

    private func handle(_ e: MatchEvent) {
        switch e {
        case .go:
            Synth.shared.sfx(.buzzer, freq: 440, vel: 0.5, dur: 0.25)
            show(String(localized: "Go!"), player: -1)
        case .turn(let p):
            show(String(localized: "Your turn"), detail: playerName(p), player: p)
            Synth.shared.sfx(.chime, freq: 784, vel: 0.5, dur: 0.3)
        case .finalStretch:
            show(String(localized: "Double points!"), detail: String(localized: "The hoop is on the move"), player: -1, hot: true)
            Synth.shared.sfx(.whoosh, freq: 1, vel: 0.6, dur: 0.6)
            Haptics.shared.fire()
        case .secondTick(let left):
            Synth.shared.sfx(.tick, freq: left == 1 ? 1760 : 1320, vel: 0.5, dur: 0.03)
        case .buzzer:
            Synth.shared.sfx(.buzzer, freq: 196, vel: 0.85, dur: 0.9)
            Haptics.shared.buzzer()
        case .basket(let p, let points, let swish, let onFire, let double):
            var detail: [String] = []
            if swish { detail.append(String(localized: "Swish")) }
            if onFire { detail.append(String(localized: "On fire")) }
            if double { detail.append(String(localized: "Double")) }
            show("+\(points)", detail: detail.isEmpty ? nil : detail.joined(separator: " · "), player: p, hot: onFire || double)
            let base: Float = 523.25 * pow(2, Float(min(points, 12)) / 12)
            Synth.shared.sfx(.chime, freq: base, vel: 0.35, dur: 0.4)
            if swish { Synth.shared.sfx(.chime, freq: base * 1.5, vel: 0.25, dur: 0.4) }
        case .fireOn(let p):
            show(String(localized: "On fire!"), detail: String(localized: "Baskets worth 3"), player: p, hot: true)
            Synth.shared.sfx(.whoosh, freq: 1, vel: 0.7, dur: 0.7)
            Haptics.shared.fire()
        case .fireOff:
            Synth.shared.sfx(.tick, freq: 300, vel: 0.3, dur: 0.06)
        }
    }

    func playerName(_ p: Int) -> String {
        p == 0 ? String(localized: "Player 1") : String(localized: "Player 2")
    }

    private func show(_ text: String, detail: String? = nil, player: Int, hot: Bool = false) {
        let b = Banner(text: text, detail: detail, player: player, hot: hot)
        banners.append(b)
        if banners.count > 3 { banners.removeFirst() }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            if !self.holdBanners { self.banners.removeAll { $0.id == b.id } }
        }
    }

    private func finish() {
        guard let m = match else { return }
        let score = m.players.first?.points ?? 0
        let previous = bests.best(m.mode)
        let newBest = !ShotsTour.active && bests.record(m.mode, score: score)
        ReviewGate.roundPlayed()
        results = Results(mode: m.mode, players: m.players, best: max(previous, newBest ? score : previous), newBest: newBest, winner: m.winner)
        screen = .results
        Synth.shared.energy = 0
        if newBest {
            Synth.shared.sfx(.chime, freq: 784, vel: 0.5, dur: 0.6)
            Synth.shared.sfx(.chime, freq: 1046.5, vel: 0.45, dur: 0.8)
            if ReviewGate.shouldAsk(afterBest: true) {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    self.askReview = true
                }
            }
        }
    }

    /// Screenshot tour helpers.
    func setResults(_ r: Results) { results = r; screen = .results }
    func injectMatch(_ m: Match) { match = m }
    func showBanner(_ text: String, detail: String?, player: Int, hot: Bool) { show(text, detail: detail, player: player, hot: hot) }
    /// Runs physics and rules for a while without waiting for frames (screenshot set-up).
    func advance(seconds: Double) {
        var left = seconds
        while left > 0 {
            let dt = Float(min(1.0 / 60, left))
            frozen = false
            tick(t: time + Double(dt), dt: dt)
            left -= Double(dt)
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
