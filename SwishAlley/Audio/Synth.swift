import AVFoundation

/// Synthesizer voices. Raw values index the render code's switch.
enum Voice: Int32, CaseIterable {
    // Music
    case kick = 0, snare, hat, clap, bass, keys, pad, lead, pluck
    // Effects
    case swish, rim, board, bounce, buzzer, chime, whoosh, tick, glass
}

/// One note of a piece, in beats from the start of its loop. Layer 1 notes play only when the game is hot
/// (final stretch or on fire); layer 0 always.
struct NoteEvent: Equatable {
    var beat: Double
    var dur: Double
    var freq: Float
    var vel: Float
    var voice: Voice
    var pan: Float
    var layer: Int32 = 0
}

/// Music and sound effects, synthesized on the device (no samples, nothing to license, no vocals). The render
/// block runs the sequencer sample-accurately. The main thread writes small values into `params` and pushes
/// one-shot effects into a ring buffer; the render block owns the voices.
final class Synth {
    static let shared = Synth()

    static let maxVoices = 40
    static let ksLength = 1024
    static let ringSize = 64

    struct Params {
        var track: Int32 = -1
        var playing: Int32 = 0
        var music: Float = 0.7
        var sfx: Float = 0.9
        var energy: Int32 = 0
        var beatOut: Double = 0
    }

    struct TrackInfo { var offset: Int32; var count: Int32; var loop: Double; var tempo: Double }
    struct Event { var beat: Double; var dur: Float; var freq: Float; var vel: Float; var voice: Int32; var pan: Float; var layer: Int32 }
    struct Cmd { var voice: Int32; var freq: Float; var vel: Float; var pan: Float; var dur: Float }

    struct V {
        var active: Int32 = 0
        var voice: Int32 = 0
        var freq: Float = 440
        var vel: Float = 0
        var panL: Float = 0.7, panR: Float = 0.7
        var t: Float = 0
        var dur: Float = 1
        var gate: Float = 1
        var release: Float = 0.999
        var p0: Float = 0, p1: Float = 0, p2: Float = 0, p3: Float = 0
        var a0: Float = 0, a1: Float = 0, a2: Float = 0, a3: Float = 0
        var k0: Float = 1, k1: Float = 1, k2: Float = 1, k3: Float = 1
        var f1: Float = 0, f2: Float = 0, f3: Float = 0
        var ksPos: Int32 = 0, ksLen: Int32 = 0
        var noise: UInt32 = 22_222
        var music: Int32 = 1
    }

    struct Seq { var current: Int32 = -1; var beat: Double = 0; var index: Int32 = 0 }

    let engine = AVAudioEngine()
    private var source: AVAudioSourceNode!
    private let reverb = AVAudioUnitReverb()
    private let eq = AVAudioUnitEQ(numberOfBands: 3)
    private let params: UnsafeMutablePointer<Params>
    private let voices: UnsafeMutablePointer<V>
    private let ks: UnsafeMutablePointer<Float>
    private let ring: UnsafeMutablePointer<Cmd>
    private let ringHead: UnsafeMutablePointer<Int32>
    private let ringTail: UnsafeMutablePointer<Int32>
    private let seq: UnsafeMutablePointer<Seq>
    private var events: UnsafeMutablePointer<Event>
    private var tracks: UnsafeMutablePointer<TrackInfo>
    private(set) var trackIDs: [String] = []
    private var started = false
    private(set) var lastError: String?

    init() {
        params = .allocate(capacity: 1); params.initialize(to: Params())
        voices = .allocate(capacity: Self.maxVoices); voices.initialize(repeating: V(), count: Self.maxVoices)
        ks = .allocate(capacity: Self.maxVoices * Self.ksLength); ks.initialize(repeating: 0, count: Self.maxVoices * Self.ksLength)
        ring = .allocate(capacity: Self.ringSize); ring.initialize(repeating: Cmd(voice: 0, freq: 0, vel: 0, pan: 0, dur: 0), count: Self.ringSize)
        ringHead = .allocate(capacity: 1); ringHead.initialize(to: 0)
        ringTail = .allocate(capacity: 1); ringTail.initialize(to: 0)
        seq = .allocate(capacity: 1); seq.initialize(to: Seq())
        var all: [Event] = []
        var infos: [TrackInfo] = []
        for t in Tracks.all {
            let evs = t.events.sorted { $0.beat < $1.beat }
            infos.append(TrackInfo(offset: Int32(all.count), count: Int32(evs.count), loop: t.loopBeats, tempo: t.tempo))
            for e in evs {
                all.append(Event(beat: e.beat, dur: Float(e.dur * 60 / t.tempo), freq: e.freq, vel: e.vel, voice: e.voice.rawValue, pan: e.pan, layer: e.layer))
            }
            trackIDs.append(t.id)
        }
        events = .allocate(capacity: max(1, all.count))
        events.initialize(from: all, count: all.count)
        tracks = .allocate(capacity: max(1, infos.count))
        tracks.initialize(from: infos, count: infos.count)
    }

