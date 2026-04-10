# Vision Cane AI

> 白杖が届く数メートル先の未来を、音声で予報する

Vision Cane AI は、視覚障がい者の白杖歩行を iPhone 上のローカル
マルチモーダル AI（Gemma 4）で補助する iOS アプリです。点字ブロック上の
障害物や遠方の状況を、LiDAR とカメラの映像から解析し、音声と空間オーディオ
でガイドします。クラウド送信は一切行いません。

## アーキテクチャ概要

```
┌──────────────────────────────────────────────────────────┐
│                       SwiftUI Views                      │
│         GuideView / SettingsView / ContentView           │
└──────────────────────────┬───────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────┐
│                     GuideViewModel                       │
│  モード管理 / イベント発行 / スロットリング / 状態集約    │
└──┬───────┬──────┬──────┬──────┬──────┬──────┬────────────┘
   │       │      │      │      │      │      │
┌──▼──┐ ┌──▼──┐ ┌─▼──┐ ┌─▼──┐ ┌─▼──┐ ┌─▼──┐ ┌─▼──────────┐
│ AR  │ │YOLO │ │BBD │ │LLM │ │TTS │ │STT │ │Thermal/Batt│
│Lidar│ │Objs │ │点字│ │G4  │ │Spch│ │Voice│ │Monitor    │
└─────┘ └─────┘ └────┘ └────┘ └────┘ └────┘ └────────────┘
```

| レイヤ | 役割 | 主な技術 |
| --- | --- | --- |
| View | UI / アクセシビリティ | SwiftUI |
| ViewModel | 状態とイベント駆動 | Combine / async-await |
| AR/LiDAR | 距離・空間情報 | ARKit (`sceneDepth`) |
| 物体検知 | 15fps で障害物候補を捕捉 | YOLOv10 (Core ML) |
| 点字ブロック | 黄色領域と連続性の判定 | Vision / Core Image |
| シーン記述 | 文脈を自然言語化 | MLX-Swift + Gemma 4 (INT4) |
| TTS / Voice | 発話と音声コマンド | AVSpeechSynthesizer / Speech |
| ヒューマンループ | 触覚と空間音 | Core Haptics / PHASE |
| 安全 | サーマル・バッテリ監視 | ProcessInfo / UIDevice |

## 必要環境

- iPhone 15 Pro / 16 Pro 以降（LiDAR スキャナ + 8GB RAM 以上）
- iOS 18+
- Xcode 16+
- [mlx-swift](https://github.com/ml-explore/mlx-swift) / [mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples)
- 4-bit 量子化済み Gemma 4 モデル（`.safetensors` / `.mlpackage`）

## プロジェクト構成

```
VisionCaneAI/
├── App/              アプリエントリポイント
├── Views/            SwiftUI 画面
├── ViewModels/       画面状態とイベント集約
├── Services/         AR・推論・音声などのドメインサービス
├── Models/           値型モデル
├── Utilities/        補助ユーティリティ
└── Resources/        Info.plist などのリソース
```

本リポジトリには Xcode プロジェクトファイル（`.xcodeproj`）は含まれていません。
Xcode で新規 App プロジェクトを作成し、`VisionCaneAI/` 以下のソースツリーを
ドラッグ & ドロップしてください。`Info.plist` のキー（カメラ・マイク・
音声認識の使用目的）は `Resources/Info.plist` にまとまっています。

## 動作モード

- **アクティブ・ガイドモード**: バックグラウンドで連続スキャン。重要な変化
  があったときだけ発話。サーマル状態で推論頻度を自動調整。
- **オンデマンド・サーチ**: タップまたは「前方は？」などの音声コマンドで
  即座に詳細解説を実行。

## プライバシ / 安全設計

- ネットワーク送信を一切行わない（Info.plist で `NSAppTransportSecurity` を
  全ブロックに）。
- LLM が落ちても LiDAR の最短距離警告（触覚フィードバック）は独立に継続。
- 推論結果の確信度が低い場合は「〜かもしれません」など推測表現を徹底。

## 免責

本アプリは音声ガイドによる「補助」であり、安全を保証する歩行補助具では
ありません。実運用に投入する前に、視覚障がい当事者と歩行訓練士による
フィールドテストを必ず行ってください。
