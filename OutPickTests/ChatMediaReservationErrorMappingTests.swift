import Foundation
import Testing
@testable import OutPick

struct ChatMediaReservationErrorMappingTests {
    @Test func activeUploadLimitSocketCodeMapsToTypedCapacityError() {
        let socketError = NSError(
            domain: "SocketIO",
            code: 400,
            userInfo: ["serverErrorCode": "active_upload_limit"]
        )

        let mapped = SocketChatMediaMessageSendingRepository.mapReservationError(socketError)

        guard case ChatMediaUploadReservationError.activeUploadLimit = mapped else {
            Issue.record("active_upload_limit가 타입 오류로 변환되지 않았습니다.")
            return
        }
    }

    @Test func unrelatedSocketErrorIsPreserved() {
        let socketError = NSError(domain: "SocketIO", code: 500)

        let mapped = SocketChatMediaMessageSendingRepository.mapReservationError(socketError) as NSError

        #expect(mapped.domain == "SocketIO")
        #expect(mapped.code == 500)
    }
}
