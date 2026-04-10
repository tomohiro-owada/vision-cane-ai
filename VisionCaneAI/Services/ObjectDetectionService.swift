import CoreML
import CoreVideo
import Foundation
import Vision

/// YOLOv10 の Core ML パッケージをロードし、カメラフレーム 1 枚から
/// 物体検知結果の配列を返すサービス。15fps 前後でのリアルタイム推論を想定。
///
/// - Note: Core ML モデルは App Bundle に `YOLOv10.mlpackage` として
///   同梱される前提。存在しない場合でも初期化は成功し、`detect` 呼び出し時に
///   空配列を返す（フェイルセーフ）。
final class ObjectDetectionService {

    /// 歩行ガイドに意味のあるラベルのみ保持する。YOLOv10 は COCO 80 クラス
    /// を出すが、信号機・人・自転車・犬・椅子など歩行で重要なものに限定する
    /// ことで発話の冗長さと誤検知を抑える。
    private static let allowedLabels: Set<String> = [
        "person", "bicycle", "car", "motorcycle", "bus", "truck",
        "traffic light", "stop sign", "bench", "chair", "suitcase",
        "backpack", "handbag", "dog", "cat", "potted plant", "bottle"
    ]

    private let confidenceThreshold: Float = 0.45
    private var visionModel: VNCoreMLModel?

    init() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all // Neural Engine 優先。
            // Bundle 内のモデル URL。存在しなければ nil のままとする。
            if let url = Bundle.main.url(forResource: "YOLOv10", withExtension: "mlpackage") {
                let compiled = try MLModel.compileModel(at: url)
                let mlModel = try MLModel(contentsOf: compiled, configuration: config)
                self.visionModel = try VNCoreMLModel(for: mlModel)
            }
        } catch {
            NSLog("[ObjectDetectionService] failed to load YOLO model: \(error.localizedDescription)")
            self.visionModel = nil
        }
    }

    /// 1 フレームを同期的に解析する。呼び出し側はバックグラウンドキューで呼ぶこと。
    func detect(
        in pixelBuffer: CVPixelBuffer,
        distanceProvider: (CGPoint) -> Float?,
        onBrailleBlock: (CGRect) -> Bool
    ) -> [DetectionResult] {
        guard let visionModel else { return [] }

        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        do {
            try handler.perform([request])
        } catch {
            NSLog("[ObjectDetectionService] perform failed: \(error)")
            return []
        }

        guard let observations = request.results as? [VNRecognizedObjectObservation] else {
            return []
        }

        return observations.compactMap { obs -> DetectionResult? in
            guard let top = obs.labels.first,
                  top.confidence >= confidenceThreshold,
                  Self.allowedLabels.contains(top.identifier) else {
                return nil
            }

            let bbox = obs.boundingBox // Vision 座標系 (左下原点, 0...1)
            let center = CGPoint(x: bbox.midX, y: 1.0 - bbox.midY) // 上原点に補正
            let distance = distanceProvider(center)
            let horizontal = (bbox.midX - 0.5) * 2.0 // -1 ... +1
            let onBlock = onBrailleBlock(bbox)

            return DetectionResult(
                label: top.identifier,
                confidence: top.confidence,
                normalizedBoundingBox: bbox,
                distanceMeters: distance,
                horizontalOffset: horizontal,
                intersectsBrailleBlock: onBlock
            )
        }
    }
}