    // MARK: Control (main thread)

    func play(_ id: String?) {
        if let id, let i = trackIDs.firstIndex(of: id) {
            params.pointee.track = Int32(i)
            params.pointee.playing = 1
        } else {
            params.pointee.playing = 0
        }
    }

    var energy: Int32 {
        get { params.pointee.energy }
        set { params.pointee.energy = newValue }
    }

    var musicVolume: Float {
        get { params.pointee.music }
        set { params.pointee.music = newValue }
    }

    var sfxVolume: Float {
        get { params.pointee.sfx }
        set { params.pointee.sfx = newValue }
    }

    var beat: Double? { params.pointee.playing == 1 ? params.pointee.beatOut : nil }

    /// A one-shot sound effect. `freq` in Hz.
    func sfx(_ v: Voice, freq: Float, vel: Float = 0.7, pan: Float = 0, dur: Float = 0.3) {
        let head = ringHead.pointee
        let next = (head + 1) % Int32(Self.ringSize)
        if next == ringTail.pointee { return }
        ring[Int(head)] = Cmd(voice: v.rawValue, freq: freq, vel: vel, pan: pan, dur: dur)
        ringHead.pointee = next
    }

    // MARK: Engine

    func start() {
        guard !started else { resume(); return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            lastError = "session: \(error.localizedDescription)"
        }
        let rate = session.sampleRate > 0 ? session.sampleRate : 48_000
        buildGraph(sampleRate: rate)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // Fall back to a dry chain (Pleats build 2 lesson: never stay silent).
            let first = "engine: \((error as NSError).code)"
            engine.stop()
            engine.disconnectNodeOutput(source)
            engine.disconnectNodeOutput(eq)
            engine.disconnectNodeOutput(reverb)
            engine.connect(source, to: engine.mainMixerNode, format: nil)
            engine.prepare()
            do { try engine.start(); lastError = first + " (dry)" } catch { lastError = first + ", dry \((error as NSError).code)" }
        }
        started = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            self?.resume()
        }
        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in self?.resume() }
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in self?.resume() }
    }

    func resume() {
        guard started, !engine.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        engine.prepare()
        try? engine.start()
    }

    func pause() { engine.pause() }

    private func buildGraph(sampleRate rate: Double) {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        source = AVAudioSourceNode(format: format, renderBlock: Self.makeRender(
            params: params, voices: voices, ks: ks, ring: ring, head: ringHead, tail: ringTail, seq: seq,
            events: events, tracks: tracks, trackCount: Int32(trackIDs.count), sampleRate: Float(rate)))
        engine.attach(source)
        engine.attach(eq)
        engine.attach(reverb)
        let bands: [(AVAudioUnitEQFilterType, Float, Float, Float)] = [(.highPass, 32, 0, 0.7), (.parametric, 300, -2, 1.1), (.highShelf, 9500, -2, 0.7)]
        for (i, b) in bands.enumerated() {
            eq.bands[i].filterType = b.0; eq.bands[i].frequency = b.1; eq.bands[i].gain = b.2; eq.bands[i].bandwidth = b.3; eq.bands[i].bypass = false
        }
        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = 14
        engine.connect(source, to: eq, format: format)
        engine.connect(eq, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
    }

    /// Offline rendering for tests (no audio hardware).
    func startOffline() throws {
        let out = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: out, maximumFrameCount: 4096)
        buildGraph(sampleRate: 48_000)
        engine.prepare()
        try engine.start()
        started = true
    }

    /// Renders `seconds` offline and returns (RMS, peak) of the left channel.
    func renderOffline(seconds: Double) throws -> (rms: Float, peak: Float) {
        let format = engine.manualRenderingFormat
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { return (0, 0) }
        var total: Double = 0
        var peak: Float = 0
        var n = 0
        var remaining = Int(seconds * format.sampleRate)
        while remaining > 0 {
            let frames = AVAudioFrameCount(min(4096, remaining))
            let status = try engine.renderOffline(frames, to: buf)
            guard status == .success, let d = buf.floatChannelData else { break }
            for i in 0..<Int(buf.frameLength) {
                let x = d[0][i]
                total += Double(x * x)
                peak = max(peak, abs(x))
            }
            n += Int(buf.frameLength)
            remaining -= Int(frames)
        }
        return (n > 0 ? Float(sqrt(total / Double(n))) : 0, peak)
    }

    // MARK: Render

    private static func makeRender(params: UnsafeMutablePointer<Params>, voices: UnsafeMutablePointer<V>,
                                   ks: UnsafeMutablePointer<Float>, ring: UnsafeMutablePointer<Cmd>,
                                   head: UnsafeMutablePointer<Int32>, tail: UnsafeMutablePointer<Int32>,
                                   seq: UnsafeMutablePointer<Seq>, events: UnsafeMutablePointer<Event>,
                                   tracks: UnsafeMutablePointer<TrackInfo>, trackCount: Int32,
                                   sampleRate sr: Float) -> AVAudioSourceNodeRenderBlock {
        let invSR = 1 / sr
        let twoPi: Float = 2 * .pi
        let maxVoices = Self.maxVoices
        let ksLength = Self.ksLength
        let ringSize = Self.ringSize

        func noise(_ v: inout V) -> Float {
            v.noise ^= v.noise << 13; v.noise ^= v.noise >> 17; v.noise ^= v.noise << 5
            return Float(Int32(bitPattern: v.noise)) / Float(Int32.max)
        }
        func decay(_ seconds: Float) -> Float { expf(-invSR / max(seconds, 0.0005)) }
        /// One-pole low-pass coefficient for a cutoff in Hz.
        func lpc(_ hz: Float) -> Float { 1 - expf(-twoPi * min(hz, sr * 0.45) * invSR) }

        func trigger(_ voice: Int32, freq: Float, vel: Float, pan: Float, dur: Float, music: Bool) {
            var slot = 0
            var oldest: Float = -1
            for i in 0..<maxVoices {
                if voices[i].active == 0 { slot = i; oldest = -2; break }
                if voices[i].t > oldest { oldest = voices[i].t; slot = i }
            }
            var v = V()
            v.active = 1
            v.voice = voice
            v.freq = freq
            v.vel = vel
            let p = max(-1, min(1, pan))
            v.panL = cosf((p + 1) * .pi / 4)
            v.panR = sinf((p + 1) * .pi / 4)
            v.dur = dur
            v.music = music ? 1 : 0
            v.noise = UInt32(truncatingIfNeeded: slot &* 2_654_435_761 &+ Int(freq * 7)) | 1
            switch Voice(rawValue: voice) ?? .tick {
            case .kick: v.a0 = 1; v.k0 = decay(0.28); v.f1 = 1; v.release = decay(0.05)
            case .snare: v.a0 = 1; v.a1 = 1; v.k0 = decay(0.07); v.k1 = decay(0.16); v.release = decay(0.05)
            case .hat: v.a0 = 1; v.k0 = decay(dur > 0.1 ? 0.22 : 0.035); v.release = decay(0.03)
            case .clap: v.a0 = 1; v.k0 = decay(0.16); v.release = decay(0.05)
            case .bass: v.a0 = 1; v.k0 = decay(0.5); v.release = decay(0.04)
            case .keys: v.a0 = 1; v.a1 = 1.8; v.a3 = 0.06; v.k0 = decay(1.6); v.k1 = decay(0.3); v.k3 = decay(0.05); v.release = decay(0.18)
            case .pad: v.a0 = 0; v.release = decay(0.7)
            case .lead: v.a0 = 1; v.release = decay(0.12)
            case .pluck:
                let len = Int32(max(8, min(Float(ksLength - 1), sr / freq)))
                v.ksLen = len
                let base = slot * ksLength
                var lp: Float = 0
                for i in 0..<Int(len) { let n = noise(&v); lp += (n - lp) * 0.6; ks[base + i] = lp * 0.9 }
                v.a0 = 1; v.k0 = 0.996; v.release = decay(0.1)
            case .swish: v.a0 = 1; v.k0 = decay(0.2); v.release = decay(0.08)
            case .rim: v.a0 = 1; v.a1 = 0.7; v.a2 = 0.45; v.a3 = 0.3; v.k0 = decay(0.55); v.k1 = decay(0.3); v.k2 = decay(0.16); v.k3 = decay(0.09); v.f1 = 1; v.release = decay(0.3)
            case .board: v.a0 = 1; v.a1 = 1; v.a2 = 0.25; v.k0 = decay(0.09); v.k1 = decay(0.025); v.k2 = decay(0.2); v.release = decay(0.08)
            case .bounce: v.a0 = 1; v.a1 = 1; v.k0 = decay(0.13); v.k1 = decay(0.02); v.f1 = 1; v.release = decay(0.08)
            case .buzzer: v.a0 = 1; v.k0 = 1; v.release = decay(0.06)
            case .chime: v.a0 = 1; v.a1 = 0.25; v.a2 = 0.1; v.k0 = decay(0.9); v.k1 = decay(0.35); v.k2 = decay(0.1); v.release = decay(0.4)
            case .whoosh: v.a0 = 0; v.release = decay(0.15)
            case .tick: v.a0 = 1; v.k0 = decay(0.012); v.release = decay(0.01)
            case .glass: v.a0 = 1; v.a1 = 1; v.k0 = decay(0.18); v.k1 = decay(0.01); v.release = decay(0.1)
            }
            voices[slot] = v
        }

        return { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard abl.count >= 2, let lp = abl[0].mData?.assumingMemoryBound(to: Float.self),
                  let rp = abl[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let n = Int(frameCount)
            let pr = params.pointee

            while tail.pointee != head.pointee {
                let c = ring[Int(tail.pointee)]
                trigger(c.voice, freq: c.freq, vel: c.vel, pan: c.pan, dur: c.dur, music: false)
                tail.pointee = (tail.pointee + 1) % Int32(ringSize)
            }

            var s = seq.pointee
            let playing = pr.playing == 1 && pr.track >= 0 && pr.track < trackCount
            if playing && s.current != pr.track {
                s.current = pr.track; s.beat = 0; s.index = 0
                for i in 0..<maxVoices where voices[i].music == 1 { voices[i].dur = min(voices[i].dur, voices[i].t) }
            }
            if !playing && s.current >= 0 {
                for i in 0..<maxVoices where voices[i].music == 1 { voices[i].dur = min(voices[i].dur, voices[i].t) }
                s.current = -1
            }
            let info = s.current >= 0 ? tracks[Int(s.current)] : TrackInfo(offset: 0, count: 0, loop: 1, tempo: 120)
            let beatInc = info.tempo / 60 / Double(sr)
            let musicGain = pr.music
            let sfxGain = pr.sfx
            let energy = pr.energy

            for f in 0..<n {
                if s.current >= 0 {
                    while s.index < info.count {
                        let e = events[Int(info.offset + s.index)]
                        if e.beat > s.beat { break }
                        if e.layer <= energy {
                            trigger(e.voice, freq: e.freq, vel: e.vel, pan: e.pan, dur: e.dur, music: true)
                        }
                        s.index += 1
                    }
                    s.beat += beatInc
                    if s.beat >= info.loop { s.beat -= info.loop; s.index = 0 }
                }

                var l: Float = 0, r: Float = 0
                for i in 0..<maxVoices {
                    if voices[i].active == 0 { continue }
                    var v = voices[i]
                    let dt = invSR
                    if v.t >= v.dur { v.gate *= v.release }
                    var x: Float = 0
                    switch v.voice {
                    case 0: // kick: pitch-dropping sine with a click
                        let f0 = v.freq * (1 + 2.5 * v.f1)
                        v.f1 *= 0.9985
                        v.p0 += f0 * dt
                        x = sinf(twoPi * v.p0) * v.a0 * 0.95 + (v.t < 0.003 ? noise(&v) * 0.3 : 0)
                        x = tanhf(x * 1.4)
                        v.a0 *= v.k0
                    case 1: // snare: body tone plus band-limited noise
                        v.p0 += v.freq * dt
                        let nz = noise(&v)
                        v.f1 += (nz - v.f1) * 0.55
                        x = sinf(twoPi * v.p0) * v.a0 * 0.45 + (nz - v.f1 * 0.6) * v.a1 * 0.5
                        v.a0 *= v.k0; v.a1 *= v.k1
                    case 2: // hat: high-passed noise
                        let nz = noise(&v)
                        v.f1 += (nz - v.f1) * 0.7
                        x = (nz - v.f1) * v.a0 * 0.28
                        v.a0 *= v.k0
                    case 3: // clap: three quick noise bursts then a tail
                        let nz = noise(&v)
                        v.f1 += (nz - v.f1) * 0.35
                        let burst: Float = (v.t < 0.012 || (v.t > 0.016 && v.t < 0.026) || v.t > 0.032) ? 1 : 0.2
                        x = (nz - v.f1) * v.a0 * burst * 0.5
                        v.a0 *= v.k0
                    case 4: // bass: sine + filtered saw, warm
                        v.p0 += v.freq * dt
                        v.p1 += v.freq * dt
                        v.p1 -= floorf(v.p1)
                        let saw = v.p1 * 2 - 1
                        v.f1 += (saw - v.f1) * lpc(220 + 900 * v.a0)
                        let env = (0.6 + 0.4 * v.a0) * min(1, v.t * 400)
                        x = tanhf((sinf(twoPi * v.p0) * 0.9 + v.f1 * 0.5) * 1.2) * 0.42 * env
                        v.a0 *= v.k0
                    case 5: // keys: two-operator FM electric piano
                        v.p0 += v.freq * dt; v.p1 += v.freq * dt; v.p3 += v.freq * 7 * dt
                        let mod = (v.a1 + 0.2) * sinf(twoPi * v.p1)
                        x = (v.a0 * sinf(twoPi * v.p0 + mod) + v.a3 * sinf(twoPi * v.p3)) * 0.26 * min(1, v.t * 300)
                        v.a0 *= v.k0; v.a1 *= v.k1; v.a3 *= v.k3
                    case 6: // pad: detuned saws through a slow low-pass
                        v.p0 += v.freq * 1.004 * dt; v.p1 += v.freq * 0.996 * dt; v.p2 += v.freq * 0.5 * dt
                        v.p0 -= floorf(v.p0); v.p1 -= floorf(v.p1); v.p2 -= floorf(v.p2)
                        let saw = (v.p0 * 2 - 1) + (v.p1 * 2 - 1) + 0.5 * (v.p2 * 2 - 1)
                        let c = lpc(900 + 400 * sinf(v.t * 0.7))
                        v.f1 += (saw - v.f1) * c; v.f2 += (v.f1 - v.f2) * c
                        x = v.f2 * 0.1 * min(1, v.t / 0.4)
                        v.a0 = 1
                    case 7: // lead: soft square with vibrato
                        let vib = 1 + 0.004 * sinf(twoPi * 5.5 * v.t) * min(1, max(0, v.t - 0.15) * 3)
                        v.p0 += v.freq * vib * dt
                        v.p0 -= floorf(v.p0)
                        let sq: Float = v.p0 < 0.5 ? 1 : -1
                        v.f1 += (sq - v.f1) * lpc(2400)
                        v.f2 += (v.f1 - v.f2) * lpc(3000)
                        x = v.f2 * 0.14 * min(1, v.t * 60)
                        v.a0 = 1
                    case 8: // pluck (Karplus-Strong)
                        let base = i * ksLength
                        let len = Int(v.ksLen)
                        let pos = Int(v.ksPos)
                        let nxt = (pos + 1) % len
                        let y = ks[base + pos]
                        ks[base + pos] = (y + ks[base + nxt]) * 0.5 * (v.t >= v.dur ? 0.98 : v.k0)
                        v.ksPos = Int32(nxt)
                        x = y * 0.45
                        v.a0 = abs(y) > 1e-4 ? 1 : v.a0 * 0.999
                    case 9: // swish: noise through a band that sweeps down, soft attack
                        let nz = noise(&v)
                        let center = v.freq * (1.6 - min(1, v.t / 0.25) * 0.9)
                        let c = lpc(center)
                        v.f1 += (nz - v.f1) * c
                        v.f2 += (v.f1 - v.f2) * lpc(center * 0.35)
                        let att = min(1, v.t / 0.03)
                        x = (v.f1 - v.f2) * v.a0 * att * 1.4
                        v.a0 *= v.k0
                    case 10: // rim: inharmonic metal partials and a strike click
                        let bend = 1 + 0.015 * v.f1
                        v.f1 *= 0.999
                        v.p0 += v.freq * bend * dt; v.p1 += v.freq * 2.76 * dt; v.p2 += v.freq * 5.40 * dt; v.p3 += v.freq * 8.93 * dt
                        x = v.a0 * sinf(twoPi * v.p0) + v.a1 * sinf(twoPi * v.p1) + v.a2 * sinf(twoPi * v.p2) + v.a3 * sinf(twoPi * v.p3)
                        x = x * 0.2 + (v.t < 0.004 ? noise(&v) * 0.35 : 0)
                        v.a0 *= v.k0; v.a1 *= v.k1; v.a2 *= v.k2; v.a3 *= v.k3
                    case 11: // board: thud, a snap and a faint glass ring
                        v.p0 += v.freq * dt; v.p2 += v.freq * 6.3 * dt
                        let nz = noise(&v)
                        x = (sinf(twoPi * v.p0) * v.a0 * 0.7 + nz * v.a1 * 0.35 + sinf(twoPi * v.p2) * v.a2 * 0.06)
                        v.a0 *= v.k0; v.a1 *= v.k1; v.a2 *= v.k2
                    case 12: // bounce: leather thump with a pitch drop
                        let f0 = v.freq * (1 + 0.8 * v.f1)
                        v.f1 *= 0.998
                        v.p0 += f0 * dt
                        let nz = noise(&v)
                        v.f2 += (nz - v.f2) * 0.25
                        x = tanhf(sinf(twoPi * v.p0) * v.a0 * 1.3) * 0.75 + v.f2 * v.a1 * 0.5
                        v.a0 *= v.k0; v.a1 *= v.k1
                    case 13: // buzzer: two detuned pulses, low-passed, arcade-style
                        v.p0 += v.freq * dt; v.p1 += v.freq * 1.059 * dt
                        v.p0 -= floorf(v.p0); v.p1 -= floorf(v.p1)
                        let s0: Float = v.p0 < 0.35 ? 1 : -1
                        let s1: Float = v.p1 < 0.35 ? 1 : -1
                        let sq = s0 + s1
                        v.f1 += (sq - v.f1) * lpc(1600)
                        x = v.f1 * 0.16 * min(1, v.t * 80)
                    case 14: // chime: bell partials
                        v.p0 += v.freq * dt; v.p1 += v.freq * 3 * dt; v.p2 += v.freq * 6.2 * dt
                        x = (v.a0 * sinf(twoPi * v.p0) + v.a1 * sinf(twoPi * v.p1) + v.a2 * sinf(twoPi * v.p2)) * 0.26 * min(1, v.t * 500)
                        v.a0 *= v.k0; v.a1 *= v.k1; v.a2 *= v.k2
                    case 15: // whoosh: noise with a rising band
                        let nz = noise(&v)
                        let center = 300 + 3200 * min(1, v.t / max(v.dur, 0.05))
                        v.f1 += (nz - v.f1) * lpc(center)
                        v.f2 += (v.f1 - v.f2) * lpc(center * 0.4)
                        x = (v.f1 - v.f2) * 0.9 * min(1, v.t / 0.1)
                        v.a0 = 1
                    case 16: // tick
                        v.p0 += v.freq * dt
                        x = sinf(twoPi * v.p0) * v.a0 * 0.5
                        v.a0 *= v.k0
                    case 17: // glass: a dull knock on the screen
                        v.p0 += v.freq * dt
                        let nz = noise(&v)
                        x = (sinf(twoPi * v.p0) * v.a0 + nz * v.a1 * 0.4) * 0.5
                        v.a0 *= v.k0; v.a1 *= v.k1
                    default:
                        v.a0 = 0
                    }
                    v.p0 -= floorf(v.p0); v.p1 -= floorf(v.p1); v.p2 -= floorf(v.p2); v.p3 -= floorf(v.p3)
                    let g = v.vel * v.gate * (v.music == 1 ? musicGain : sfxGain)
                    l += x * g * v.panL
                    r += x * g * v.panR
                    v.t += dt
                    let sustained = v.voice == 6 || v.voice == 7 || v.voice == 13 || v.voice == 15
                    let silent = v.gate < 0.0005 || (!sustained && v.a0 < 0.0003 && v.a1 < 0.0003) || v.t > 10
                    if silent { v.active = 0 }
                    voices[i] = v
                }
                lp[f] = l / (1 + abs(l))
                rp[f] = r / (1 + abs(r))
            }
            seq.pointee = s
            params.pointee.beatOut = s.beat
            return noErr
        }
    }
}
