//
//  PushSupport.swift
//  OutPick
//
//  Created by Codex on 4/10/26.
//

import Foundation

enum AppPresenceState: String, Sendable {
    case foreground
    case background
    case offline
}

struct PushDeviceState: Sendable {
    let deviceID: String
    let email: String
    let fcmToken: String?
    let pushEnabled: Bool
    let appState: AppPresenceState
    let visibleRoomID: String?
    let socketID: String?
}

struct PushNotificationRoute: Sendable, Equatable {
    let roomID: String
    let messageID: String?
    let senderID: String?
    let senderNickname: String?
    let roomName: String?
    let messageType: String?

    static func from(userInfo: [AnyHashable: Any]) -> PushNotificationRoute? {
        let roomID = stringValue(in: userInfo, keys: ["roomID", "roomId"])
        guard let roomID, !roomID.isEmpty else { return nil }

        return PushNotificationRoute(
            roomID: roomID,
            messageID: stringValue(in: userInfo, keys: ["messageID", "messageId"]),
            senderID: stringValue(in: userInfo, keys: ["senderID", "senderId"]),
            senderNickname: stringValue(in: userInfo, keys: ["senderNickname", "senderNickName"]),
            roomName: stringValue(in: userInfo, keys: ["roomName"]),
            messageType: stringValue(in: userInfo, keys: ["messageType", "type"])
        )
    }

    private static func stringValue(in userInfo: [AnyHashable: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = userInfo[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let value = userInfo[key] as? NSString {
                let trimmed = String(value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            if let value = userInfo[key] as? NSNumber {
                return value.stringValue
            }
        }

        return nil
    }
}

@MainActor
final class NotificationRouter {
    static let shared = NotificationRouter()

    private var pendingRoute: PushNotificationRoute?

    private init() {}

    func storePendingRoute(from userInfo: [AnyHashable: Any]) {
        guard let route = PushNotificationRoute.from(userInfo: userInfo) else { return }
        pendingRoute = route
    }

    func setPendingRoute(_ route: PushNotificationRoute?) {
        pendingRoute = route
    }

    func consumePendingRoute() -> PushNotificationRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }
}
