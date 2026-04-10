import CoreGraphics
import Foundation

/// 物体検知の 1 件分の結果。
struct DetectionResult: Identifiable, Hashable {
    let id = UUID()
    /// YOLO ラベル（例: "bicycle", "person"）。
    let label: String
    /// 0.0 〜 1.0 の確信度。
    let confidence: Float
    /// カメラフレーム内の正規化されたバウンディングボックス（Vision 座標系）。
    let normalizedBoundingBox: CGRect
    /// LiDAR から取得した推定距離 [m]。計測不能時は nil。
    let distanceMeters: Float?
    /// ブロック中心からの水平オフセット [-1, 1]（左: -1, 右: +1）。
    let horizontalOffset: CGFloat

    /// 点字ブロックの経路上に載っているとみなすかどうか。
    /// `BrailleBlockDetector` から渡されるマスクと重なり具合で決定される。
    let intersectsBrailleBlock: Bool

    /// 発話時に使う自然な距離表現（例: "約3メートル先"）。
    var spokenDistance: String {
        guard let distanceMeters else { return "近く" }
        switch distanceMeters {
        case ..<1.5:  return "すぐ前"
        case ..<3.0:  return "約2メートル先"
        case ..<5.0:  return "約4メートル先"
        case ..<8.0:  return "数メートル先"
        default:      return "遠方"
        }
    }

    /// 発話時に使う方向表現（例: "右前方"）。
    var spokenDirection: String {
        switch horizontalOffset {
        case ..<(-0.33): return "左前方"
        case ..<0.33:    return "正面"
        default:         return "右前方"
        }
    }
}
