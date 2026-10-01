import UIKit

struct ChatMediaViewportItem {
    let id: String
    let path: String
    let frame: CGRect
    let cacheResource: ChatMediaCacheResource?

    init(id: String, path: String, frame: CGRect, cacheResource: ChatMediaCacheResource? = nil) {
        self.id = id
        self.path = path
        self.frame = frame
        self.cacheResource = cacheResource
    }
}

struct ChatMediaViewportPolicy {
    var forwardScreens: CGFloat = 1.5
    var backwardScreens: CGFloat = 0.5
    var prefetchLimit = 24

    func initialDiskPreparationPaths(groups: [[String]], anchor: Int) -> [String] {
        let order = groups.indices.sorted {
            let a = abs($0 - anchor), b = abs($1 - anchor)
            return a == b ? $0 > $1 : a < b
        }
        var seen = Set<String>()
        return order.flatMap { groups[$0] }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func diskPreparationPaths(items: [ChatMediaViewportItem], viewport: CGRect) -> [String] {
        let ordered = items.filter { !$0.path.isEmpty && !$0.frame.isEmpty && !$0.frame.isNull }.sorted {
            let a = max(0, max(viewport.minY - $0.frame.maxY, $0.frame.minY - viewport.maxY))
            let b = max(0, max(viewport.minY - $1.frame.maxY, $1.frame.minY - viewport.maxY))
            return a == b ? $0.id < $1.id : a < b
        }
        var seen = Set<String>()
        return ordered.compactMap { seen.insert($0.path).inserted ? $0.path : nil }
    }

    func region(viewport: CGRect, movingDown: Bool, velocityY: CGFloat = 0) -> CGRect {
        let forward = max(forwardScreens, min(4, abs(velocityY) * 0.45 / max(1, viewport.height)))
        let before = movingDown ? backwardScreens : forward
        let after = movingDown ? forward : backwardScreens
        return CGRect(x: viewport.minX, y: viewport.minY - viewport.height * before,
                      width: viewport.width, height: viewport.height * (1 + before + after))
    }

    func predictedRegion(viewport: CGRect, velocityY: CGFloat, targetY: CGFloat?) -> CGRect? {
        guard abs(velocityY) > viewport.height * 2 else { return nil }
        let offset = max(-viewport.height * 3, min(viewport.height * 3, velocityY * 0.35))
        return CGRect(x: viewport.minX, y: targetY ?? viewport.minY + offset, width: viewport.width, height: viewport.height)
    }

    func demands(items: [ChatMediaViewportItem], viewport: CGRect, movingDown: Bool, velocityY: CGFloat = 0, targetY: CGFloat? = nil) -> [String: ImageRequestPriority] {
        guard viewport.width > 0, viewport.height > 0 else { return [:] }
        let candidates = items.filter { !$0.path.isEmpty && !$0.frame.isEmpty && !$0.frame.isNull }
        let visible = candidates.filter { $0.frame.intersects(viewport) }
        var result = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, ImageRequestPriority.visible) })
        let visiblePaths = Set(visible.map(\.path))
        var prefetchPaths = Set<String>()
        let surrounding = region(viewport: viewport, movingDown: movingDown, velocityY: velocityY)
        let ordered = candidates.filter { result[$0.id] == nil && $0.frame.intersects(surrounding) }.sorted {
            func distance(_ item: ChatMediaViewportItem) -> CGFloat {
                max(0, max(viewport.minY - item.frame.maxY, item.frame.minY - viewport.maxY))
            }
            let lhs = distance($0), rhs = distance($1)
            if lhs != rhs { return lhs < rhs }
            if $0.frame.midY != $1.frame.midY { return movingDown ? $0.frame.midY > $1.frame.midY : $0.frame.midY < $1.frame.midY }
            return $0.id < $1.id
        }
        let predicted = predictedRegion(viewport: viewport, velocityY: velocityY, targetY: targetY)
        let destination = candidates.filter { item in
            result[item.id] == nil && predicted.map { item.frame.intersects($0) } == true
        }.sorted { lhs, rhs in
            let center = predicted?.midY ?? viewport.midY
            let a = abs(lhs.frame.midY - center), b = abs(rhs.frame.midY - center)
            return a == b ? lhs.id < rhs.id : a < b
        }
        // 가까운 다음 사진과 먼 도착 화면을 번갈아 선택해 어느 한쪽이 상한을 독점하지 않게 한다.
        var selected: [ChatMediaViewportItem] = []
        for index in 0..<max(ordered.count, destination.count) {
            if index < ordered.count { selected.append(ordered[index]) }
            if index < destination.count { selected.append(destination[index]) }
        }
        for item in selected {
            if !visiblePaths.contains(item.path), !prefetchPaths.contains(item.path) {
                guard prefetchPaths.count < prefetchLimit else { continue }
                prefetchPaths.insert(item.path)
            }
            result[item.id] = .prefetch
        }
        return result
    }
}
