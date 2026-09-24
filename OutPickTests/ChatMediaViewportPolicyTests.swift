import XCTest
@testable import OutPick

final class ChatMediaViewportPolicyTests: XCTestCase {
    func testInitialPreparationStartsAtEntryAnchorWithoutLayout() {
        let policy = ChatMediaViewportPolicy()
        let groups = [["old"], ["near"], ["unread", ""], ["latest", "near"]]
        XCTAssertEqual(policy.initialDiskPreparationPaths(groups: groups, anchor: 3), ["latest", "near", "unread", "old"])
        XCTAssertEqual(policy.initialDiskPreparationPaths(groups: groups, anchor: 2), ["unread", "latest", "near", "old"])
        XCTAssertEqual(policy.initialDiskPreparationPaths(groups: [], anchor: 0), [])
    }

    func testDiskPreparationIncludesDistantItemsInDistanceOrderAndDeduplicates() {
        let viewport = CGRect(x: 0, y: 500, width: 100, height: 100)
        let items = [
            ChatMediaViewportItem(id: "far", path: "far", frame: CGRect(x: 0, y: 100000, width: 10, height: 10)),
            ChatMediaViewportItem(id: "near", path: "near", frame: CGRect(x: 0, y: 480, width: 10, height: 10)),
            ChatMediaViewportItem(id: "visible", path: "current", frame: viewport),
            ChatMediaViewportItem(id: "duplicate", path: "current", frame: viewport)
        ]
        XCTAssertEqual(ChatMediaViewportPolicy().diskPreparationPaths(items: items, viewport: viewport), ["current", "near", "far"])
    }

    func testFastScrollIncludesBoundedForwardAndDestinationWithoutWholeCorridor() {
        let viewport = CGRect(x: 0, y: 200, width: 100, height: 100)
        let near = (0..<30).map { ChatMediaViewportItem(id: "near\($0)", path: "near\($0)", frame: CGRect(x: 0, y: 310, width: 10, height: 10)) }
        let destination = (0..<30).map { ChatMediaViewportItem(id: "dest\($0)", path: "dest\($0)", frame: CGRect(x: 0, y: 10010, width: 10, height: 10)) }
        let middle = ChatMediaViewportItem(id: "middle", path: "middle", frame: CGRect(x: 0, y: 5000, width: 10, height: 10))
        let visible = ChatMediaViewportItem(id: "visible", path: "visible", frame: viewport)
        let policy = ChatMediaViewportPolicy()
        let demands = policy.demands(items: near + destination + [middle, visible], viewport: viewport,
                                     movingDown: true, velocityY: 2000, targetY: 10000)
        XCTAssertEqual(demands["visible"], .visible)
        XCTAssertNil(demands["middle"])
        XCTAssertEqual(demands.values.filter { $0 == .prefetch }.count, 24)
        XCTAssertEqual(demands.keys.filter { $0.hasPrefix("near") }.count, 12)
        XCTAssertEqual(demands.keys.filter { $0.hasPrefix("dest") }.count, 12)
        XCTAssertEqual(policy.region(viewport: viewport, movingDown: true, velocityY: 100000).height, 550)
        XCTAssertNil(policy.predictedRegion(viewport: viewport, velocityY: 100, targetY: 10000))
    }

    func testProjectedRegionMovesInScrollDirectionAndIsBounded() {
        let viewport = CGRect(x: 0, y: 500, width: 100, height: 100)
        let policy = ChatMediaViewportPolicy()
        XCTAssertEqual(policy.predictedRegion(viewport: viewport, velocityY: -100000, targetY: nil)?.minY, 200)
        XCTAssertEqual(policy.predictedRegion(viewport: viewport, velocityY: 100000, targetY: nil)?.minY, 800)
    }

    func testVisibleItemsDoNotConsumePrefetchLimitAndPathsAreDeduplicated() {
        let viewport = CGRect(x: 0, y: 100, width: 100, height: 100)
        let visible = (0..<30).map { ChatMediaViewportItem(id: "v\($0)", path: "v\($0)", frame: viewport) }
        let surrounding = (0..<40).map { ChatMediaViewportItem(id: "p\($0)", path: "p\($0 / 2)", frame: CGRect(x: 0, y: 210, width: 10, height: 10)) }
        let extra = (0..<20).map { ChatMediaViewportItem(id: "e\($0)", path: "e\($0)", frame: CGRect(x: 0, y: 240, width: 10, height: 10)) }
        let items = visible + surrounding + extra
        let demands = ChatMediaViewportPolicy().demands(items: items, viewport: viewport, movingDown: true)
        XCTAssertEqual(demands.values.filter { $0 == .visible }.count, 30)
        XCTAssertEqual(Set(items.filter { demands[$0.id] == .prefetch }.map(\.path)).count, 24)
    }

    func testDirectionChangesSurroundingRegionAndEmptyPathsNeverLoad() {
        let viewport = CGRect(x: 0, y: 200, width: 100, height: 100)
        let items = [ChatMediaViewportItem(id: "up", path: "up", frame: CGRect(x: 0, y: 70, width: 10, height: 10)),
                     ChatMediaViewportItem(id: "down", path: "down", frame: CGRect(x: 0, y: 400, width: 10, height: 10)),
                     ChatMediaViewportItem(id: "empty", path: "", frame: viewport)]
        let policy = ChatMediaViewportPolicy()
        XCTAssertEqual(Set(policy.demands(items: items, viewport: viewport, movingDown: true).keys), ["down"])
        XCTAssertEqual(Set(policy.demands(items: items, viewport: viewport, movingDown: false).keys), ["up"])
    }
}
