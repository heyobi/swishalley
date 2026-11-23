import CoreHaptics
import UIKit

/// A haptic for every contact: floor bounces scale with speed, the rim is sharp, the board a dull knock,
/// a swish a light double tick.
final class Haptics {
    static let shared = Haptics()

    var enabled: Bool { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }

    private var engine: CHHapticEngine?
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private var lastAt: CFTimeInterval = 0

    private init() {
        [light, soft, rigid, heavy].forEach { $0.prepare() }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.playsHapticsOnly = true
        engine?.isAutoShutdownEnabled = true
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
    }

    private func play(_ events: [CHHapticEvent]) -> Bool {
        guard let engine, let pattern = try? CHHapticPattern(events: events, parameters: []) else { return false }
        do {
            try engine.start()
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
            return true
        } catch { return false }
    }

    private func tick(_ i: Float, _ s: Float, at t: TimeInterval = 0) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: max(0, min(1, i))),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: max(0, min(1, s)))], relativeTime: t)
    }

    /// Too many taps at once blur together; keep at most one every 25 ms.
    private func allowed() -> Bool {
        let now = CACurrentMediaTime()
        if now - lastAt < 0.025 { return false }
        lastAt = now
        return true
    }

    func bounce(_ speed: Float) {
        guard enabled, allowed() else { return }
        let i = min(1, 0.25 + speed * 0.5)
        if !play([tick(i, 0.25)]) { soft.impactOccurred(intensity: CGFloat(i)) }
    }

    func rim(_ speed: Float) {
        guard enabled, allowed() else { return }
        let i = min(1, 0.45 + speed * 0.4)
        if !play([tick(i, 0.95), tick(i * 0.4, 0.9, at: 0.05)]) { rigid.impactOccurred(intensity: CGFloat(i)) }
    }

    func board(_ speed: Float) {
        guard enabled, allowed() else { return }
        let i = min(1, 0.35 + speed * 0.4)
        if !play([tick(i, 0.45)]) { rigid.impactOccurred(intensity: CGFloat(i * 0.8)) }
    }

    func glass(_ speed: Float) {
        guard enabled, allowed() else { return }
        if !play([tick(min(1, 0.4 + speed * 0.4), 0.7)]) { rigid.impactOccurred() }
    }

    func swish() {
        guard enabled else { return }
        if !play([tick(0.5, 0.6), tick(0.8, 0.85, at: 0.07)]) { light.impactOccurred() }
    }

    func launch(_ power: Float) {
        guard enabled, allowed() else { return }
        if !play([tick(min(1, 0.2 + power * 0.25), 0.5)]) { light.impactOccurred(intensity: 0.5) }
    }

    func fire() {
        guard enabled else { return }
        let rumble = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)], relativeTime: 0, duration: 0.35)
        if !play([rumble, tick(1, 0.8, at: 0.36)]) { heavy.impactOccurred() }
    }

    func buzzer() {
        guard enabled else { return }
        let rumble = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15)], relativeTime: 0, duration: 0.5)
        if !play([rumble]) { heavy.impactOccurred() }
    }

    func tap() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.6)
    }
}
