import CoreVideo
import Foundation
import UIKit

/// MLX-Swift 上で動く Gemma 4（マルチモーダル・4bit 量子化）を呼び出し、
/// カメラフレームと物体検知結果から「遠方の状況を説明する一文」を生成する。
///
/// 本ファイルはモデルロード部分を薄く抽象化した「アダプタ」であり、実際の
/// MLX-Swift / mlx-swift-examples の API を import して差し替える前提で
/// ある。ローカル動作を止めないために、モデル未ロード時でも `describe` は
/// 軽量な決定論的なテンプレート文を返す。
///
/// - Important: クラウドへの送信は一切行わない。モデルの重みは端末ローカル
///   の `Documents/models/gemma-4-e4b-int4/` に配置される想定。
actor SceneNarrator {

    struct Snapshot {
        let detections: [DetectionResult]
        let imageData: Data?
        let cameraHeading: Float?
    }

    /// モデルロード状態。`.ready` でないときはテンプレートフォールバックに切替。
    enum State {
        case uninitialized
        case loading
        case ready
        case failed(Error)
    }

    private(set) var state: State = .uninitialized
    private let modelDirectoryName = "gemma-4-e4b-int4"

    private let systemPrompt = """
        あなたは視覚障がい者の歩行を支援する AI です。渡された画像と物体の
        一覧から、白杖が届かない数メートル先の状況を 1 文で説明してください。
        ルール:
          - 1 文、日本語、最大 40 字。
          - 確信が持てない情報は「〜かもしれません」と推測表現を使う。
          - 色・形状の細かい描写は避け、移動判断に必要な情報を優先する。
          - 数値は「約◯メートル」の形で丸める。
        """

    /// モデルをロードする。失敗しても throw せず、内部状態を `.failed` に
    /// するだけに留める（フェイルセーフ）。
    func loadModel() async {
        state = .loading
        do {
            let url = try modelURL()
            try await Self.warmUp(modelURL: url)
            state = .ready
        } catch {
            NSLog("[SceneNarrator] failed to load Gemma 4: \(error)")
            state = .failed(error)
        }
    }

    /// 1 件分の説明文を生成する。モデルが使用不可の場合はテンプレートで応答。
    func describe(_ snapshot: Snapshot) async -> String {
        switch state {
        case .ready:
            return await runInference(snapshot)
        default:
            return templateDescription(snapshot)
        }
    }

    // MARK: - Private

    private func runInference(_ snapshot: Snapshot) async -> String {
        // 実装メモ:
        //   let session = try await MLXVLM.load(modelURL: url)
        //   let response = try await session.generate(
        //       system: systemPrompt,
        //       image: snapshot.imageData,
        //       userText: buildUserPrompt(snapshot),
        //       maxTokens: 48,
        //       temperature: 0.2
        //   )
        //   return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        //
        // MLX-Swift の実際の型名はバージョンごとに変わるので、本リポジトリ
        // では挙動保証のためテンプレートを返す。差し替え時は上記の擬似コード
        // を参照のこと。
        return templateDescription(snapshot)
    }

    private func templateDescription(_ snapshot: Snapshot) -> String {
        let onBlock = snapshot.detections.filter(\.intersectsBrailleBlock)
        if let first = onBlock.min(by: { ($0.distanceMeters ?? .greatestFiniteMagnitude)
                                       < ($1.distanceMeters ?? .greatestFiniteMagnitude) }) {
            return "\(first.spokenDistance)の点字ブロック上に\(localized(label: first.label))があります"
        }
        if let nearest = snapshot.detections.min(by: { ($0.distanceMeters ?? .greatestFiniteMagnitude)
                                                     < ($1.distanceMeters ?? .greatestFiniteMagnitude) }) {
            return "\(nearest.spokenDirection)\(nearest.spokenDistance)に\(localized(label: nearest.label))かもしれません"
        }
        return "前方に目立った障害物はありません"
    }

    private func localized(label: String) -> String {
        switch label {
        case "person": return "人"
        case "bicycle": return "自転車"
        case "car", "motorcycle", "bus", "truck": return "車両"
        case "traffic light": return "信号機"
        case "stop sign": return "停止標識"
        case "bench": return "ベンチ"
        case "chair": return "椅子"
        case "suitcase": return "スーツケース"
        case "backpack", "handbag": return "荷物"
        case "dog": return "犬"
        case "cat": return "猫"
        case "potted plant": return "植木"
        case "bottle": return "ボトル"
        default: return label
        }
    }

    private func buildUserPrompt(_ snapshot: Snapshot) -> String {
        let lines = snapshot.detections.prefix(5).map { d -> String in
            let dist = d.distanceMeters.map { String(format: "%.1fm", $0) } ?? "距離不明"
            return "- \(d.label) / \(dist) / onBrailleBlock=\(d.intersectsBrailleBlock)"
        }
        return """
            周囲の物体:
            \(lines.joined(separator: "\n"))
            これらを踏まえ、歩行者への 1 文ガイドを日本語で返してください。
            """
    }

    private func modelURL() throws -> URL {
        let fm = FileManager.default
        let docs = try fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = docs.appendingPathComponent("models/\(modelDirectoryName)", isDirectory: true)
        guard fm.fileExists(atPath: dir.path) else {
            throw NSError(
                domain: "SceneNarrator",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Gemma 4 モデルが見つかりません: \(dir.path)"]
            )
        }
        return dir
    }

    private static func warmUp(modelURL: URL) async throws {
        // モデルの重みを mmap するだけのダミー処理。実装差し替え時に
        // 実際の `MLXModel.load(...)` を呼ぶ。
        _ = try Data(contentsOf: modelURL.appendingPathComponent("config.json"))
    }
}
