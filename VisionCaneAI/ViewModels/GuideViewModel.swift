import Combine
import CoreVideo
import Foundation
import SwiftUI

/// アプリ全体の頭脳。AR / 物体検知 / 点字ブロック / LLM / 発話 / 触覚 /
/// 音声コマンド / サーマル監視を束ね、UI と接続するための ObservableObject。
///
/// 主な責務:
///  1. ARLidarService からフレームを受け取り、2 つのレートで流し込む。
///     - YOLO 検知と BrailleBlockDetector: ThermalMonitor の `yoloHz`。
///     - SceneNarrator (Gemma 4):           ThermalMonitor の `llmHz`。
///  2. 検知結果 → GuideEvent への変換（距離・確信度・ブロック上の有無で重み付け）。
///  3. イベントを発話・触覚・空間音に配信。
///  4. 音声コマンド受付と `AppMode` 遷移。
@MainActor
final class GuideViewModel: ObservableObject {

    // MARK: - Public state

    @Published var mode: AppMode = .active
    @Published var lastEvent: GuideEvent?
    @Published var lastDescription: String = "準備中..."
    @Published var isLidarAvailable: Bool = false
    @Published var batteryLevel: Float = 1.0
    @Published var profileLabel: String = "nominal"

    // MARK: - Services

    private let ar = ARLidarService()
    private let yolo = ObjectDetectionService()
    private let braille = BrailleBlockDetector()
    private let narrator = SceneNarrator()
    private let speech = SpeechService()
    private let voice = VoiceCommandService()
    private let haptic = HapticService()
    private let spatial = SpatialAudioService()
    private let thermal = ThermalMonitor()

    // MARK: - Internal state

    private var cancellables = Set<AnyCancellable>()
    private var yoloThrottle = Throttle(interval: 1.0 / 15.0)
    private var llmThrottle  = Throttle(interval: 1.0 / 1.5)
    private var speechThrottle = Throttle(interval: 2.0)
    private let yoloQueue = DispatchQueue(label: "ai.visioncane.yolo", qos: .userInitiated)

    init() {
        isLidarAvailable = ar.isLidarAvailable
        wireThermalProfile()
        wireFramePipeline()
    }

    // MARK: - Lifecycle

    func start() {
        ar.start()
        Task { await narrator.loadModel() }
        voice.requestAuthorizationAndStart { [weak self] command in
            Task { @MainActor in self?.handle(command: command) }
        }
    }

    func stop() {
        ar.pause()
        voice.stop()
        speech.stopAll()
    }

    func setMode(_ newMode: AppMode) {
        mode = newMode
        if newMode == .paused {
            speech.stopAll()
        }
    }

    /// 画面タップからの「オンデマンド解説」要求。
    func requestOnDemandDescription() {
        let snapshot = SceneNarrator.Snapshot(
            detections: latestDetections,
            imageData: nil,
            cameraHeading: nil
        )
        Task { [weak self] in
            guard let self else { return }
            let text = await self.narrator.describe(snapshot)
            self.lastDescription = text
            self.speech.speak(GuideEvent(
                severity: .info,
                spokenText: text,
                horizontalOffset: 0,
                hapticIntensity: 0,
                timestamp: .now
            ))
        }
    }

    // MARK: - Wiring

    private func wireThermalProfile() {
        thermal.$profile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                guard let self else { return }
                self.yoloThrottle = Throttle(interval: 1.0 / profile.yoloHz)
                if profile.llmHz > 0 {
                    self.llmThrottle = Throttle(interval: 1.0 / profile.llmHz)
                } else {
                    self.llmThrottle = Throttle(interval: .greatestFiniteMagnitude)
                }
                self.profileLabel = Self.label(for: profile)
            }
            .store(in: &cancellables)

