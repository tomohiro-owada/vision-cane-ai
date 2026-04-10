import Foundation

/// ユーザーに通知すべき 1 件分のガイドイベント。
///
/// 物体検知単体では発火せず、`GuideViewModel` が閾値（距離・確信度・点字
/// ブロックとの重なり）を満たしたものだけを生成する。
struct GuideEvent: Identifiable, Hashable {
    enum Severity: Int, Comparable {
        case info        // 「右側にコンビニがあります」
        case caution     // 「点字ブロック上に荷物があります」
        case warning     // 「2メートル先に自転車」
        case critical    // 「すぐ前に人」

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    let id = UUID()
    let severity: Severity
    /// 発話するテキスト。ハルシネーション抑制のため、推測時は "〜かもしれません" を付与。
    let spokenText: String
    /// 空間オーディオ定位のための水平オフセット [-1, 1]。
    let horizontalOffset: Float
    /// 触覚フィードバックの強度 [0, 1]。
    let hapticIntensity: Float
    /// 発話時刻。同一内容の連続発話を抑制するために使用。
    let timestamp: Date
}
