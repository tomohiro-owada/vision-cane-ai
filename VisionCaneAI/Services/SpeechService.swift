import AVFoundation
import Foundation

/// 音声合成（TTS）ラッパ。発話の優先度制御と重複抑制を担当する。
///
/// - severity が高いイベントは前の発話をキャンセルして即時発話する。
/// - 直前の発話と全く同じ本文は 10 秒以内なら抑制し、連呼を避ける。
/// - AVSpeechSynthesizer の `mixToTelephonyUplink` / `duckOthers` を利用し、
///   骨伝導イヤホンの環境音を遮らない設計。
final class SpeechService: NSObject {

    private let synthesizer = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()
    private var lastSpoken: (text: String, at: Date)?

    override init() {
        super.init()
        configureAudioSession()
        synthesizer.delegate = self
    }

    func speak(_ event: GuideEvent) {
        if let last = lastSpoken,
           last.text == event.spokenText,
           Date.now.timeIntervalSince(last.at) < 10 {
            return // 重複抑制
        }
        if event.severity >= .warning {
            synthesizer.stopSpeaking(at: .immediate)
        } else if synthesizer.isSpeaking {
            return // 低優先の発話は割り込まない。
        }

        let utterance = AVSpeechUtterance(string: event.spokenText)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.52 // 標準より気持ちゆっくり。
        utterance.pitchMultiplier = event.severity >= .warning ? 1.15 : 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.0

        synthesizer.speak(utterance)
        lastSpoken = (event.spokenText, .now)
    }

    /// 緊急停止用。`AppMode.paused` への遷移時に呼び出す。
    func stopAll() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func configureAudioSession() {
        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .allowBluetoothA2DP, .allowAirPlay]
            )
            try session.setActive(true, options: [])
        } catch {
            NSLog("[SpeechService] audio session setup failed: \(error)")
        }
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    // 空実装。必要に応じて開始・終了のフックを追加する。
}
