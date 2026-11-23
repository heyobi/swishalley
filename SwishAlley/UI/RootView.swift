import SwiftUI
import StoreKit

enum SheetKind: String, Identifiable, Equatable {
    case settings, locker, paywall
    var id: String { rawValue }
}

extension View {
    /// Liquid Glass on iOS 26 and later, a thin material before.
    @ViewBuilder func glass<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(shape.fill(.ultraThinMaterial))
        }
    }

    /// Places a view exactly on a window rectangle, turned so that its player reads it upright.
    func place(_ r: CGRect, rotation: Double = 0) -> some View {
        let sideways = abs(rotation.truncatingRemainder(dividingBy: 180)) == 90
        return self
            .frame(width: sideways ? r.height : r.width, height: sideways ? r.width : r.height)
            .rotationEffect(.degrees(rotation))
            .position(x: r.midX, y: r.midY)
    }
}

struct RootView: View {
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var store: Store
    @Environment(\.requestReview) private var requestReview
    @State private var sheet: SheetKind?
    @State private var cameraCard = false
    @AppStorage("cameraCardDismissed") private var cameraCardDismissed = false

    var body: some View {
        stage
            .sheet(item: $sheet) { s in sheetView(s) }
            .onChange(of: engine.askReview) { _, ask in if ask { requestReview(); engine.askReview = false } }
            .onChange(of: engine.shotSheet) { _, s in sheet = s; if s != nil { engine.shotSheet = nil } }
            .task {
                if ShotsTour.active { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if engine.tracking == .needsPermission && !cameraCardDismissed && engine.screen == .menu {
                    withAnimation(.spring(duration: 0.5)) { cameraCard = true }
                }
            }
    }

    private var stage: some View {
        GeometryReader { proxy in
            let fold = foldFrame(proxy)
            ZStack {
                GameContainer(engine: engine, fold: fold)
                    .ignoresSafeArea()
                overlay
            }
        }
        .ignoresSafeArea()
        .modifier(HingeReader(engine: engine))
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    @ViewBuilder
    private func sheetContent(_ s: SheetKind) -> some View {
        switch s {
        case .settings: SettingsSheet()
        case .locker: LockerSheet(sheet: $sheet)
        case .paywall: PaywallSheet()
        }
    }

    private func sheetView(_ s: SheetKind) -> some View {
        let large: Set<PresentationDetent> = [.large]
        return sheetContent(s)
            .environmentObject(engine)
            .environmentObject(store)
            .presentationDetents(large)
            .presentationBackground(.regularMaterial)
    }

    // MARK: Overlay (every rectangle comes from the layout and stays clear of the crease)

    @ViewBuilder
    private var overlay: some View {
        if let l = engine.layout {
            ZStack {
                if ShotsTour.foldGuide, let ng = l.hud.noGo {
                    // Debug/screenshot aid: the region kept free of interface.
                    Rectangle().fill(Color.red.opacity(0.18)).place(ng)
                }
                switch engine.screen {
                case .menu: menu(l)
                case .playing: playing(l)
                case .results: results(l)
                }
                banners(l)
            }
        }
    }

    @ViewBuilder
    private func menu(_ l: SceneLayout) -> some View {
        if let b = l.hud.banner, l.presentation == .stage {
            TitleView(compact: b.height < 220).place(b)
        }
        MenuView(sheet: $sheet, showTitle: l.presentation != .stage, cameraCard: $cameraCard, cameraCardDismissed: $cameraCardDismissed)
            .place(l.hud.menu)
    }

    @ViewBuilder
    private func playing(_ l: SceneLayout) -> some View {
        if let m = engine.match {
            ForEach(Array(l.hud.panels.enumerated()), id: \.offset) { _, p in
                ScorePanel(match: m, player: p.player, sideways: abs(p.rotation) == 90, pause: { engine.pauseToMenu() })
                    .place(p.rect, rotation: p.rotation)
            }
            if m.phase == .countdown {
                CountdownView(clock: m.clock).place(l.hud.shootZones.first ?? l.hud.menu)
                if l.presentation == .duel, l.hud.shootZones.count > 1 {
                    CountdownView(clock: m.clock).place(l.hud.shootZones[1], rotation: l.hud.panels[1].rotation)
                }
            }
            if l.presentation == .duel, engine.hasHinge, (engine.shownHinge ?? 180) < 160 {
                HintCard(text: String(localized: "Lay iPhone Duo flat between you, one half each."))
                    .place(l.hud.menu.insetBy(dx: 0, dy: max(0, (l.hud.menu.height - 90) / 2)))
            }
        }
    }

    @ViewBuilder
    private func results(_ l: SceneLayout) -> some View {
        if let r = engine.results {
            ResultsCard(results: r, player: 0, again: { engine.playAgain() }, close: { engine.closeResults() })
                .place(l.hud.menu)
            if r.mode.isDuel, l.hud.shootZones.count > 1, l.hud.panels.count > 1 {
                DuelResultBadge(results: r, player: 1).place(l.hud.shootZones[1].insetBy(dx: 12, dy: 12), rotation: l.hud.panels[1].rotation)
            }
        }
    }

    @ViewBuilder
    private func banners(_ l: SceneLayout) -> some View {
        ForEach(engine.banners) { b in
            let (rect, rot) = bannerSpot(b, l)
            BannerView(banner: b)
                .place(rect, rotation: rot)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    /// Banners go where the player looks: the upright half on the stage, the player's own half in a duel.
    private func bannerSpot(_ b: Banner, _ l: SceneLayout) -> (CGRect, Double) {
        if l.presentation == .duel, b.player >= 0, b.player < l.hud.shootZones.count {
            let z = l.hud.shootZones[b.player]
            return (z.insetBy(dx: 0, dy: z.height * 0.3), l.hud.panels[b.player].rotation)
        }
        if let area = l.hud.banner, l.presentation == .stage {
            return (area.insetBy(dx: 0, dy: area.height * 0.32), 0)
        }
        let z = l.hud.menu
        return (CGRect(x: z.minX, y: z.minY + z.height * 0.18, width: z.width, height: 120), 0)
    }
}

/// Feeds the iPhone Duo hinge (iOS 27.1) into the engine: every angle sample, not only open/closed.
struct HingeReader: ViewModifier {
    let engine: Engine

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, ctx in
                let h: DeviceHinge? = ctx.hinge
                guard let h else { return }
                engine.hingeChanged(angle: h.angle.degrees, closed: h.status == .closed)
            }
        } else {
            content
        }
    }
}

/// The division (fold) reserved region of an iPhone Duo in this geometry's coordinates, if any. Never assume the
/// middle of the screen: the frame comes from the system.
func foldFrame(_ proxy: GeometryProxy) -> CGRect? {
    if #available(iOS 27.1, *) {
        if let d = proxy.reservedRegions(kind: .division, options: [.includeInactive]).first {
            return d.frame
        }
    }
    return nil
}
