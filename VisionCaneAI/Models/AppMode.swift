import Foundation

/// アプリの動作モード。
///
/// - active:  連続スキャンし、重要な変化があったときだけ発話する。
/// - onDemand: ユーザーの操作 / 音声コマンドをトリガーに一度だけ状況を解析。
/// - paused:  推論・発話を完全停止。LiDAR 触覚警告のみ継続（フェイルセーフ）。
enum AppMode: String, CaseIterable, Identifiable {
    case active
    case onDemand
    case paused

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .active:    return "アクティブ・ガイド"
        case .onDemand:  return "オンデマンド・サーチ"
        case .paused:    return "一時停止"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .active:
            return "連続スキャンし、重要な変化のみ発話します。"
        case .onDemand:
            return "画面をダブルタップするか、音声コマンドで周囲を解析します。"
        case .paused:
            return "AI 推論を停止します。最短距離の触覚警告のみ継続します。"
        }
    }
}
