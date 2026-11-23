import SwiftUI

struct MenuView: View {
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var store: Store
    @Binding var sheet: SheetKind?
    let showTitle: Bool
    @Binding var cameraCard: Bool
    @Binding var cameraCardDismissed: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if showTitle { TitleView(compact: true).frame(height: 70) }
                if cameraCard {
                    CameraCard(allow: {
                        withAnimation { cameraCard = false }
                        cameraCardDismissed = true
                        engine.enableTracking()
                    }, later: {
                        withAnimation { cameraCard = false }
                        cameraCardDismissed = true
                    })
                }
                ModeButton(title: String(localized: "Classic 60"), detail: bestText(.classic), symbol: "basketball.fill", tint: Neon.pink, big: true) {
                    engine.start(.classic)
                }
                HStack(spacing: 10) {
                    ModeButton(title: String(localized: "Duel"), detail: duelDetail, symbol: "person.2.fill", tint: Neon.cyan) {
                        engine.start(engine.duelStyle)
                    }
                    ModeButton(title: String(localized: "Practice"), detail: String(localized: "No clock"), symbol: "figure.basketball", tint: Neon.amber) {
                        engine.start(.practice)
                    }
                }
                Picker("Duel style", selection: $engine.duelStyle) {
                    Text("Race").tag(Mode.duelRace)
                    Text("Turns").tag(Mode.duelTurns)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(Text("Duel style"))
                HStack(spacing: 10) {
                    ModeButton(title: String(localized: "Overtime"), detail: bestText(.overtime), symbol: "timer", tint: Neon.amber) { engine.start(.overtime) }
                    ModeButton(title: String(localized: "Drift"), detail: bestText(.drift), symbol: "arrow.left.and.right", tint: Neon.cyan) { engine.start(.drift) }
                }
                ModeButton(title: String(localized: "Wild Toss"), detail: store.pro ? bestText(.wildToss) : String(localized: "Watermelons, ducks, toasters · Pro"),
                           symbol: store.pro ? "party.popper.fill" : "lock.fill", tint: Neon.pink) { engine.start(.wildToss) }
                HStack(spacing: 10) {
                    SmallButton(title: String(localized: "Locker"), symbol: "tshirt.fill") { sheet = .locker }
                    SmallButton(title: String(localized: "Settings"), symbol: "gearshape.fill") { sheet = .settings }
                    if !store.pro { SmallButton(title: String(localized: "Pro"), symbol: "star.fill") { sheet = .paywall } }
                }
            }
            .padding(14)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var duelDetail: String {
        engine.duelStyle == .duelRace ? String(localized: "Face to face · race") : String(localized: "Face to face · turns")
    }

    private func bestText(_ m: Mode) -> String {
        let b = Bests().best(m)
        if b > 0 { return String(format: String(localized: "Best %d"), b) }
        switch m {
        case .overtime: return String(localized: "+2 s per basket")
        case .drift: return String(localized: "The hoop never stops")
        case .wildToss: return String(localized: "Throw silly things")
        default: return String(localized: "60 seconds")
        }
    }
}

struct ModeButton: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    var big = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: big ? 26 : 19, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: big ? 40 : 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: big ? 22 : 17, weight: .heavy, design: .rounded))
                    Text(detail).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, big ? 16 : 11)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .glass(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(tint.opacity(big ? 0.7 : 0.35), lineWidth: big ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

struct SmallButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .glass(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct CameraCard: View {
    let allow: () -> Void
    let later: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("See the hoop in true 3D", systemImage: "eye").font(.headline)
            Text("Swish Alley can follow where your eyes are with the front camera, so the hoop pops out of the screen and you can look around the backboard. Video is analysed on this device and never stored or sent. The game plays the same without it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Not now", action: later).buttonStyle(.bordered)
                Spacer()
                Button(action: allow) { Text("Follow my eyes").bold() }.buttonStyle(.borderedProminent).tint(Neon.cyan)
            }
        }
        .padding(16)
        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
