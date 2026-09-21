import UIKit

struct AvatarViewportRow {
    let id: String
    let path: String
    let frame: CGRect
    var policy: AvatarImageCachePolicy = .memoryOnly
}

struct AvatarViewportDemand {
    var request: AvatarImageRequest
    var visibleIDs: Set<String>
}

enum AvatarViewportPrefetchPolicy {
    static func region(viewport: CGRect, direction: Int) -> CGRect {
        CGRect(x: viewport.minX, y: viewport.minY - viewport.height * (direction >= 0 ? 0.5 : 1.5),
               width: viewport.width, height: viewport.height * 3)
    }

    static func select(rows: [AvatarViewportRow], viewport: CGRect, direction: Int, limit: Int = 24) -> [AvatarViewportDemand] {
        guard viewport.height > 0 else { return [] }
        let region = region(viewport: viewport, direction: direction)
        let candidates = rows.filter { !$0.path.isEmpty && $0.frame.intersects(region) }.sorted {
            let lhsVisible = $0.frame.intersects(viewport), rhsVisible = $1.frame.intersects(viewport)
            if lhsVisible != rhsVisible { return lhsVisible }
            func distance(_ row: AvatarViewportRow) -> CGFloat {
                max(0, max(viewport.minY - row.frame.maxY, row.frame.minY - viewport.maxY))
            }
            let a = distance($0), b = distance($1)
            if a != b { return a < b }
            return direction >= 0 ? $0.frame.minY < $1.frame.minY : $0.frame.maxY > $1.frame.maxY
        }
        var result: [AvatarViewportDemand] = []
        var indices: [String: Int] = [:]
        for row in candidates {
            let visible: Set<String> = row.frame.intersects(viewport) ? [row.id] : []
            if let index = indices[row.path] {
                result[index].visibleIDs.formUnion(visible)
                if row.policy == .memoryAndDisk {
                    result[index].request = AvatarImageRequest(path: row.path, representation: .thumbnail, cachePolicy: .memoryAndDisk)
                }
            } else if result.count < limit {
                indices[row.path] = result.count
                result.append(AvatarViewportDemand(request: AvatarImageRequest(path: row.path, representation: .thumbnail, cachePolicy: row.policy), visibleIDs: visible))
            }
        }
        return result
    }
}

/// UIKit layout 좌표를 그대로 사용한다. 메시지/참여자 등 실제 후보 선택은 화면이 전달한다.
@MainActor
final class AvatarCollectionViewport {
    private var previousY: CGFloat?
    private var direction = 1
    private(set) var isActive = false
    let prefetch: AvatarImagePrefetchController
    init(manager: AvatarImageManaging) { prefetch = AvatarImagePrefetchController(manager: manager) }
    func activate() { isActive = true }
    func update(_ collection: UICollectionView, rows: (IndexPath, CGRect) -> [AvatarViewportRow]) {
        guard isActive, collection.window != nil, collection.bounds.height > 0 else { return }
        let viewport = collection.bounds
        if let previousY, abs(viewport.minY - previousY) > 1 { direction = viewport.minY > previousY ? 1 : -1 }
        previousY = viewport.minY
        let attributes = collection.collectionViewLayout.layoutAttributesForElements(in: AvatarViewportPrefetchPolicy.region(viewport: viewport, direction: direction)) ?? []
        let candidates = attributes.filter { $0.representedElementCategory == .cell }.flatMap { rows($0.indexPath, $0.frame) }
        prefetch.update(AvatarViewportPrefetchPolicy.select(rows: candidates, viewport: viewport, direction: direction))
    }
    func clear() { isActive = false; prefetch.clear(); previousY = nil }
}
