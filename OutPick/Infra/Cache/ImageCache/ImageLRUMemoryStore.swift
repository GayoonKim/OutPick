import Foundation
import UIKit

/// 채팅 표시 이미지 전용. 캐시 소유 참조의 비용을 제한하며 화면/플레이어의 메모리까지 제한하지는 않는다.
final class ImageLRUMemoryStore: @unchecked Sendable {
    enum Pressure { case normal, warning, critical }
    private struct Entry {
        let image: UIImage
        let cost: Int
        var access: UInt64
    }
    private let lock = NSLock()
    private let maximumBytes: Int
    private var limit: Int
    private var entries: [String: Entry] = [:]
    private var bytes = 0
    private var sequence: UInt64 = 0
    private var pressureSource: DispatchSourceMemoryPressure?
    private var warningObserver: NSObjectProtocol?

    init(maximumBytes: Int, observesPressure: Bool = true) {
        self.maximumBytes = max(0, maximumBytes)
        self.limit = max(0, maximumBytes)
        guard observesPressure else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, let flags = self.pressureSource?.data else { return }
            self.handlePressure(flags.contains(.critical) ? .critical : flags.contains(.warning) ? .warning : .normal)
        }
        pressureSource = source
        source.resume()
        warningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handlePressure(.warning)
        }
    }

    deinit {
        pressureSource?.cancel()
        if let warningObserver { NotificationCenter.default.removeObserver(warningObserver) }
    }

    func image(forKey key: String) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[key] else { return nil }
        sequence &+= 1
        entry.access = sequence
        entries[key] = entry
        return entry.image
    }

    func set(_ image: UIImage, forKey key: String) {
        let cost: Int
        if let cg = image.cgImage { cost = cg.bytesPerRow * cg.height }
        else { cost = max(1, Int(image.size.width * image.scale)) * max(1, Int(image.size.height * image.scale)) * 4 }
        lock.lock()
        defer { lock.unlock() }
        removeLocked(key, reason: "replaced")
        guard cost <= limit, limit > 0 else {
            ImageCacheMetrics.shared.mark("memory.admission", key: key, outcome: "overBudget", bytes: cost)
            return
        }
        while bytes > limit - cost, let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key {
            removeLocked(oldest, reason: "capacityLRU")
        }
        sequence &+= 1
        entries[key] = Entry(image: image, cost: cost, access: sequence)
        bytes += cost
        reportLocked()
    }

    func remove(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        removeLocked(key, reason: "explicit")
        reportLocked()
    }

    // 먼 구간 준비는 기존 캐시를 밀어내지 않고, 압박 상태에서는 재유입하지 않는다.
    var canPrepareDiskImage: Bool {
        lock.lock()
        defer { lock.unlock() }
        return limit == maximumBytes && limit > 0 && limit - bytes >= 8 * 1024 * 1024
    }

    func setIfRoom(_ image: UIImage, forKey key: String) {
        guard let cg = image.cgImage else { return }
        let cost = cg.bytesPerRow * cg.height
        lock.lock()
        defer { lock.unlock() }
        guard entries[key] == nil, limit == maximumBytes, limit > 0,
              cost <= limit - bytes else { return }
        sequence &+= 1
        entries[key] = Entry(image: image, cost: cost, access: sequence)
        bytes += cost
        reportLocked()
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        bytes = 0
        reportLocked()
    }

    func handlePressure(_ pressure: Pressure) {
        lock.lock()
        defer { lock.unlock() }
        switch pressure {
        case .normal:
            limit = maximumBytes
        case .warning, .critical:
            // 경고 때 기존 보관분을 비우고 재유입도 제한한다. 정상 신호 전까지 큰 예산으로 복귀하지 않는다.
            limit = pressure == .critical || limit == 0 ? 0 : maximumBytes / 4
            for key in Array(entries.keys) { removeLocked(key, reason: "pressure") }
        }
        ImageCacheMetrics.shared.mark("memory.pressure", outcome: pressure == .normal ? "normal" : pressure == .critical ? "critical" : "warning", bytes: limit)
        reportLocked()
    }

    func snapshot() -> (count: Int, bytes: Int, limit: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (entries.count, bytes, limit)
    }

    private func removeLocked(_ key: String, reason: String) {
        guard let old = entries.removeValue(forKey: key) else { return }
        bytes -= old.cost
        ImageCacheMetrics.shared.mark("memory.eviction", key: key, outcome: reason, bytes: old.cost)
    }

    private func reportLocked() {
        ImageCacheMetrics.shared.mark("memory.lruUsage", outcome: "count_\(entries.count)", bytes: bytes)
    }
}
