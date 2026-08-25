import Foundation

/// Split timing points make UI, selection and inference regressions distinguishable.
@MainActor
final class LatencyMetrics {
    private let startedAt: UInt64

    init(startedAt: UInt64) {
        self.startedAt = startedAt
    }

    func mark(_ name: String) {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        print("[QuickTranslate] \(name): \(String(format: "%.1f", elapsed)) ms")
    }
}
