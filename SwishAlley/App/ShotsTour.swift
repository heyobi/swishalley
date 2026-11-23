import SwiftUI
import simd

/// App Store screenshot tour and simulator verification, only when launched with `-shots`
/// (scripts/sim-shots.sh). Each scene is set up, frozen, and its name written to Documents/shots/ready; the
/// script takes the screenshot and answers in Documents/shots/next. A name ending in "@<degrees>" asks the
/// script to put the iPhone Duo simulator's hinge at that angle first ("@sweep": sweep it back and forth and
/// take no picture). The tour logs every hinge sample and the geometry derived from it to hinge-log.txt, and
/// writes <name>.json (eye, hinge, window, fold) for the half-open composer.
@MainActor
struct ShotsTour {
    nonisolated static var active: Bool { ProcessInfo.processInfo.arguments.contains("-shots") }
    nonisolated static var inner: Bool { ProcessInfo.processInfo.arguments.contains("-shotsInner") }
    nonisolated static var foldGuide: Bool { ProcessInfo.processInfo.arguments.contains("-foldGuide") }

    let engine: Engine

    private var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("shots")
    }

    func run() async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("next"))
        engine.attract = false
        engine.holdBanners = true
        engine.musicOn = true
        try? await Task.sleep(for: .seconds(3))

        if Self.inner {
            orient(.portrait)
            try? await Task.sleep(for: .seconds(2))
            await probe()
            await stageShot("1-stage@112", hinge: 112, eye: SIMD3(0.015, 0.215, 0.36), theme: "gym", points: [24], streak: [1], time: 38,
                            shots: [(0, 0.42)], banner: nil)
            await stageShot("2-fire@124", hinge: 124, eye: SIMD3(-0.03, 0.2, 0.35), theme: "gym", points: [41], streak: [4], time: 22,
                            shots: [(0, 0.5)], banner: (String(localized: "On fire!"), String(localized: "Baskets worth 3")))
            await stageShot("3-final@98", hinge: 98, eye: SIMD3(0.04, 0.21, 0.37), theme: "cabinet", points: [58], streak: [2], time: 7,
                            shots: [(0, 0.36)], banner: (String(localized: "Double points!"), String(localized: "The hoop is on the move")))
            await duelShot("4-duel@180", theme: "gym")
            await menuShot("5-menu@108", hinge: 108)
        } else {
            await windowShot("1-play", theme: "gym", points: [26], streak: [1], time: 41, flight: 0.4, banner: nil)
            await windowShot("2-fire", theme: "rooftop", points: [44], streak: [4], time: 19, flight: 0.5,
                             banner: (String(localized: "On fire!"), String(localized: "Baskets worth 3")))
            await duelShot("3-duel", theme: "pier")
            await resultsShot("4-results")
            engine.pauseToMenu()
            engine.shotSheet = .locker
            await step("5-locker")
            engine.shotSheet = nil
            try? await Task.sleep(for: .seconds(1))
        }
        engine.pauseToMenu()
        engine.shotSheet = .paywall
        await step("6-paywall")
        engine.shotSheet = nil
        write("ready", "done")
    }

    // MARK: Verification on the iPhone Duo simulator

    /// Logs each hinge sample while the script sweeps the hinge, with what the layout made of it: the angle
    /// between the halves, the fold frame, where the rim's back edge is relative to the crease.
    private func probe() async {
        var lines: [String] = []
        let start = Date()
        engine.hingeOverride = nil
        engine.onHingeSample = { angle, closed in
            let l = engine.layout
            let g = engine.geometry
            var line = String(format: "t=%.3f angle=%.2f closed=%d", Date().timeIntervalSince(start), angle, closed ? 1 : 0)
            if let f = g.fold { line += String(format: " fold=[%.1f,%.1f,%.1f,%.1f]", f.minX, f.minY, f.width, f.height) }
            line += String(format: " window=[%.0f,%.0f]", g.size.width, g.size.height)
            if let l {
                line += " presentation=\(l.presentation.rawValue)"
                if l.viewports.count == 2, l.presentation == .stage {
                    let up = l.viewports[0].surface, low = l.viewports[1].surface
                    let between = acos(max(-1, min(1, simd_dot(up.vu, -low.vu)))) * 180 / .pi
                    line += String(format: " halves=%.2f° shown=%.2f°", between, l.hinge)
                    let a = l.arenas[0]
                    let rimBack = Arena.rimCenter(back: a.crease + a.setback).z - Arena.rimRadius - Arena.rimTube
                    line += String(format: " crease=%.4f rimBack=%.4f setback=%.4f", a.crease, rimBack, a.setback)
                }
            }
            lines.append(line)
        }
        await step("0-probe@sweep", settle: false)
        try? await Task.sleep(for: .seconds(1.5))
        engine.onHingeSample = nil
        write("hinge-log.txt", lines.joined(separator: "\n"))
    }

    // MARK: Scenes

    private func prepare(_ mode: Mode, theme: String, points: [Int], streak: [Int], time: Double) async {
        engine.frozen = false
        engine.banners = []
        engine.themeID = theme
        engine.start(mode)
        try? await Task.sleep(for: .seconds(0.6))
        var m = engine.match ?? Match(mode: mode)
        m.showcase(points: points, baskets: points.map { $0 / 2 - 2 }, streak: streak, timeLeft: time)
        engine.injectMatch(m)
    }

    /// Lets the lane run until a demo shot is `flight` seconds into the air, then freezes.
    private func shoot(lane: Int, flight: Double, aim: Float = 0) {
        engine.demoShot(lane: lane, factor: 1, aim: aim)
        engine.advance(seconds: flight)
        engine.frozen = true
    }

    private func stageShot(_ name: String, hinge: Double, eye: SIMD3<Float>, theme: String, points: [Int], streak: [Int], time: Double,
                           shots: [(Int, Double)], banner: (String, String)?) async {
        engine.hingeOverride = hinge
        engine.simulateEye = eye
        await prepare(.classic, theme: theme, points: points, streak: streak, time: time)
        try? await Task.sleep(for: .seconds(1.2))
        engine.advance(seconds: 0.5)
        for (lane, flight) in shots { shoot(lane: lane, flight: flight) }
        if let b = banner { engine.showBanner(b.0, detail: b.1, player: -1, hot: true) }
        try? await Task.sleep(for: .seconds(1))
        writeGeometry(name: String(name.split(separator: "@")[0]), eye: eye, hinge: hinge)
        await step(name, settle: false)
    }

    private func windowShot(_ name: String, theme: String, points: [Int], streak: [Int], time: Double, flight: Double, banner: (String, String)?) async {
        engine.simulateEye = nil
        await prepare(.classic, theme: theme, points: points, streak: streak, time: time)
        try? await Task.sleep(for: .seconds(1))
        engine.advance(seconds: 0.5)
        shoot(lane: 0, flight: flight)
        if let b = banner { engine.showBanner(b.0, detail: b.1, player: -1, hot: true) }
        await step(name)
    }

    private func duelShot(_ name: String, theme: String) async {
        engine.hingeOverride = Self.inner ? 180 : nil
        engine.simulateEye = nil
        await prepare(.duelRace, theme: theme, points: [16, 14], streak: [2, 3], time: 23)
        try? await Task.sleep(for: .seconds(1.2))
        engine.advance(seconds: 0.4)
        engine.demoShot(lane: 0, factor: 1)
        engine.advance(seconds: 0.15)
        engine.demoShot(lane: 1, factor: 1, aim: 0.02)
        engine.advance(seconds: 0.32)
        engine.frozen = true
        writeGeometry(name: String(name.split(separator: "@")[0]), eye: SIMD3(0, Layout.duelEyeHeight, 0.3), hinge: 180)
        await step(name)
    }

    private func menuShot(_ name: String, hinge: Double) async {
        engine.frozen = false
        engine.hingeOverride = hinge
        engine.simulateEye = SIMD3(0, 0.21, 0.36)
        engine.pauseToMenu()
        engine.themeID = "gym"
        engine.attract = true
        try? await Task.sleep(for: .seconds(1.5))
        engine.demoShot(lane: 0, factor: 1)
        engine.advance(seconds: 0.45)
        engine.frozen = true
        engine.attract = false
        writeGeometry(name: String(name.split(separator: "@")[0]), eye: SIMD3(0, 0.21, 0.36), hinge: hinge)
        await step(name, settle: false)
        engine.frozen = false
    }

    private func resultsShot(_ name: String) async {
        engine.frozen = false
        engine.banners = []
        engine.pauseToMenu()
        engine.start(.classic)
        try? await Task.sleep(for: .seconds(0.5))
        var p = PlayerScore()
        p.points = 72; p.baskets = 27; p.shots = 34; p.swishes = 9; p.bestStreak = 11
        engine.setResults(Results(mode: .classic, players: [p], best: 72, newBest: true, winner: nil))
        engine.frozen = true
        await step(name)
        engine.frozen = false
    }

    private func writeGeometry(name: String, eye: SIMD3<Float>, hinge: Double) {
        let g = engine.geometry
        let fold = g.fold ?? .zero
        var json = String(format: "{\"hinge\":%.2f,\"eye\":[%.4f,%.4f,%.4f],\"size\":[%.1f,%.1f],\"fold\":[%.1f,%.1f,%.1f,%.1f],\"scale\":%.2f",
                          hinge, eye.x, eye.y, eye.z, g.size.width, g.size.height, fold.minX, fold.minY, fold.width, fold.height, g.nativeScale)
        if let l = engine.layout {
            json += ",\"presentation\":\"\(l.presentation.rawValue)\",\"metresPerUnit\":\(l.metresPerUnit)"
            if l.presentation == .stage, l.viewports.count == 2 {
                let up = l.viewports[0].surface, low = l.viewports[1].surface
                let s = l.metresPerUnit
                json += String(format: ",\"upper\":[%.4f,%.4f],\"lower\":[%.4f,%.4f]", up.width * s, up.height * s, low.width * s, low.height * s)
            }
        }
        json += "}"
        write("\(name).json", json)
    }

    private func step(_ name: String, settle: Bool = true) async {
        if settle { try? await Task.sleep(for: .seconds(2)) }
        write("ready", name)
        for _ in 0..<1200 {
            if let s = try? String(contentsOf: dir.appendingPathComponent("next"), encoding: .utf8), s == name { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// The half-open stage needs the fold running across the window: on the Duo's inner display that is the
    /// tall ("portrait") window.
    private func orient(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private func write(_ file: String, _ text: String) {
        try? text.write(to: dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }
}
