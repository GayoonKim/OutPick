import Foundation

/// 동시에 도착하는 파일별 진행률을 묶음 단위로 합산하고 역행을 방지한다.
final class ChatMediaBatchProgress: @unchecked Sendable {
    private let lock = NSLock()
    private let completed: Int
    private let total: Int
    private let weights: [Int]
    private var fractions: [Int: Double] = [:]
    private let onProgress: (Double) -> Void

    init(completed: Int, total: Int, weights: [Int] = [], onProgress: @escaping (Double) -> Void) {
        self.completed = completed
        self.total = max(1, total)
        self.weights = weights
        self.onProgress = onProgress
    }

    func update(index: Int, fraction: Double) {
        guard fraction.isFinite else { return }
        lock.lock()
        defer { lock.unlock() }
        fractions[index] = max(fractions[index] ?? 0, min(1, max(0, fraction)))
        let sent = fractions.reduce(0.0) { sum, item in
            sum + item.value * Double(weights.indices.contains(item.key) ? weights[item.key] : 1)
        }
        onProgress(min(1, (Double(completed) + sent) / Double(total)))
    }
}
