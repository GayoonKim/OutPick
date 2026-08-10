import Foundation
import Testing

@Suite("Chat Room Active Query Contract")
struct ChatRoomActiveQueryContractTests {
    @Test("모든 최상위 Rooms 목록 query는 active room helper를 사용한다")
    func topLevelRoomQueriesUseActiveRoomHelper() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appendingPathComponent(
            "OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseChatRoomRepository.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.components(separatedBy: "activeRoomsQuery()").count - 1 == 5)
        #expect(source.contains(".whereField(\"isClosed\", isEqualTo: false)"))
        #expect(source.contains(".whereField(\"lifecycleStatus\", isEqualTo: \"active\")"))
    }
}
