import SwiftUI
import SceneKit

/// Scene views over one shared scene, one per viewport of the layout (two on a half-open iPhone Duo and in a
/// duel, one elsewhere), framed exactly on the window rectangles the layout gives (so a view never spans the
/// crease). A display link drives the engine once per frame; touches go to the engine in window points.
final class GameView: UIView {
    let engine: Engine
    private var views: [SCNView] = []
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var shownLayout: SceneLayout?
    var fold: CGRect? { didSet { if fold != oldValue { setNeedsLayout() } } }

    init(engine: Engine) {
        self.engine = engine
        super.init(frame: .zero)
        backgroundColor = .black
        isMultipleTouchEnabled = true
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Basketball lane")
        accessibilityHint = String(localized: "Flick up toward the hoop to shoot.")
        accessibilityTraits = .allowsDirectInteraction
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let l = CADisplayLink(target: LinkProxy(self), selector: #selector(LinkProxy.step(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var g = engine.geometry
        g.size = bounds.size
        g.fold = fold
        let i = window?.safeAreaInsets ?? safeAreaInsets
        g.insets = Insets(top: i.top, left: i.left, bottom: i.bottom, right: i.right)
        g.isPad = traitCollection.userInterfaceIdiom == .pad
        g.nativeScale = window?.screen.nativeScale ?? 3
        g.interface = window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        if g != engine.geometry { engine.geometry = g }
        arrange()
    }

    fileprivate func step(_ link: CADisplayLink) {
        let t = link.targetTimestamp
        let dt = lastTime > 0 ? Float(t - lastTime) : 1 / 60
        lastTime = t
        engine.tick(t: t, dt: dt)
        arrange()
    }

    private func makeView() -> SCNView {
        let v = SCNView(frame: .zero)
        v.scene = engine.gym.scene
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 120
        v.rendersContinuously = true
        v.isPlaying = true
        v.backgroundColor = .black
        v.isUserInteractionEnabled = false
        v.isJitteringEnabled = false
        addSubview(v)
        return v
    }

    /// Frames the scene views on the layout's viewports.
    private func arrange() {
        guard let l = engine.layout else { return }
        if let s = shownLayout, s.viewports.map(\.rect) == l.viewports.map(\.rect) { return }
        shownLayout = l
        while views.count < l.viewports.count { views.append(makeView()) }
        for (i, v) in views.enumerated() {
            if i < l.viewports.count {
                v.isHidden = false
                v.frame = l.viewports[i].rect
                if i < engine.gym.cameras.count { v.pointOfView = engine.gym.cameras[i] }
            } else {
                v.isHidden = true
            }
        }
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { engine.touchBegan(ObjectIdentifier(t), at: t.location(in: self), t: t.timestamp) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            // Coalesced touches give the flick's speed at the full sensor rate.
            for c in event?.coalescedTouches(for: t) ?? [t] {
                engine.touchMoved(ObjectIdentifier(t), at: c.location(in: self), t: c.timestamp)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { engine.touchEnded(ObjectIdentifier(t), at: t.location(in: self), t: t.timestamp) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { engine.touchCancelled(ObjectIdentifier(t)) }
    }
}

@MainActor
private final class LinkProxy: NSObject {
    weak var view: GameView?
    init(_ v: GameView) { view = v }
    @objc func step(_ link: CADisplayLink) {
        guard let view else { link.invalidate(); return }
        view.step(link)
    }
}

struct GameContainer: UIViewRepresentable {
    let engine: Engine
    let fold: CGRect?

    func makeUIView(context: Context) -> GameView { GameView(engine: engine) }
    func updateUIView(_ v: GameView, context: Context) { v.fold = fold }
}
