import AVFoundation
import Foundation

/// 空間オーディオで障害物の方向を知らせるための軽量プレイヤ。
///
/// `AVAudioEnvironmentNode` をエンジンに繋ぎ、水平オフセット（-1 左 / +1 右）
/// とユーザーからの距離を使って短いクリック音を定位再生する。
final class SpatialAudioService {

    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let player = AVAudioPlayerNode()
    private var clickBuffer: AVAudioPCMBuffer?

    init() {
        setupEngine()
    }

    /// 水平 -1..+1 / 距離 [m] に応じてクリック音を 1 発鳴らす。
    func cue(horizontalOffset: Float, distance: Float) {
        guard let buffer = clickBuffer else { return }

        // 簡易ヘッド座標系: +X = 右, +Z = 前方 (ユーザー基準)。
        let x = horizontalOffset * distance
        let z = max(0.3, distance)
        player.position = AVAudio3DPoint(x: x, y: 0, z: z)

        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    private func setupEngine() {
        engine.attach(environment)
        engine.attach(player)

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        engine.connect(player, to: environment, format: format)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)

        player.renderingAlgorithm = .HRTFHQ
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)

        clickBuffer = Self.generateClickBuffer(sampleRate: 44_100)

        do {
            try engine.start()
        } catch {
            NSLog("[SpatialAudioService] engine start failed: \(error)")
        }
    }

    /// 12ms の正弦波クリック音を合成したバッファを作る。
    private static func generateClickBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(sampleRate * 0.012)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        guard let channel = buffer.floatChannelData?[0] else { return nil }
        let frequency = 880.0
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let envelope = 1.0 - Double(i) / Double(frameCount) // リニア減衰
            channel[i] = Float(sin(2 * .pi * frequency * t) * envelope * 0.6)
        }
        return buffer
    }
}
