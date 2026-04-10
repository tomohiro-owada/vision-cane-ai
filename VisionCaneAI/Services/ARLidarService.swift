import ARKit
import Combine
import CoreVideo
import Foundation
import simd

/// LiDAR 搭載 iPhone（15 Pro / 16 Pro 以降）向けに ARKit セッションを立ち上げ、
/// カメラフレームとシーン深度を他サービスへ配信するアダプタ。
///
/// - 高速検知 (YOLO) と LLM 推論の両方がこのサービスからフレームを受け取る。
/// - `frameSemantics` に `.sceneDepth` を追加することで LiDAR からの
///   距離マップを取得できる。ハードウェアが非搭載の場合は `sceneDepth` を
///   フォールバックで落とし、カメラのみで動作する。
final class ARLidarService: NSObject, ObservableObject {

    struct Frame {
        let pixelBuffer: CVPixelBuffer
        let depthMap: CVPixelBuffer?
        let confidenceMap: CVPixelBuffer?
        let cameraTransform: simd_float4x4
        let intrinsics: simd_float3x3
        let timestamp: TimeInterval
    }

    /// 最新フレームの publisher。各サブスクライバ (YOLO / LLM / 点字 BD) は
    /// 必要なフレームレートに `throttle` を掛けて購読する。
    let framePublisher = PassthroughSubject<Frame, Never>()

    /// LiDAR が利用可能か。初期化時に 1 回だけ計算される。
    let isLidarAvailable: Bool

    private let session = ARSession()
    private let configuration: ARWorldTrackingConfiguration

    override init() {
        self.configuration = ARWorldTrackingConfiguration()
        self.isLidarAvailable = ARWorldTrackingConfiguration
            .supportsFrameSemantics(.sceneDepth)

        if isLidarAvailable {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        configuration.worldAlignment = .gravity
        configuration.environmentTexturing = .none
        configuration.planeDetection = []
        configuration.isAutoFocusEnabled = true

        super.init()
        session.delegate = self
    }

    func start() {
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func pause() {
        session.pause()
    }

    /// 与えられたスクリーン正規化座標（0...1）に対する LiDAR 距離 [m] を取得する。
    /// 深度マップが無い場合やインデックスが範囲外の場合は nil を返す。
    func distance(atNormalizedPoint point: CGPoint, in frame: Frame) -> Float? {
        guard let depthMap = frame.depthMap else { return nil }
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let x = Int(point.x * CGFloat(width))
        let y = Int(point.y * CGFloat(height))
        guard x >= 0, x < width, y >= 0, y < height else { return nil }

        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(depthMap)
        let rowStart = base.advanced(by: y * rowBytes)
        let depthPointer = rowStart.assumingMemoryBound(to: Float32.self)
        let value = depthPointer[x]
        return value.isFinite && value > 0 ? value : nil
    }
}

// MARK: - ARSessionDelegate

extension ARLidarService: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let wrapped = Frame(
            pixelBuffer: frame.capturedImage,
            depthMap: frame.sceneDepth?.depthMap,
            confidenceMap: frame.sceneDepth?.confidenceMap,
            cameraTransform: frame.camera.transform,
            intrinsics: frame.camera.intrinsics,
            timestamp: frame.timestamp
        )
        framePublisher.send(wrapped)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        // セッション失敗時もフェイルセーフ層（触覚警告）は別サービスで継続する。
        NSLog("[ARLidarService] session failed: \(error.localizedDescription)")
    }

    func sessionWasInterrupted(_ session: ARSession) {
        NSLog("[ARLidarService] session interrupted")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        start() // 割り込みからの復帰時は設定をリセットして再開。
    }
}