        thermal.$batteryLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$batteryLevel)
    }

    private func wireFramePipeline() {
        ar.framePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                // ARSessionDelegate は既にメインスレッドで呼ばれるが、MainActor
                // isolation を明示するために Task で包む。
                Task { @MainActor [weak self] in
                    guard let self, self.mode == .active else { return }
                    self.handle(frame: frame)
                }
            }
            .store(in: &cancellables)
    }

    private var latestFrame: ARLidarService.Frame?
    private var latestDetections: [DetectionResult] = []

    private func handle(frame: ARLidarService.Frame) {
        latestFrame = frame

        // YOLO と点字ブロック検出を同一キューで直列化する（マスク更新と
        // 読み出しの競合を回避するため）。
        if yoloThrottle.shouldFire() {
            let braille = self.braille
            let yolo = self.yolo
            let ar = self.ar
            weak var weakSelf = self
            yoloQueue.async {
                braille.analyze(frame.pixelBuffer)
                let detections = yolo.detect(
                    in: frame.pixelBuffer,
                    distanceProvider: { normalizedPoint in
                        ar.distance(atNormalizedPoint: normalizedPoint, in: frame)
                    },
                    onBrailleBlock: { bbox in
                        braille.isBoundingBoxOnBlock(bbox)
                    }
                )
                Task { @MainActor in
                    guard let vm = weakSelf else { return }
                    vm.latestDetections = detections
                    vm.consume(detections: detections)
                }
            }
        }

        // 3. LLM シーン説明（さらに粗いレート）
        if llmThrottle.shouldFire() {
            let snapshot = SceneNarrator.Snapshot(
                detections: latestDetections,
                imageData: nil, // 本番実装ではここでリサイズ済み JPEG を渡す。
                cameraHeading: nil
            )
            Task { [weak self] in
                guard let self else { return }
                let text = await self.narrator.describe(snapshot)
                self.lastDescription = text
            }
        }
    }

    private func consume(detections: [DetectionResult]) {
        guard let event = pickBestEvent(from: detections) else { return }
        lastEvent = event

        // 触覚は常に（フェイルセーフ）発火
        if let nearestDistance = detections.compactMap(\.distanceMeters).min(),
           nearestDistance < 2.5 {
            haptic.warn(distance: nearestDistance)
        }

        guard mode != .paused else { return }

        // 発話は severity と time-gap でゲーティング。
        if event.severity >= .warning || speechThrottle.shouldFire() {
            speech.speak(event)
            spatial.cue(
                horizontalOffset: event.horizontalOffset,
                distance: Float(max(0.5, Double(event.hapticIntensity) * 5.0))
            )
        }
    }

    /// 検知結果の中から最重要の 1 件を選び、GuideEvent に変換する。
    private func pickBestEvent(from detections: [DetectionResult]) -> GuideEvent? {
        let onBlock = detections.filter(\.intersectsBrailleBlock)
        let candidates = onBlock.isEmpty ? detections : onBlock
        guard let target = candidates.min(by: { ($0.distanceMeters ?? .greatestFiniteMagnitude)
                                               < ($1.distanceMeters ?? .greatestFiniteMagnitude) }) else {
            return nil
        }

        let distance = target.distanceMeters ?? 6.0
        let severity: GuideEvent.Severity
        switch distance {
        case ..<1.2:  severity = .critical
        case ..<2.5:  severity = .warning
        case ..<5.0:  severity = target.intersectsBrailleBlock ? .caution : .info
        default:      severity = .info
        }

        let spoken: String
        if target.intersectsBrailleBlock {
            spoken = "\(target.spokenDistance)の点字ブロック上に\(Self.jp(label: target.label))"
        } else {
            spoken = "\(target.spokenDirection)\(target.spokenDistance)に\(Self.jp(label: target.label))"
        }

        return GuideEvent(
            severity: severity,
            spokenText: spoken,
            horizontalOffset: Float(target.horizontalOffset),
            hapticIntensity: Float(max(0.2, 1.0 - Double(distance) / 6.0)),
            timestamp: .now
        )
    }

    // MARK: - Voice commands

    private func handle(command: VoiceCommandService.Command) {
        switch command {
        case .describeFront:
            requestOnDemandDescription()
        case .findPlace(let place):
            // 本来はオブジェクト履歴から place を検索する。現段階では LLM 任せ。
            let prompt = "\(place)の入り口を教えて"
            lastDescription = prompt
            requestOnDemandDescription()
        case .raw:
            break
        }
    }

    // MARK: - Helpers

    private static func label(for profile: ThermalMonitor.Profile) -> String {
        switch profile {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        default:        return "custom"
        }
    }

    private static func jp(label: String) -> String {
        switch label {
        case "person": return "人がいます"
        case "bicycle": return "自転車があります"
        case "car", "motorcycle", "bus", "truck": return "車両があります"
        case "traffic light": return "信号機があります"
        case "stop sign": return "停止標識があります"
        case "bench": return "ベンチがあります"
        case "chair": return "椅子があります"
        case "suitcase": return "スーツケースがあります"
        case "backpack", "handbag": return "荷物があります"
        case "dog": return "犬がいます"
        case "cat": return "猫がいます"
        case "potted plant": return "植木があります"
        case "bottle": return "ボトルがあります"
        default: return "\(label)があるかもしれません"
        }
    }
}
