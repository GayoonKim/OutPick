import XCTest
import UIKit
import SwiftUI
@testable import OutPick

@MainActor
final class AvatarNestedViewportTests: XCTestCase {
    func testSwiftUIViewportPrefetchesChangedPathWithoutScrolling() async throws {
        let spy = AvatarRouteImageSpy()
        let model = AvatarViewportTestModel()
        let controller = UIHostingController(rootView: AvatarViewportTestView(model: model, manager: spy))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(spy.requests.isEmpty)
        for path in ["first-photo", "changed-photo"] {
            model.items = [AvatarViewportItem(id: "same-row", path: path)]
            for _ in 0..<200 where !spy.requests.contains(where: { $0.path == path }) {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTAssertTrue(spy.requests.contains(where: { $0.path == path }), "스크롤 없이 최신 경로를 선로딩해야 합니다: \(path)")
        }
    }

    func testNestedParticipantsRequestOnlyOuterViewportAndPrefetchRegion() async throws {
        let spy = AvatarRouteImageSpy()
        let manager = spy.scoped { .memoryAndDisk }
        let dataSource = NestedAvatarDataSource(manager: manager)
        let controller = UIViewController()
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 300), collectionViewLayout: NestedAvatarLayout())
        collection.register(ParticipantsSectionParticipantCell.self, forCellWithReuseIdentifier: ParticipantsSectionParticipantCell.reuseIdentifier)
        collection.dataSource = dataSource
        controller.view.addSubview(collection)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let viewport = AvatarCollectionViewport(manager: manager)
        defer { viewport.clear(); window.isHidden = true; window.rootViewController = nil }
        collection.reloadData()
        collection.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        let cell = try XCTUnwrap(dataSource.cell)
        cell.layoutIfNeeded()
        cell.verticalCollectionView.layoutIfNeeded()
        XCTAssertEqual(cell.verticalCollectionView.numberOfItems(inSection: 0), 50)
        XCTAssertTrue(spy.requests.isEmpty, "중첩 셀 생성만으로 화면 밖 50명 사진을 요청하면 안 됩니다.")
        viewport.activate()
        var previousOffset: CGFloat = 0
        for offset: CGFloat in [0, 2400, 1200] {
            let previousPaths = Set(spy.requests.map(\.path))
            collection.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            collection.layoutIfNeeded()
            viewport.update(collection) { _, _ in cell.avatarRows(in: collection) }
            try await Task.sleep(nanoseconds: 400_000_000)
            let rows = cell.avatarRows(in: collection)
            XCTAssertEqual(rows.count, 50)
            let visible = Set(rows.filter { $0.frame.intersects(collection.bounds) }.map(\.path))
            let ahead: CGFloat = offset >= previousOffset ? 1.5 : 0.5
            let behind: CGFloat = offset >= previousOffset ? 0.5 : 1.5
            let allowedRect = CGRect(x: 0, y: offset - 300 * behind, width: 300, height: 300 * (1 + ahead + behind))
            let allowed = Set(rows.filter { $0.frame.intersects(allowedRect) }.map(\.path))
            let requested = Set(spy.requests.map(\.path))
            let newRequests = requested.subtracting(previousPaths)
            XCTAssertFalse(visible.isEmpty)
            XCTAssertTrue(visible.isSubset(of: requested))
            XCTAssertTrue(newRequests.isSubset(of: allowed), "바깥 스크롤 영역에서 먼 참여자의 요청이 발생했습니다.")
            XCTAssertLessThanOrEqual(viewport.prefetch.activePaths.count, 24)
            XCTAssertLessThan(requested.count, 50)
            print("[AvatarNestedQA] offset=\(Int(offset)) visible=\(visible.count) newRequests=\(newRequests.count) active=\(viewport.prefetch.activePaths.count) total=\(requested.count)")
            previousOffset = offset
        }
        viewport.clear()
        XCTAssertTrue(viewport.prefetch.activePaths.isEmpty)
    }
}

@MainActor
private final class AvatarViewportTestModel: ObservableObject {
    @Published var items = [AvatarViewportItem(id: "same-row", path: nil)]
}

private struct AvatarViewportTestView: View {
    @ObservedObject var model: AvatarViewportTestModel
    let manager: AvatarImageManaging
    var body: some View {
        ScrollView {
            VStack {
                Text("고정 행").frame(height: 60)
                    .avatarViewportRow("same-row", space: "avatar-review")
            }
        }
        .avatarViewport(items: model.items, space: "avatar-review", manager: manager)
        .frame(height: 300)
    }
}

@MainActor
private final class NestedAvatarDataSource: NSObject, UICollectionViewDataSource {
    let manager: AvatarImageManaging
    var cell: ParticipantsSectionParticipantCell?
    init(manager: AvatarImageManaging) { self.manager = manager }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 1 }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ParticipantsSectionParticipantCell.reuseIdentifier, for: indexPath) as! ParticipantsSectionParticipantCell
        let participants = (0..<50).map { index in
            ChatRoomParticipant(user: LocalChatUser(userID: "qa-\(index)", nickname: "QA \(index)", profileImagePath: "photo-\(index)"), role: .member)
        }
        cell.configureCell(participants, currentUserID: "self", avatarImageManager: manager)
        self.cell = cell
        return cell
    }
}

private final class NestedAvatarLayout: UICollectionViewLayout {
    override var collectionViewContentSize: CGSize { CGSize(width: 300, height: 3030) }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = CGRect(x: 0, y: 0, width: 300, height: 3030)
        return attributes
    }
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let attributes = layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!
        return attributes.frame.intersects(rect) ? [attributes] : []
    }
}
