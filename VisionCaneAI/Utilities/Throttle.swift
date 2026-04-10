import Foundation

/// 連続発話やフレーム処理を間引くためのシンプルなスロットル。
///
/// `shouldFire(at:)` は最後に発火してから `interval` 秒以上経過していれば
/// `true` を返し、内部状態を更新する。スレッドセーフではないので呼び出し側で
/// actor / main thread などに閉じ込めて使うこと。
struct Throttle {
    let interval: TimeInterval
    private var lastFired: Date?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    mutating func shouldFire(at now: Date = .now) -> Bool {
        guard let last = lastFired else {
            lastFired = now
            return true
        }
        guard now.timeIntervalSince(last) >= interval else { return false }
        lastFired = now
        return true
    }

    mutating func reset() {
        lastFired = nil
    }
}
