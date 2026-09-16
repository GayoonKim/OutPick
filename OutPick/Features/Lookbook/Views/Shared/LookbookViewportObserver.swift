import SwiftUI

private struct LookbookItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

extension View {
    func lookbookItemFrame(_ id: String, in coordinateSpace: String) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: LookbookItemFramePreferenceKey.self,
                    value: [id: geometry.frame(in: .named(coordinateSpace))]
                )
            }
        }
    }

    func onLookbookItemFrames(_ action: @escaping ([String: CGRect]) -> Void) -> some View {
        onPreferenceChange(LookbookItemFramePreferenceKey.self, perform: action)
    }
}

/// 미배치 셀은 이미 측정된 행을 기준으로 추정하고, 화면 크기가 바뀌면 다시 계산한다.
struct LookbookViewportTracker {
    private(set) var direction: Int = 1
    private var previousFrames: [String: CGRect] = [:]
    private var previousFirstIndex: Int?

    mutating func range(
        ids: [String], frames: [String: CGRect], viewportHeight: CGFloat,
        columns: Int, estimatedRowStride: CGFloat, limit: Int = 24
    ) -> [Int] {
        guard !ids.isEmpty, viewportHeight > 0 else { return [] }
        let indexed = ids.enumerated().compactMap { index, id -> (Int, CGRect)? in
            frames[id].map { (index, $0) }
        }
        if let common = indexed.first(where: { previousFrames[ids[$0.0]] != nil }),
           let previous = previousFrames[ids[common.0]] {
            let delta = common.1.minY - previous.minY
            if abs(delta) > 1 { direction = delta < 0 ? 1 : -1 }
        } else if let first = indexed.first?.0, let previousFirstIndex,
                  first != previousFirstIndex {
            direction = first > previousFirstIndex ? 1 : -1
        }
        previousFrames = frames
        if let first = indexed.first?.0 { previousFirstIndex = first }

        let columnCount = max(columns, 1)
        let stride = measuredStride(indexed, columns: columnCount) ?? max(estimatedRowStride, 1)
        let anchor = indexed.first
        let anchorRow = (anchor?.0 ?? 0) / columnCount
        let anchorY = anchor?.1.minY ?? 0
        let before = direction > 0 ? 0.5 : 1.5
        let after = direction > 0 ? 1.5 : 0.5
        let minY = -CGFloat(before) * viewportHeight
        let maxY = CGFloat(1 + after) * viewportHeight
        var candidates: [(index: Int, distance: CGFloat)] = []
        for index in ids.indices {
            let row = index / columnCount
            let y = frames[ids[index]]?.minY ?? anchorY + CGFloat(row - anchorRow) * stride
            let height = frames[ids[index]]?.height ?? stride
            guard y + height >= minY, y <= maxY else { continue }
            let distance = y < 0 ? -y : max(0, y - viewportHeight)
            candidates.append((index, distance))
        }
        if candidates.count > limit {
            candidates.sort { lhs, rhs in
                lhs.distance == rhs.distance ? lhs.index < rhs.index : lhs.distance < rhs.distance
            }
            candidates = Array(candidates.prefix(limit))
        }
        return candidates.map(\.index).sorted(by: direction > 0 ? (<) : (>))
    }

    private func measuredStride(_ frames: [(Int, CGRect)], columns: Int) -> CGFloat? {
        guard frames.count >= 2 else { return nil }
        let first = frames[0]
        for next in frames.dropFirst() {
            let rows = next.0 / columns - first.0 / columns
            if rows > 0 {
                let measured = (next.1.minY - first.1.minY) / CGFloat(rows)
                if measured > 1 { return measured }
            }
        }
        return nil
    }
}
