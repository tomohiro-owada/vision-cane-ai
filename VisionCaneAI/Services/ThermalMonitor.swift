import Combine
import Foundation
import UIKit

/// 端末のサーマル状態とバッテリ残量を監視し、推論のティックレートを
/// 動的に落とすための「速度プロファイル」を配信する。
///
/// - `.nominal`:  YOLO 15fps / LLM 1.5fps
/// - `.fair`:     YOLO 12fps / LLM 1.0fps
/// - `.serious`:  YOLO  8fps / LLM 0.5fps
/// - `.critical`: YOLO  4fps / LLM 停止（テンプレート応答のみ）
final class ThermalMonitor: ObservableObject {

    struct Profile: Equatable {
        let yoloHz: Double
        let llmHz: Double
    }

    @Published private(set) var profile: Profile = .nominal
    @Published private(set) var batteryLevel: Float = 1.0

    private var cancellables = Set<AnyCancellable>()

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshProfile()

        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { [weak self] _ in self?.refreshProfile() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .sink { [weak self] _ in
                self?.batteryLevel = UIDevice.current.batteryLevel
                self?.refreshProfile()
            }
            .store(in: &cancellables)
    }

    private func refreshProfile() {
        let thermal = ProcessInfo.processInfo.thermalState
        let battery = UIDevice.current.batteryLevel
        self.batteryLevel = battery

        // バッテリ 10% 未満は強制的に serious 以上に落とす。
        let effective: ProcessInfo.ThermalState
        if battery >= 0 && battery < 0.1 {
            effective = max(thermal, .serious)
        } else {
            effective = thermal
        }

        switch effective {
        case .nominal:  profile = .nominal
        case .fair:     profile = .fair
        case .serious:  profile = .serious
        case .critical: profile = .critical
        @unknown default: profile = .fair
        }
    }
}

extension ThermalMonitor.Profile {
    static let nominal  = ThermalMonitor.Profile(yoloHz: 15.0, llmHz: 1.5)
    static let fair     = ThermalMonitor.Profile(yoloHz: 12.0, llmHz: 1.0)
    static let serious  = ThermalMonitor.Profile(yoloHz: 8.0,  llmHz: 0.5)
    static let critical = ThermalMonitor.Profile(yoloHz: 4.0,  llmHz: 0.0)
}

private func max(_ a: ProcessInfo.ThermalState, _ b: ProcessInfo.ThermalState) -> ProcessInfo.ThermalState {
    func rank(_ s: ProcessInfo.ThermalState) -> Int {
        switch s {
        case .nominal:  return 0
        case .fair:     return 1
        case .serious:  return 2
        case .critical: return 3
        @unknown default: return 1
        }
    }
    return rank(a) >= rank(b) ? a : b
}
