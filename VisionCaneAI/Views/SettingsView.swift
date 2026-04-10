import SwiftUI

/// 設定画面のプレースホルダ。将来的にモデル切替、発話速度、触覚強度、
/// 点字ブロック検出の閾値などを調整するためのノブを載せる。
struct SettingsView: View {
    @AppStorage("speechRate") private var speechRate: Double = 0.52
    @AppStorage("hapticIntensity") private var hapticIntensity: Double = 1.0
    @AppStorage("useSpatialAudio") private var useSpatialAudio: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("発話") {
                    Slider(value: $speechRate, in: 0.3...0.7, step: 0.02) {
                        Text("発話速度")
                    } minimumValueLabel: {
                        Text("遅")
                    } maximumValueLabel: {
                        Text("速")
                    }
                }
                Section("触覚") {
                    Slider(value: $hapticIntensity, in: 0.0...1.0) {
                        Text("触覚強度")
                    }
                }
                Section("空間オーディオ") {
                    Toggle("空間オーディオで方向を通知", isOn: $useSpatialAudio)
                }
                Section("モデル") {
                    LabeledContent("LLM", value: "Gemma 4 E4B (INT4)")
                    LabeledContent("物体検知", value: "YOLOv10")
                }
                Section("ライセンス / 免責") {
                    Text("本アプリはあくまで音声ガイドによる補助であり、安全を保証する歩行補助具ではありません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
        }
    }
}

#Preview {
    SettingsView()
}
