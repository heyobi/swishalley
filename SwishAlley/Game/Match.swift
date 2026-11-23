import Foundation

enum Mode: String, CaseIterable, Identifiable {
    case classic, duelRace, duelTurns, practice, overtime, drift, wildToss
    var id: String { rawValue }

    var isDuel: Bool { self == .duelRace || self == .duelTurns }
    /// Paid content is extra things to play with, never a clock: only Wild Toss (silly objects) needs Pro.
    var isPro: Bool { self == .wildToss }
    /// Golden bonus balls show up in timed solo and race modes.
    var hasBonuses: Bool { self == .classic || self == .overtime || self == .drift || self == .duelRace || self == .wildToss }
    var players: Int { isDuel ? 2 : 1 }
    /// Modes with a saved personal best.
    var keepsBest: Bool { self == .classic || self == .overtime || self == .drift || self == .wildToss }

    /// Round length in seconds (practice has none; turns is per turn).
    var duration: Double? {
        switch self {
        case .classic, .drift, .wildToss: return 60
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
    var unstoppable: Bool { streak >= Match.unstoppableStreak }
    var accuracy: Double { shots > 0 ? Double(baskets) / Double(shots) : 0 }
}

enum MatchPhase: Equatable { case countdown, playing, turnBreak, over }

enum Bonus: String, Equatable { case bigHoop, double }

enum MatchEvent: Equatable {
    case count(left: Int)      // the countdown before the start
    case goldenBall(player: Int)
    case bonus(player: Int, kind: Bonus)
    case unstoppable(player: Int)
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
    static let unstoppableStreak = 6
    static let bonusLength: Double = 7
    static let goldenEvery: Double = 13
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
    /// Active bonus per player and when it ends (in play time).
    private(set) var bonuses: [Int: (kind: Bonus, until: Double)] = [:]
    private var nextGolden: Double = 8
    private var lastCount = 99
    private var bonusFlip = 0

    static func == (a: Match, b: Match) -> Bool {
        a.mode == b.mode && a.phase == b.phase && a.players == b.players && a.clock == b.clock && a.timeLeft == b.timeLeft
            && a.active == b.active && a.playTime == b.playTime && a.bonuses.keys.sorted() == b.bonuses.keys.sorted()
    }

    func bonus(_ player: Int) -> Bonus? {
        guard let b = bonuses[player], playTime < b.until else { return nil }
        return b.kind
    }

    /// Seconds left on a player's bonus.
    func bonusLeft(_ player: Int) -> Double { bonuses[player].map { max(0, $0.until - playTime) } ?? 0 }

    /// Rim size for a player's lane (Big Hoop bonus).
    func hoopScale(player: Int) -> Float { bonus(player) == .bigHoop ? 1.4 : 1 }

    /// A golden ball went in: alternate the two bonuses so both get seen.
    mutating func goldenScored(player: Int) -> [MatchEvent] {
        guard player < players.count else { return [] }
        let kind: Bonus = bonusFlip % 2 == 0 ? .bigHoop : .double
        bonusFlip += 1
        bonuses[player] = (kind, playTime + Self.bonusLength)
        return [.bonus(player: player, kind: kind)]
    }

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
            let left = Int(ceil(Self.countdown - clock))
            if left < lastCount && left > 0 { lastCount = left; events.append(.count(left: left)) }
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
            if mode.hasBonuses && playTime >= nextGolden && (!timed || timeLeft > 4) {
                nextGolden = playTime + Self.goldenEvery
                for p in players.indices where canShoot(p) { events.append(.goldenBall(player: p)) }
            }
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
        let wasUnstoppable = p.unstoppable
        var points = wasUnstoppable ? 4 : (wasOnFire ? 3 : 2)
        if swish { points += 1 }
        let double = isFinalStretch || bonus(player) == .double
        if double { points *= 2 }
        p.points += points
        p.baskets += 1
        if swish { p.swishes += 1 }
        p.streak += 1
        p.bestStreak = max(p.bestStreak, p.streak)
        players[player] = p
        var events: [MatchEvent] = [.basket(player: player, points: points, swish: swish, onFire: wasOnFire, double: double)]
        if !wasOnFire && p.onFire { events.append(.fireOn(player: player)) }
        if !wasUnstoppable && p.unstoppable { events.append(.unstoppable(player: player)) }
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
