import CoreHaptics
import Foundation
import UIKit

/// Core Haptics を使った触覚フィードバック。
///
/// - LLM や TTS が落ちていてもバイブレーションだけは継続する「最後の防波堤」。
/// - `intensity` が高いほど強く・速く振動するパターンを生成する。
final class HapticService {

    private var engine: CHHapticEngine?

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.stoppedHandler = { _ in /* no-op */ }
            engine.resetHandler = { [weak self] in try? self?.engine?.start() }
            try engine.start()
            self.engine = engine
        } catch {
            NSLog("[HapticService] engine init failed: \(error)")
        }
    }

    /// 近接警告パルス。距離 [m] に応じてパルス間隔とシャープネスを調整する。
    func warn(distance: Float) {
        guard let engine else {
            // Core Haptics 非対応端末の場合は通常の振動で代替。
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            return
        }

        let intensity = min(1.0, max(0.2, 1.0 - distance / 6.0))
        let sharpness: Float = distance < 1.5 ? 1.0 : 0.5
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            NSLog("[HapticService] play failed: \(error)")
        }
    }
}
