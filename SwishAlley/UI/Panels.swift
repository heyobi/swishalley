import SwiftUI

enum Neon {
    static let pink = Color(red: 1, green: 0.25, blue: 0.64)
    static let cyan = Color(red: 0.22, green: 0.89, blue: 1)
    static let amber = Color(red: 1, green: 0.70, blue: 0.12)
    static let ink = Color(red: 0.07, green: 0.05, blue: 0.12)
}

struct TitleView: View {
    var compact = false
    var body: some View {
        VStack(spacing: compact ? 2 : 6) {
            Text("SWISH ALLEY")
                .font(.system(size: compact ? 30 : 44, weight: .black, design: .rounded))
                .kerning(3)
                .foregroundStyle(LinearGradient(colors: [Neon.amber, Neon.pink], startPoint: .top, endPoint: .bottom))
                .shadow(color: Neon.pink.opacity(0.8), radius: 12)
            Text("Arcade basketball")
                .font(.system(size: compact ? 13 : 16, weight: .semibold, design: .rounded))
                .textCase(.uppercase)
                .kerning(2)
                .foregroundStyle(Neon.cyan)
        }
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
        .allowsHitTesting(false)
    }
}

struct ScorePanel: View {
    @EnvironmentObject var engine: Engine
    let match: Match
    let player: Int
    var sideways = false
    let pause: () -> Void

    var body: some View {
        let p = match.players[safe: player] ?? PlayerScore()
        HStack(spacing: 14) {
            if player == 0 {
                Button(action: pause) {
                    Image(systemName: "pause.fill").font(.system(size: 15, weight: .bold)).frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Pause"))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(match.mode.isDuel ? engine.playerName(player) : String(localized: "Score"))
                    .font(.system(size: 11, weight: .bold, design: .rounded)).textCase(.uppercase).foregroundStyle(.secondary)
                Text("\(p.points)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(p.onFire ? Neon.amber : .white)
                    .contentTransition(.numericText())
            }
            if p.onFire {
                HStack(spacing: 1) {
                    Image(systemName: "flame.fill")
                    if p.unstoppable { Image(systemName: "flame.fill") }
                    Text("×\(p.streak)").font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
                }
                .foregroundStyle(p.unstoppable ? Neon.pink : Neon.amber).font(.title3)
                .accessibilityLabel(Text("On fire"))
            }
            if let b = match.bonus(player) {
                Label(b == .bigHoop ? String(localized: "Big hoop") : String(localized: "×2"), systemImage: b == .bigHoop ? "circle.dashed" : "star.fill")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color(red: 1, green: 0.78, blue: 0.23).opacity(0.85)))
                    .foregroundStyle(Neon.ink)
            }
            Spacer(minLength: 4)
            if match.timed {
                let active = match.mode != .duelTurns || match.active == player
                VStack(alignment: .trailing, spacing: 0) {
                    Text(match.mode == .duelTurns ? (active ? String(localized: "Your turn") : String(localized: "Wait")) : String(localized: "Time"))
                        .font(.system(size: 11, weight: .bold, design: .rounded)).textCase(.uppercase).foregroundStyle(.secondary)
                    Text(active ? String(format: "%d", Int(ceil(match.timeLeft))) : "–")
                        .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(match.isFinalStretch ? Neon.pink : Neon.cyan)
                }
            } else {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Streak").font(.system(size: 11, weight: .bold, design: .rounded)).textCase(.uppercase).foregroundStyle(.secondary)
                    Text("\(p.streak)").font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit()).foregroundStyle(Neon.cyan)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: sideways ? .infinity : 520, maxHeight: .infinity)
        .glass(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: .infinity)
    }
}

struct CountdownView: View {
    let clock: Double
    var body: some View {
        let left = max(1, Int(ceil(Match.countdown - clock)))
        Text("\(left)")
            .font(.system(size: 72, weight: .black, design: .rounded))
            .foregroundStyle(Neon.amber)
            .shadow(color: Neon.pink, radius: 16)
            .id(left)
            .transition(.scale.combined(with: .opacity))
            .allowsHitTesting(false)
    }
}

