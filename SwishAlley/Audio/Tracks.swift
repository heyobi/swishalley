import Foundation

/// An original instrumental loop, arranged from step patterns at launch. No vocals, no lyrics, no samples.
struct Track: Identifiable {
    let id: String
    let title: String
    let tempo: Double
    let bars: Int
    var loopBeats: Double { Double(bars * 4) }
    let events: [NoteEvent]
}

enum Tracks {
    static func freq(_ midi: Int) -> Float { Float(440 * pow(2, Double(midi - 69) / 12)) }

    /// "Am9" → (root pitch class, intervals).
    static func chord(_ s: String) -> (root: Int, iv: [Int]) {
        let names: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        var chars = Array(s)
        var root = names[chars.removeFirst()] ?? 0
        if let c = chars.first, c == "#" || c == "b" { root += c == "#" ? 1 : -1; chars.removeFirst() }
        let table: [String: [Int]] = [
            "": [0, 4, 7], "m": [0, 3, 7], "7": [0, 4, 7, 10], "maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10],
            "m9": [0, 3, 10, 14], "9": [0, 4, 10, 14], "maj9": [0, 4, 11, 14], "sus4": [0, 5, 7], "sus2": [0, 2, 7],
            "6": [0, 4, 7, 9], "m6": [0, 3, 7, 9], "add9": [0, 4, 7, 14],
        ]
        return ((root + 12) % 12, table[String(chars)] ?? [0, 4, 7])
    }

    struct Spec {
        var id: String
        var title: String
        var tempo: Double
        var bars: Int
        var chords: [String]                  // one per bar, repeated to fill
        var kick = ""
        var snare = ""
        var clap = ""
        var hat = ""
        var hatHot = ""                       // layer 1
        var bass = ""                         // '1' root, '5' fifth, '8' octave, '7' seventh, '3' third
        var bassOctave = 36                   // C2
        var keys = ""                         // 'x' chord stab
        var keysOctave = 60
        var pad = false
        var arp = ""                          // pluck: digits pick chord tones (layer 1 unless arpAlways)
        var arpAlways = false
        var lead: [(Double, Double, Int)] = []   // (beat within 8 bars, beats, midi), layer 1
    }

    static func arrange(_ s: Spec) -> Track {
        var ev: [NoteEvent] = []
        func steps(_ p: String) -> [Character] { Array(p.replacingOccurrences(of: " ", with: "")) }
        for bar in 0..<s.bars {
            let b0 = Double(bar * 4)
            let c = chord(s.chords[bar % s.chords.count])
            func tone(_ d: Character, octave: Int) -> Int? {
                let base = octave + c.root
                switch d {
                case "1": return base
                case "3": return base + (c.iv.count > 1 ? c.iv[1] : 4)
                case "5": return base + 7
                case "7": return base + (c.iv.count > 3 ? c.iv[3] : 10)
                case "8": return base + 12
                case "9": return base + 14
                default: return nil
                }
            }
            func drum(_ p: String, _ v: Voice, freq: Float, pan: Float = 0, layer: Int32 = 0) {
                for (i, ch) in steps(p).enumerated() where ch != "." {
                    let vel: Float = ch == "x" ? 0.9 : (ch == "O" ? 0.55 : 0.5)
                    ev.append(NoteEvent(beat: b0 + Double(i) * 0.25, dur: ch == "O" ? 0.5 : 0.1, freq: freq, vel: vel, voice: v, pan: pan, layer: layer))
                }
            }
            drum(s.kick, .kick, freq: 52)
            drum(s.snare, .snare, freq: 190)
            drum(s.clap, .clap, freq: 1, pan: 0.1)
            drum(s.hat, .hat, freq: 1, pan: 0.25)
            drum(s.hatHot, .hat, freq: 1, pan: -0.25, layer: 1)
            // Bass: a digit starts a note that lasts until the next symbol that is not '-'.
            let bs = steps(s.bass)
            for (i, ch) in bs.enumerated() {
                guard let m = tone(ch, octave: s.bassOctave) else { continue }
                var len = 1
                while i + len < bs.count && bs[i + len] == "-" { len += 1 }
                ev.append(NoteEvent(beat: b0 + Double(i) * 0.25, dur: Double(len) * 0.25 * 0.9, freq: freq(m), vel: 0.8, voice: .bass, pan: 0))
            }
            // Keys stabs: the whole chord, voiced close.
            for (i, ch) in steps(s.keys).enumerated() where ch == "x" || ch == "o" {
                for (k, iv) in c.iv.enumerated() {
                    ev.append(NoteEvent(beat: b0 + Double(i) * 0.25, dur: ch == "x" ? 0.45 : 0.9, freq: freq(s.keysOctave + c.root + iv),
                                        vel: 0.42, voice: .keys, pan: Float(k) * 0.15 - 0.2))
                }
            }
            if s.pad {
                for (k, iv) in c.iv.enumerated() {
                    ev.append(NoteEvent(beat: b0, dur: 3.9, freq: freq(48 + c.root + iv + (iv < 5 ? 12 : 0)), vel: 0.38, voice: .pad,
                                        pan: k % 2 == 0 ? -0.35 : 0.35))
                }
            }
            for (i, ch) in steps(s.arp).enumerated() {
                guard let m = tone(ch, octave: 60) else { continue }
                ev.append(NoteEvent(beat: b0 + Double(i) * 0.25, dur: 0.2, freq: freq(m), vel: 0.35, voice: .pluck,
                                    pan: i % 2 == 0 ? 0.3 : -0.3, layer: s.arpAlways ? 0 : 1))
            }
        }
        // Lead hook repeats every 8 bars, only when the game is hot.
        var start = 0.0
        while start < Double(s.bars * 4) {
            for (b, d, m) in s.lead where start + b < Double(s.bars * 4) {
                ev.append(NoteEvent(beat: start + b, dur: d, freq: freq(m), vel: 0.5, voice: .lead, pan: 0.05, layer: 1))
            }
            start += 32
        }
        return Track(id: s.id, title: s.title, tempo: s.tempo, bars: s.bars, events: ev)
    }

