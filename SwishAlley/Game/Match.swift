import Foundation

enum Mode: String, CaseIterable, Identifiable {
    case classic, duelRace, duelTurns, practice, overtime, drift
    var id: String { rawValue }

    var isDuel: Bool { self == .duelRace || self == .duelTurns }
    var isPro: Bool { self == .overtime || self == .drift }
    var players: Int { isDuel ? 2 : 1 }
    /// Modes with a saved personal best.
    var keepsBest: Bool { self == .classic || self == .overtime || self == .drift }

    /// Round length in seconds (practice has none; turns is per turn).
    var duration: Double? {
        switch self {
        case .classic, .drift: return 60
        case .duelRace: return 45
        case .duelTurns: return 15
        case .overtime: return 30
        case .practice: return nil
        }
    }
}

struct PlayerScore: Equatable {
    var points = 0
    var baskets = 0
    var shots = 0
    var swishes = 0
    var streak = 0
    var bestStreak = 0
    var onFire: Bool { streak >= Match.fireStreak }
    var accuracy: Double { shots > 0 ? Double(baskets) / Double(shots) : 0 }
}

enum MatchPhase: Equatable { case countdown, playing, turnBreak, over }

enum MatchEvent: Equatable {
    case basket(player: Int, points: Int, swish: Bool, onFire: Bool, double: Bool)
    case fireOn(player: Int)
    case fireOff(player: Int)
    case finalStretch          // the last seconds start: double points, the hoop moves
    case secondTick(left: Int) // each of the last five seconds
    case go
    case turn(player: Int)
    case buzzer
}

/// The rules of a round, independent of drawing and physics: clock, scoring, streaks ("on fire"), the final
/// stretch where baskets count double and the hoop starts to glide, turns in a duel.
struct Match: Equatable {
    static let countdown: Double = 2.4
    static let fireStreak = 3
    static let finalStretch: Double = 10
    static let turnsEach = 3
    static let turnBreak: Double = 1.6
    static let overtimeBonus: Double = 2
    static let overtimeCap: Double = 60

    let mode: Mode
    private(set) var phase: MatchPhase = .countdown
    private(set) var players: [PlayerScore]
    /// Seconds into the current phase.
    private(set) var clock: Double = 0
    /// Seconds left in the round (or in the current turn).
    private(set) var timeLeft: Double
    /// Turns mode: whose turn it is, and how many turns have been played.
    private(set) var active = 0
    private(set) var turnsPlayed = 0
    private(set) var finalAnnounced = false
    private var lastTick = Int.max
    /// Total seconds of play, for the hoop's motion.
    private(set) var playTime: Double = 0

    init(mode: Mode) {
        self.mode = mode
        players = Array(repeating: PlayerScore(), count: mode.players)
        timeLeft = mode.duration ?? 0
    }

    var timed: Bool { mode.duration != nil }
    var isFinalStretch: Bool { phase == .playing && timed && mode != .duelTurns && mode != .overtime && timeLeft <= Self.finalStretch }

    /// Whether a player may shoot right now.
    func canShoot(_ player: Int) -> Bool {
        guard phase == .playing else { return false }
        if mode == .duelTurns { return player == active }
        return player < players.count
    }

    /// Sideways offset of the hoop for a player's lane at this moment (arena units).
    func hoopSlide(player: Int) -> Float {
        let t = playTime
        switch mode {
        case .drift:
            let speed = 1.1 + 0.9 * min(1, t / 60)
            let ramp = min(1, t / 2)
            return Float(0.2 * ramp * sin(t * speed + Double(player)))
        case .classic, .duelRace:
            guard isFinalStretch || (phase == .over && finalAnnounced) else { return 0 }
            let into = Self.finalStretch - max(0, timeLeft)
            let ramp = min(1, into / 1.2)
            return Float(0.2 * ramp * sin(into * 2.4 + Double(player) * .pi))
        default:
            return 0
        }
    }

    // MARK: Time