struct HintCard: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .glass(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 20)
            .allowsHitTesting(false)
    }
}

struct BannerView: View {
    let banner: Banner
    var body: some View {
        VStack(spacing: 2) {
            Text(banner.text)
                .font(.system(size: 46, weight: .black, design: .rounded))
                .foregroundStyle(banner.hot ? Neon.amber : .white)
                .shadow(color: banner.hot ? Neon.pink : Neon.cyan, radius: 14)
            if let d = banner.detail {
                Text(d)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .textCase(.uppercase)
                    .kerning(1.5)
                    .foregroundStyle(banner.hot ? Neon.pink : Neon.cyan)
            }
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }
}

struct ResultsCard: View {
    @EnvironmentObject var engine: Engine
    let results: Results
    let player: Int
    let again: () -> Void
    let close: () -> Void

    var body: some View {
        let p = results.players[safe: player] ?? PlayerScore()
        ScrollView {
            VStack(spacing: 14) {
                if results.mode.isDuel {
                    Text(results.winner == nil ? String(localized: "It's a tie!") : String(format: String(localized: "%@ wins!"), engine.playerName(results.winner ?? 0)))
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(Neon.amber)
                    HStack(spacing: 24) {
                        ForEach(0..<results.players.count, id: \.self) { i in
                            VStack {
                                Text(engine.playerName(i)).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                Text("\(results.players[i].points)").font(.system(size: 38, weight: .heavy, design: .rounded).monospacedDigit())
                            }
                        }
                    }
                } else {
                    if results.newBest {
                        Label("New personal best!", systemImage: "trophy.fill")
                            .font(.headline)
                            .foregroundStyle(Neon.amber)
                    }
                    Text("\(p.points)")
                        .font(.system(size: 64, weight: .black, design: .rounded).monospacedDigit())
                        .shadow(color: Neon.pink.opacity(0.7), radius: 12)
                    if results.mode.keepsBest {
                        Text(String(format: String(localized: "Best %d"), results.best))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 18) {
                        stat(String(localized: "Baskets"), "\(p.baskets)")
                        stat(String(localized: "Accuracy"), "\(Int((p.accuracy * 100).rounded()))%")
                        stat(String(localized: "Swishes"), "\(p.swishes)")
                        stat(String(localized: "Streak"), "\(p.bestStreak)")
                    }
                }
                Button(action: again) {
                    Label("One more run", systemImage: "arrow.counterclockwise")
                        .font(.title3.weight(.heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Neon.pink)
                Button("Menu", action: close).buttonStyle(.bordered)
            }
            .padding(20)
            .frame(maxWidth: 440)
            .glass(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.heavy).monospacedDigit())
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
        }
    }
}

/// The second player's view of the result, upright from their side.
struct DuelResultBadge: View {
    @EnvironmentObject var engine: Engine
    let results: Results
    let player: Int
    var body: some View {
        VStack(spacing: 6) {
            Text(results.winner == player ? String(localized: "You win!") : (results.winner == nil ? String(localized: "It's a tie!") : String(localized: "Good game!")))
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Neon.amber)
            Text("\(results.players[safe: player]?.points ?? 0)")
                .font(.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit())
        }
        .padding(18)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .allowsHitTesting(false)
    }
}

/// A pulsing edge glow while a player is on fire.
struct FireGlow: View {
    var hot = false
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let a = 0.35 + 0.25 * sin(t * (hot ? 9 : 5))
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(LinearGradient(colors: [hot ? Neon.pink : Neon.amber, .orange.opacity(0.4), hot ? Neon.pink : Neon.amber], startPoint: .top, endPoint: .bottom), lineWidth: 6)
                .blur(radius: 6)
                .opacity(a)
        }
        .allowsHitTesting(false)
    }
}
