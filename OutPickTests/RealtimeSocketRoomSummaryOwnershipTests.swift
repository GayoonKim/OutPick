import Foundation
import Testing

@Suite("Realtime Socket Room Summary Ownership")
struct RealtimeSocketRoomSummaryOwnershipTests {
    @Test("Socket ACK 이후 iOS가 room summary를 다시 쓰지 않는다")
    func socketAckDoesNotWriteRoomSummaryFromClient() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot
            .appendingPathComponent("OutPick/Infra/Realtime/RealtimeSocketService.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("updateRoomSummaryAfterSend") == false)
        #expect(source.contains("updateRoomLastMessage(") == false)
        #expect(source.contains("FirebaseChatRoomRepositoryProtocol") == false)
    }
}
