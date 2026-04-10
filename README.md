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
`project.yml` から [XcodeGen](https://github.com/yonaskolb/XcodeGen) で
生成する運用です（CI でも同じ手順）。ローカルで開く場合は:

```bash
brew install xcodegen
xcodegen generate
open VisionCaneAI.xcodeproj
```

`Info.plist` のキー（カメラ・マイク・音声認識の使用目的）は
`Resources/Info.plist` にまとまっています。

## クラウドから iPhone まで届ける（Mac 不要 CI/CD）

GitHub Actions の `macos-14` ランナーで XcodeGen + Fastlane match + TestFlight
を回し、ローカル Mac を一切持たずに iPhone まで配信できます。

### 1 回だけ必要な準備

1. **Apple Developer Program に加入**し、Team ID を控える。
2. [Apple Developer Portal](https://developer.apple.com/account/resources/identifiers/list)
   で App ID `ai.visioncane.app` を登録（Capability: ARKit を有効化）。
3. [App Store Connect](https://appstoreconnect.apple.com/) でアプリレコード
   を作成し、同じ Bundle ID を指定。
4. App Store Connect → Users and Access → Keys から **API Key (.p8)** を発行。
   `Key ID` / `Issuer ID` / `.p8 の内容` を控える。
5. 証明書と Provisioning Profile を暗号化保管するための **別プライベート
   リポジトリ**（例: `vision-cane-ai-match`）を作る。空で良い。
6. 上記 match リポジトリへの読み書きができる **GitHub Fine-grained PAT**
   を発行する。

### GitHub Secrets に登録する値

| Secret 名 | 内容 |
| --- | --- |
| `APPLE_TEAM_ID` | 10 桁の Team ID |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | API Key の Issuer ID (UUID) |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | `.p8` の中身を **Base64 エンコード**した文字列 |
| `MATCH_PASSWORD` | match が証明書を暗号化する任意のパスフレーズ |
| `MATCH_GIT_URL` | `https://github.com/<you>/vision-cane-ai-match.git` |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `base64("<user>:<pat>")`（match リポジトリ用 PAT） |

### 初回だけ走らせる bootstrap

証明書と Provisioning Profile を match リポジトリに入れるのは 1 度きりの
作業です。Actions タブから `iOS Release (TestFlight)` ワークフローを
`workflow_dispatch` で実行し、`lane` に `bootstrap_signing` を指定して
キックしてください。これで match リポジトリに `certs/` と `profiles/`
が暗号化されて push されます。

### 通常リリース

`main` への push、もしくは `v*` タグの push で `beta` lane が走り、
以下の順でパイプラインが回ります。

1. `xcodegen generate` で `.xcodeproj` を生成
2. `fastlane match appstore --readonly` で証明書を復号してキーチェーンに登録
3. `latest_testflight_build_number + 1` でビルド番号を採番
4. `xcodebuild archive` → `-exportArchive` で `.ipa` を生成
5. `upload_to_testflight` で App Store Connect にアップロード
6. 処理完了後、iPhone の **TestFlight アプリ**で受け取ってインストール

### iPhone 側の受け取り方

- App Store から **TestFlight** アプリをインストール
- App Store Connect → TestFlight → Internal Testing にあなたの Apple ID を追加
- TestFlight アプリを開くと Vision Cane AI が表示されるので **インストール**

### モデル重みはどうするか

Gemma 4 INT4（数 GB）や YOLOv10 の重みは IPA に同梱するとビルドと配信が
重くなるので、**初回起動時にアプリが自分でダウンロードする**前提にして
います。具体的には `Documents/models/gemma-4-e4b-int4/` と
`Documents/models/yolov10.mlpackage` に配置されればロードされ、それまでは
`SceneNarrator` がテンプレート応答にフォールバックします。配信元は
S3 / Cloudflare R2 / GitHub Releases のどれでも構いません。ダウンロード
処理自体はまだ実装していないので、本番投入時に `ModelDownloader` のような
サービスを追加してください。

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
