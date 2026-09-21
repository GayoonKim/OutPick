import SwiftUI

private struct AvatarRefreshKey: EnvironmentKey { static var defaultValue = 0 }
extension EnvironmentValues {
    var avatarRefreshID: Int {
        get { self[AvatarRefreshKey.self] }
        set { self[AvatarRefreshKey.self] = newValue }
    }
}

struct AvatarViewportItem: Equatable {
    let id: String
    let path: String?
}

private struct AvatarRowFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

extension View {
    func avatarViewportRow(_ id: String, space: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: AvatarRowFrames.self, value: [id: proxy.frame(in: .named(space))])
        })
    }
    func avatarViewport(items: [AvatarViewportItem], space: String, manager: AvatarImageManaging, refreshID: Int = 0) -> some View {
        modifier(AvatarViewportModifier(items: items, space: space, manager: manager, refreshID: refreshID))
    }
}

private struct AvatarViewportModifier: ViewModifier {
    let items: [AvatarViewportItem]
    let space: String
    let manager: AvatarImageManaging
    let refreshID: Int
    @StateObject private var prefetch: AvatarImagePrefetchController
    @State private var frames: [String: CGRect] = [:]
    @State private var height: CGFloat = 0
    @State private var direction = 1
    @State private var active = false

    init(items: [AvatarViewportItem], space: String, manager: AvatarImageManaging, refreshID: Int) {
        self.items = items; self.space = space; self.manager = manager; self.refreshID = refreshID
        _prefetch = StateObject(wrappedValue: AvatarImagePrefetchController(manager: manager))
    }

    func body(content: Content) -> some View {
        content.coordinateSpace(name: space)
            .environment(\.avatarRefreshID, refreshID)
            .background(GeometryReader { proxy in
                Color.clear.onAppear { height = proxy.size.height; update() }
                    .onChange(of: proxy.size.height) { height = $0; update() }
            })
            .onPreferenceChange(AvatarRowFrames.self) { next in
                if let common = items.first(where: { frames[$0.id] != nil && next[$0.id] != nil }),
                   let old = frames[common.id], let new = next[common.id], abs(old.minY - new.minY) > 1 {
                    direction = new.minY < old.minY ? 1 : -1
                }
                frames = next; update()
            }
            .onChange(of: items) { next in update(items: next) }
            .onChange(of: refreshID) { _ in prefetch.clear(); update() }
            .onAppear { active = true; update() }
            .onDisappear { active = false; prefetch.clear() }
    }

    private func update(items latestItems: [AvatarViewportItem]? = nil) {
        guard active, height > 0 else { return }
        // 경로만 바뀐 경우에도 콜백이 받은 최신 값으로 선로딩 수요를 갱신한다.
        let items = latestItems ?? self.items
        let measured = items.enumerated().compactMap { index, item in frames[item.id].map { (index, $0) } }
        guard let anchor = measured.first else { prefetch.update([]); return }
        // Lazy 행의 미배치 영역은 측정된 행 간격으로만 추정한다.
        let strides = zip(measured, measured.dropFirst()).compactMap { a, b -> CGFloat? in
            let delta = b.0 - a.0
            return delta > 0 ? max(1, (b.1.minY - a.1.minY) / CGFloat(delta)) : nil
        }.sorted()
        let stride = strides.isEmpty ? max(1, anchor.1.height + 14) : strides[strides.count / 2]
        let rows = items.enumerated().compactMap { index, item -> AvatarViewportRow? in
            guard let path = item.path else { return nil }
            let frame = frames[item.id] ?? CGRect(x: 0, y: anchor.1.minY + CGFloat(index - anchor.0) * stride, width: 1, height: stride)
            return AvatarViewportRow(id: item.id, path: path, frame: frame, policy: manager.avatarCachePolicy)
        }
        prefetch.update(AvatarViewportPrefetchPolicy.select(rows: rows, viewport: CGRect(x: 0, y: 0, width: 100_000, height: height), direction: direction))
    }
}
