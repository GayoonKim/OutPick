import Foundation

enum ChatRoomRoleMutationErrorMessage {
    static func message(for error: Error) -> String {
        guard let code = serverErrorCode(from: error) else {
            return "잠시 후 다시 시도해 주세요."
        }
        switch code {
        case "ROOM_CLOSED":
            return "이미 종료된 채팅방이에요."
        case "ROOM_ROLE_STATE_INVALID":
            return "채팅방 권한 정보를 다시 확인한 뒤 시도해 주세요."
        case "NOT_ROOM_OWNER", "NOT_ROOM_MODERATOR":
            return "현재 권한으로는 이 작업을 할 수 없어요."
        case "OWNER_TRANSFER_REQUIRED":
            return "관리자에게 방장 권한을 넘기거나 방을 종료해 주세요."
        case "TARGET_NOT_MEMBER":
            return "이미 채팅방을 나간 사용자예요."
        case "TARGET_IS_OWNER":
            return "방장에게는 이 작업을 할 수 없어요."
        case "TARGET_IS_MODERATOR":
            return "다른 관리자에게는 이 작업을 할 수 없어요."
        case "TARGET_ALREADY_MODERATOR":
            return "이미 관리자인 사용자예요."
        case "TARGET_NOT_MODERATOR":
            return "이미 관리자 권한이 해제됐어요."
        case "MODERATOR_LIMIT_REACHED":
            return "관리자는 최대 3명까지 지정할 수 있어요."
        case "TARGET_NOT_ELIGIBLE":
            return "현재 운영 권한을 맡을 수 없는 사용자예요."
        case "REQUEST_ID_CONFLICT":
            return "요청 상태를 다시 확인한 뒤 시도해 주세요."
        case "FEATURE_NOT_AVAILABLE":
            return "채팅방 관리자 기능을 준비 중이에요."
        default:
            return "잠시 후 다시 시도해 주세요."
        }
    }

    static func serverErrorCode(from error: Error) -> String? {
        let details = (error as NSError).userInfo["details"]
        if let dictionary = details as? [String: Any] {
            return dictionary["errorCode"] as? String
        }
        if let dictionary = details as? NSDictionary {
            return dictionary["errorCode"] as? String
        }
        return nil
    }
}
