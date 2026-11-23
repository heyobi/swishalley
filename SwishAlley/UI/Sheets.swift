import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("haptics") private var haptics = true
    @State private var trackingOn = false
    @State private var showDiagnostics = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: Binding(get: { engine.tracking == .running || (trackingOn && engine.trackingPreferred) }, set: { on in
                        trackingOn = on
                        on ? engine.enableTracking() : engine.disableTracking()
                    })) {
                        Label("Head tracking (3D hoop)", systemImage: "eye")
                    }
                    .disabled(engine.tracking == .unavailable || engine.tracking == .denied)
                    if engine.tracking == .denied {
                        Text("Camera access is off. You can allow it in the Settings app; the game plays the same without it.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("The front camera finds your eyes so the hoop is drawn from your point of view. Frames are analysed on this device and never recorded, stored or sent. Optional: everything plays the same with it off.")
                }
                Section("Sound") {
                    Toggle(isOn: $engine.musicOn) { Label("Music", systemImage: "music.note") }
                    Toggle(isOn: $engine.soundOn) { Label("Sound effects", systemImage: "speaker.wave.2.fill") }
                    Toggle(isOn: $haptics) { Label("Haptics", systemImage: "hand.tap.fill") }
                }
                Section("How to play") {
                    Text("Flick the ball up toward the hoop. The speed of your flick sets the power, its direction sets the aim. Three baskets in a row and you're on fire: baskets are worth 3 until you miss. In the last 10 seconds every basket counts double and the hoop starts to move.")
                        .font(.callout)
                    Text("On iPhone Duo, stand it half open like a tiny laptop: the hoop rises from the fold. For a duel, open it flat between two players.")
                        .font(.callout)
                }
                Section("Pro") {
                    if store.pro {
                        Label("Swish Alley Pro is unlocked. Thank you!", systemImage: "star.fill")
                    } else {
                        Button("Get Pro") { engine.shotSheet = .paywall; dismiss() }
                    }
                    Button("Restore purchase") { Task { await store.restore() } }
                    if let m = store.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("About") {
                    Link("Privacy policy", destination: URL(string: "https://github.com/heyobi/swishalley/blob/main/PRIVACY.md")!)
                    Link("Website", destination: URL(string: "https://heyobi.github.io/swishalley/")!)
                    DisclosureGroup("Diagnostics", isExpanded: $showDiagnostics) {
                        Text(diagnostics).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: haptics) { _, _ in Haptics.shared.tap() }
        }
    }

    private var diagnostics: String {
        let l = engine.layout
        var s = "presentation \(l?.presentation.rawValue ?? "-")"
        s += "\nhinge \(engine.shownHinge.map { String(format: "%.1f°", $0) } ?? "none")\(engine.hingeClosed ? " closed" : "")"
        if let f = engine.geometry.fold { s += String(format: "\nfold %.0f,%.0f %.0f×%.0f", f.minX, f.minY, f.width, f.height) }
        s += String(format: "\nwindow %.0f×%.0f", engine.geometry.size.width, engine.geometry.size.height)
        if let l { s += String(format: "\nscale %.1f pt/unit, setback %.3f", l.pointsPerUnit, l.arenas.first?.setback ?? 0) }
        s += "\ntracking \(engine.tracking) \(engine.diagnostics)"
        if let e = Synth.shared.lastError { s += "\naudio \(e)" }
        return s
    }
}

struct LockerSheet: View {
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var store: Store
    @Binding var sheet: SheetKind?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Arena") {
                    ForEach(ArenaTheme.all) { t in
                        row(title: t.name, locked: !t.free && !store.pro, selected: engine.themeID == t.id,
                            swatch: [Color(uiColor: UIColor(hex: t.neonA)), Color(uiColor: UIColor(hex: t.neonB)), Color(uiColor: UIColor(hex: t.floorLight))]) {
                            engine.themeID = t.id
                        }
                    }
                }
                Section("Ball") {
                    ForEach(BallSkin.all) { b in
                        row(title: b.name, locked: !b.free && !store.pro, selected: engine.skinID == b.id,
                            swatch: [Color(uiColor: UIColor(hex: b.base)), Color(uiColor: UIColor(hex: b.stripe ?? b.seams))]) {
                            engine.skinID = b.id
                        }
                    }
                }
                Section("Music") {
                    ForEach(Tracks.all.filter { Tracks.roundIDs.contains($0.id) }) { t in
                        row(title: t.title, locked: false, selected: engine.trackID == t.id, swatch: []) {
                            engine.trackID = t.id
                            if !engine.musicOn { engine.musicOn = true }
                            Synth.shared.play(t.id)
                        }
                    }
                }
            }
            .navigationTitle("Locker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onDisappear { if engine.screen == .menu && engine.musicOn { Synth.shared.play("lobby") } }
        }
    }

    private func row(title: String, locked: Bool, selected: Bool, swatch: [Color], pick: @escaping () -> Void) -> some View {
        Button {
            if locked { engine.shotSheet = .paywall; dismiss() } else { pick(); Haptics.shared.tap() }
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: -6) {
                    ForEach(Array(swatch.enumerated()), id: \.offset) { _, c in
                        Circle().fill(c).frame(width: 22, height: 22).overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 1))
                    }
                }
                Text(title).foregroundStyle(.primary)
                Spacer()
                if locked { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                else if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Neon.pink) }
            }
        }
        .accessibilityLabel(Text(locked ? "\(title), Pro" : title))
    }
}

struct PaywallSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(LinearGradient(colors: [Neon.amber, Neon.pink], startPoint: .top, endPoint: .bottom))
                    Text("Swish Alley Pro").font(.system(size: 30, weight: .black, design: .rounded))
                    Text("The whole game, duel included, stays free forever with no ads. Pro is a one-time thank-you that adds more to play with.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        perk("sparkles", String(localized: "Three more arenas"), String(localized: "Retro Cabinet, Rooftop Dusk and Midnight Pier"))
                        perk("basketball.fill", String(localized: "Four more balls"), String(localized: "Retro Stripe, Glow Orb, Chrome and Sunset"))
                        perk("timer", String(localized: "Overtime mode"), String(localized: "30 seconds, every basket adds two more"))
                        perk("arrow.left.and.right", String(localized: "Drift mode"), String(localized: "The hoop glides for the whole minute"))
                    }
                    .padding(16)
                    .glass(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Button {
                        Task { await store.buy(); if store.pro { dismiss() } }
                    } label: {
                        Text(store.priceText.map { String(format: String(localized: "Unlock Pro · %@"), $0) } ?? String(localized: "Unlock Pro"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Neon.pink)
                    .disabled(store.busy)
                    Text("One-time purchase. No subscription.").font(.footnote).foregroundStyle(.secondary)
                    Button("Restore purchase") { Task { await store.restore() } }.font(.footnote)
                    if let m = store.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func perk(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Neon.cyan).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