    // MARK: The pieces (all original)

    /// Menus: laid-back keys and a soft groove.
    static let lobby = arrange(Spec(
        id: "lobby", title: "Locker Room Lights", tempo: 88, bars: 8,
        chords: ["Dmaj7", "Bm7", "Gmaj7", "A7", "Dmaj7", "F#m7", "Gmaj7", "A7"],
        kick: "x.....x...x.....", snare: "....o.......o...", hat: "o.o.o.o.o.o.o.oo",
        bass: "1-----5---1-8---", bassOctave: 38, keys: "o.......o.......", keysOctave: 60, pad: true,
        arp: "1.3.5.8.5.3.1...", arpAlways: true))

    /// Classic: a warm funk groove.
    static let neonGym = arrange(Spec(
        id: "neon", title: "Neon Gym", tempo: 106, bars: 8,
        chords: ["Am9", "D9", "Fmaj7", "E7", "Am9", "D9", "Fmaj7", "E7"],
        kick: "x.....x...x..x..", snare: "....x.......x...", clap: "............x...",
        hat: "x.o.x.o.x.o.x.oo", hatHot: ".o.o.o.o.o.o.o.o",
        bass: "1--8..1.5-..7.8.", bassOctave: 33, keys: "..x..x....x..x..", keysOctave: 60, pad: false,
        arp: "1.5.8.5.3.5.8.9.",
        lead: [(0, 0.5, 76), (0.5, 0.5, 79), (1.5, 1, 81), (3, 0.5, 79), (3.5, 0.5, 76), (4, 2, 74),
               (8, 0.5, 76), (8.5, 0.5, 79), (9.5, 1, 81), (11, 0.5, 84), (11.5, 0.5, 83), (12, 2, 81),
               (16, 0.75, 76), (17, 0.75, 74), (18, 1.5, 72), (20, 0.5, 74), (20.5, 0.5, 76), (21, 3, 76)]))

    /// Night games: four-on-the-floor house.
    static let nightCourt = arrange(Spec(
        id: "night", title: "Night Court", tempo: 120, bars: 8,
        chords: ["Fm7", "Dbmaj7", "Ebsus4", "Cm7", "Fm7", "Dbmaj7", "Bbm7", "C7"],
        kick: "x...x...x...x...", clap: "....x.......x...", hat: "..o...o...o...o.", hatHot: "xoxoxoxoxoxoxoxo",
        bass: "..1-..1-..1-..8-", bassOctave: 29, keys: "", pad: true,
        arp: "1.3.5.8.1.3.5.8.", arpAlways: true,
        lead: [(0, 1, 77), (1.5, 0.5, 80), (2, 2, 79), (8, 1, 77), (9.5, 0.5, 80), (10, 1, 82), (11, 1, 84), (12, 3, 79)]))

    /// Retro arcade synthwave.
    static let arcadeGlow = arrange(Spec(
        id: "glow", title: "Arcade Glow", tempo: 112, bars: 8,
        chords: ["C", "Am", "F", "G", "C", "Am", "F", "Gsus4"],
        kick: "x.......x.......", snare: "....x.......x...", hat: "o.o.o.o.o.o.o.o.", hatHot: ".x.x.x.x.x.x.x.x",
        bass: "1.1.1.1.1.1.1.1.", bassOctave: 36, keys: "", pad: true,
        arp: "1358135813581358", arpAlways: false,
        lead: [(0, 1.5, 76), (1.5, 0.5, 74), (2, 2, 72), (4, 1, 69), (5, 1, 72), (6, 2, 74),
               (8, 1.5, 76), (9.5, 0.5, 79), (10, 2, 77), (12, 1, 76), (13, 1, 74), (14, 2, 72)]))

    static let all: [Track] = [lobby, neonGym, nightCourt, arcadeGlow]
    /// Playable round music (the lobby piece plays in menus).
    static let roundIDs = ["neon", "night", "glow"]
}
