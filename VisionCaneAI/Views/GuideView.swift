import SwiftUI

/// ガイド中のメイン画面。高コントラストで情報密度を抑え、VoiceOver と
/// Dynamic Type に最適化する。画面を見ない運用を前提とするが、晴眼者の
/// 介助者やデバッグ用途のために現在のモード・プロファイル・最新ガイドを
/// 表示する。
struct GuideView: View {
    @EnvironmentObject private var viewModel: GuideViewModel

    var body: some View {
        VStack(spacing: 24) {
            header
            Spacer()
            descriptionCard
            Spacer()
            modePicker
            onDemandButton
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Vision Cane AI")
                .font(.system(.title, design: .rounded, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 12) {
                Label(viewModel.isLidarAvailable ? "LiDAR 有効" : "LiDAR なし",
                      systemImage: viewModel.isLidarAvailable ? "sensor" : "sensor.tag.radiowaves.forward.fill")
                Label(viewModel.profileLabel, systemImage: "thermometer.medium")
                Label(String(format: "%.0f%%", viewModel.batteryLevel * 100),
                      systemImage: "battery.75")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var descriptionCard: some View {
        Text(viewModel.lastDescription)
            .font(.system(.title2, design: .rounded, weight: .semibold))
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .accessibilityLabel("最新の状況")
            .accessibilityValue(viewModel.lastDescription)
    }

    private var modePicker: some View {
        Picker("モード", selection: Binding(
            get: { viewModel.mode },
            set: { viewModel.setMode($0) }
        )) {
            ForEach(AppMode.allCases) { mode in
                Text(mode.localizedTitle).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint(viewModel.mode.accessibilityHint)
    }

    private var onDemandButton: some View {
        Button {
            viewModel.requestOnDemandDescription()
        } label: {
            Label("前方を解析", systemImage: "sparkles.tv")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.yellow)
        .foregroundStyle(.black)
        .accessibilityHint("ダブルタップで周囲の状況を一度だけ解析します。")
    }
}

#Preview {
    GuideView()
        .environmentObject(GuideViewModel())
}
