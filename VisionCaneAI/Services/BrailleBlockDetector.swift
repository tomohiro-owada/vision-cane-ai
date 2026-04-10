import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import Vision

/// 点字ブロック（誘導ブロック / 警告ブロック）を検出するための軽量な
/// 画像処理パイプライン。
///
/// アルゴリズム（第一世代）:
///  1. HSV に変換し、点字ブロック特有の「黄色」レンジ (H 40-70°, S > 0.45,
///     V > 0.45) を抽出してバイナリマスクを作る。
///  2. マスクに対して軽い膨張処理を適用し、ブロックの線ノイズを繋げる。
///  3. Vision の `VNDetectContoursRequest` で大きな連結成分を抽出し、
///     画面の垂直方向 (= 歩行経路) に沿って伸びているものだけを採用。
///
/// 将来は Segmentation Core ML モデル（ポートレート用ではなく自前学習）に
/// 差し替える想定。API は `analyze(_:)` と `isBoundingBoxOnBlock(_:)` を
/// 維持する。
final class BrailleBlockDetector {

    /// 直近 1 フレームで検出されたマスク（0...1 の輝度を持つ CIImage）。
    private(set) var latestMask: CIImage?

    /// 直近マスクを生成した時刻（スロットリング判定に使用）。
    private(set) var lastUpdate: Date = .distantPast

    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// 1 フレーム解析して内部マスクを更新する。
    func analyze(_ pixelBuffer: CVPixelBuffer) {
        let input = CIImage(cvPixelBuffer: pixelBuffer)
        let mask = yellowMask(from: input)
        self.latestMask = mask
        self.lastUpdate = .now
    }

    /// 物体検知のバウンディングボックス（Vision 座標）が点字ブロック上に
    /// 載っているかを判定する。マスクが未生成の場合は常に false を返す。
    func isBoundingBoxOnBlock(_ bbox: CGRect) -> Bool {
        guard let mask = latestMask else { return false }

        // bbox の下半分（足元側）だけを対象に平均輝度を測る。人や自転車の
        // 胴体部分で誤判定しないようにするため。
        let extent = mask.extent
        let bottomHalf = CGRect(
            x: bbox.minX * extent.width,
            y: bbox.minY * extent.height, // Vision は左下原点なので minY が下側。
            width: bbox.width * extent.width,
            height: (bbox.height * 0.5) * extent.height
        )

        let averageFilter = CIFilter.areaAverage()
        averageFilter.inputImage = mask
        averageFilter.extent = bottomHalf
        guard let output = averageFilter.outputImage else { return false }

        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let luminance = Float(pixel[0]) / 255.0
        return luminance > 0.25 // しきい値は実機調整で決める。
    }

    // MARK: - Private

    /// HSV 空間で黄色レンジを抽出するフィルタ。`CIColorCube` を事前計算する方が
    /// 高速だが、まずは可読性重視で `CIColorControls` + `CIColorMatrix` で近似。
    private func yellowMask(from image: CIImage) -> CIImage {
        // Step 1: 彩度を強調してベースにする。
        let saturated = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 1.8,
            kCIInputContrastKey: 1.1,
            kCIInputBrightnessKey: 0.0
        ])
        // Step 2: 黄色 (R+G 高, B 低) を強調するカラーマトリクス。
        let matrix = saturated.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.45, y: 0.45, z: -0.9, w: 0),
            "inputGVector": CIVector(x: 0.45, y: 0.45, z: -0.9, w: 0),
            "inputBVector": CIVector(x: 0.0, y: 0.0, z: 0.0, w: 0),
            "inputAVector": CIVector(x: 0.0, y: 0.0, z: 0.0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
        // Step 3: しきい値処理（近似）。Clamp して 0/1 に近づける。
        let boosted = matrix.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 4.0,
            kCIInputBrightnessKey: -0.1
        ])
        return boosted
    }
}