    mutating func update(dt: Double) -> [MatchEvent] {
        var events: [MatchEvent] = []
        clock += dt
        switch phase {
        case .countdown:
            if clock >= Self.countdown {
                phase = .playing
                clock = 0
                events.append(.go)
                if mode == .duelTurns { events.append(.turn(player: active)) }
            }
        case .turnBreak:
            if clock >= Self.turnBreak {
                phase = .playing
                clock = 0
                timeLeft = mode.duration ?? 0
                lastTick = Int.max
                events.append(.turn(player: active))
            }
        case .playing:
            playTime += dt
            guard timed else { break }
            timeLeft -= dt
            if !finalAnnounced && isFinalStretch {
                finalAnnounced = true
                events.append(.finalStretch)
            }
            let whole = Int(ceil(timeLeft))
            if whole < lastTick && whole <= 5 && whole > 0 {
                events.append(.secondTick(left: whole))
            }
            lastTick = min(lastTick, whole)
            if timeLeft <= 0 {
                timeLeft = 0
                events.append(.buzzer)
                if mode == .duelTurns {
                    turnsPlayed += 1
                    if turnsPlayed >= Self.turnsEach * 2 {
                        phase = .over
                    } else {
                        active = 1 - active
                        phase = .turnBreak
                        clock = 0
                    }
                } else {
                    phase = .over
                }
            }
        case .over:
            break
        }
        return events
    }

    // MARK: Shots

    mutating func shot(player: Int) {
        guard player < players.count, phase == .playing else { return }
        players[player].shots += 1
    }

    mutating func basket(player: Int, swish: Bool) -> [MatchEvent] {
        guard player < players.count, phase == .playing || phase == .over || phase == .turnBreak else { return [] }
        var p = players[player]
        let wasOnFire = p.onFire
        var points = wasOnFire ? 3 : 2
        if swish { points += 1 }
        let double = isFinalStretch
        if double { points *= 2 }
        p.points += points
        p.baskets += 1
        if swish { p.swishes += 1 }
        p.streak += 1
        p.bestStreak = max(p.bestStreak, p.streak)
        players[player] = p
        var events: [MatchEvent] = [.basket(player: player, points: points, swish: swish, onFire: wasOnFire, double: double)]
        if !wasOnFire && p.onFire { events.append(.fireOn(player: player)) }
        if mode == .overtime && phase == .playing {
            timeLeft = min(Self.overtimeCap, timeLeft + Self.overtimeBonus)
        }
        return events
    }

    mutating func miss(player: Int) -> [MatchEvent] {
        guard player < players.count else { return [] }
        let was = players[player].onFire
        players[player].streak = 0
        return was ? [.fireOff(player: player)] : []
    }

    /// Duel winner (nil for a tie or a solo mode).
    var winner: Int? {
        guard players.count == 2, phase == .over else { return nil }
        if players[0].points == players[1].points { return nil }
        return players[0].points > players[1].points ? 0 : 1
    }

    /// A mid-round state for screenshots and tests.
    mutating func showcase(points: [Int], baskets: [Int], streak: [Int], timeLeft: Double, active: Int = 0) {
        phase = .playing
        clock = 0
        for i in players.indices {
            players[i].points = points[safe: i] ?? 0
            players[i].baskets = baskets[safe: i] ?? 0
            players[i].shots = (baskets[safe: i] ?? 0) + 3
            players[i].streak = streak[safe: i] ?? 0
            players[i].bestStreak = max(players[i].streak, 4)
            players[i].swishes = (baskets[safe: i] ?? 0) / 3
        }
        self.timeLeft = timeLeft
        self.active = active
        if let d = mode.duration { playTime = d - timeLeft }
        finalAnnounced = isFinalStretch
        lastTick = Int(ceil(timeLeft))
    }

    /// Ends the round now (the player quit).
    mutating func finish() { phase = .over }
}

/// Personal bests per mode, kept on the device.
struct Bests {
    var defaults: UserDefaults = .standard

    func best(_ m: Mode) -> Int { defaults.integer(forKey: "best.\(m.rawValue)") }

    /// Records a score; returns true when it beats the previous best (a first score of zero never counts).
    @discardableResult
    func record(_ m: Mode, score: Int) -> Bool {
        guard m.keepsBest, score > 0 else { return false }
        if score > best(m) {
            defaults.set(score, forKey: "best.\(m.rawValue)")
            return true
        }
        return false
    }
}
