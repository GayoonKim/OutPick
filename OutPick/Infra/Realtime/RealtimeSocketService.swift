//
//  RealtimeSocketService.swift
//  OutPick
//
//  Created by Codex on 6/24/26.
//

import Foundation
import FirebaseAuth
import Network
import SocketIO
import UIKit

struct SocketSessionIdentity: Equatable, Sendable {
    let email: String
    let nickname: String
    let avatarPath: String?
    let clientKey: String
    let socketURL: URL
    let idToken: String

    var connectParams: [String: Any] {
        [
            "clientKey": clientKey,
            "email": email
        ]
    }

    var extraHeaders: [String: String] {
        [
            "Authorization": "Bearer \(idToken)",
            "X-OutPick-Client-Key": clientKey
        ]
    }

    var authPayload: [String: Any] {
        [
            "idToken": idToken,
            "clientKey": clientKey
        ]
    }
}

extension SocketSessionIdentity {
    @MainActor
    static func current(
        currentUserProvider: CurrentUserProviding = LoginManagerCurrentUserProvider()
    ) async throws -> SocketSessionIdentity {
        let idToken = try await currentFirebaseIDToken()
        return SocketSessionIdentity(
            email: currentUserProvider.email
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
            nickname: currentUserProvider.nickname ?? "",
            avatarPath: currentUserProvider.avatarPath,
            clientKey: makeClientKey(),
            socketURL: RealtimeSocketService.makeSocketURL(),
            idToken: idToken
        )
    }

    @MainActor
    private static func currentFirebaseIDToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw SocketIdentityError.missingFirebaseUser
        }

        return try await withCheckedThrowingContinuation { continuation in
            user.getIDToken { token, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let token, !token.isEmpty else {
                    continuation.resume(throwing: SocketIdentityError.missingIDToken)
                    return
                }

                continuation.resume(returning: token)
            }
        }
    }

    @MainActor
    private static func makeClientKey() -> String {
        if let id = UIDevice.current.identifierForVendor?.uuidString {
            return "ios-\(id)"
        }
        return "ios-\(UUID().uuidString)"
    }
}

private enum SocketIdentityError: LocalizedError {
    case missingFirebaseUser
    case missingIDToken

    var errorDescription: String? {
        switch self {
        case .missingFirebaseUser:
            return "Firebase 로그인 사용자를 찾을 수 없습니다."
        case .missingIDToken:
            return "Firebase ID Token을 가져오지 못했습니다."
        }
    }
}

struct ChatRoomSocketSession: Sendable {
    let roomID: String
    let messages: AsyncStream<ChatMessage>
    let close: @Sendable () async -> Void
}

actor ChatRoomSessionActor {
    struct Consumer: Sendable {
        let id: UUID
        let stream: AsyncStream<ChatMessage>
    }

    private var continuations: [UUID: AsyncStream<ChatMessage>.Continuation] = [:]

    func addConsumer() -> Consumer {
        let consumerID = UUID()
        let (stream, continuation) = Self.makeStream()
        continuations[consumerID] = continuation
        return Consumer(id: consumerID, stream: stream)
    }

    @discardableResult
    func removeConsumer(_ consumerID: UUID) -> Bool {
        continuations[consumerID]?.finish()
        continuations.removeValue(forKey: consumerID)
        return continuations.isEmpty
    }

    func publish(_ message: ChatMessage) {
        for continuation in continuations.values {
            continuation.yield(message)
        }
    }

    func finishAll() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    nonisolated private static func makeStream() -> (AsyncStream<ChatMessage>, AsyncStream<ChatMessage>.Continuation) {
        var continuation: AsyncStream<ChatMessage>.Continuation!
        let stream = AsyncStream<ChatMessage> { continuation = $0 }
        return (stream, continuation)
    }
}

actor RealtimeSocketService {
    static let shared = RealtimeSocketService()

    enum SocketError: Error {
        case connectionFailed([Any])
        case invalidRoomID
    }

    private struct ReconnectPolicy {
        var maxAttempts: Int
        var baseDelay: TimeInterval
        var maxDelay: TimeInterval
        var jitter: Double
    }

    private let chatRoomRepository: FirebaseChatRoomRepositoryProtocol
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "outpick.socket.pathmonitor")

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var identity: SocketSessionIdentity?

    private var clientPolicy = ReconnectPolicy(maxAttempts: 5, baseDelay: 0.5, maxDelay: 8.0, jitter: 0.3)
    private var serverPolicy: ReconnectPolicy?
    private var manualAttempt = 0
    private var allowReconnect = true

    private var connectWaiters: [CheckedContinuation<Void, Error>] = []
    private var didBindSocketLifecycle = false

    private var joinedRooms = Set<String>()
    private var pendingRooms: Set<String> = []
    private var pendingCreatedRooms = Set<String>()
    private var joiningRooms = Set<String>()
    private var creatingRooms = Set<String>()

    private var roomSessionActors = [String: ChatRoomSessionActor]()
    private var isChatMessageListenerBound = false
    private var isImageMessageListenerBound = false
    private var isVideoMessageListenerBound = false
    private var roomClosedContinuations = [UUID: AsyncStream<String>.Continuation]()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let productionSocketURL = URL(string: "https://outpick-socket-2w7zhxurhq-du.a.run.app")!

    private init(repositories: FirebaseRepositoryProviding = FirebaseRepositoryProvider.shared) {
        self.chatRoomRepository = repositories.chatRoomRepository
        startPathMonitor()
    }

    nonisolated static func makeSocketURL() -> URL {
        productionSocketURL
    }

    func isConnected() -> Bool {
        socket?.status == .connected
    }

    func connect(identity newIdentity: SocketSessionIdentity) async throws {
        if identity != newIdentity {
            replaceSocket(identity: newIdentity)
        } else if socket == nil {
            replaceSocket(identity: newIdentity)
        }

        guard let socket else {
            throw makeSocketError(code: -1, message: "소켓을 초기화하지 못했습니다.")
        }

        allowReconnect = true

        if socket.status == .connected {
            print("이미 연결된 상태")
            return
        }

        if socket.status == .connecting {
            print("이미 연결 중인 상태")
            try await withCheckedThrowingContinuation { continuation in
                connectWaiters.append(continuation)
            }
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connectWaiters.append(continuation)
            print("소켓 연결 시도")
            socket.connect(withPayload: newIdentity.authPayload)
        }
    }

    func disconnect() {
        allowReconnect = false
        manualAttempt = 0
        tearDownRoomStreams()
        failConnectWaiters(with: SocketError.connectionFailed(["manual disconnect"]))
        socket?.disconnect()
    }

    func suspendForBackground() {
        allowReconnect = false
        manualAttempt = 0
        failConnectWaiters(with: SocketError.connectionFailed(["background disconnect"]))
        guard socket?.status == .connected || socket?.status == .connecting else { return }
        print("백그라운드 진입으로 소켓 연결 해제")
        socket?.disconnect()
    }

    func resetMembership() {
        joinedRooms.removeAll()
        pendingRooms.removeAll()
        pendingCreatedRooms.removeAll()
        joiningRooms.removeAll()
        creatingRooms.removeAll()
    }

    func openRoomSession(for roomID: String) async throws -> ChatRoomSocketSession {
        guard !roomID.isEmpty else { throw SocketError.invalidRoomID }

        bindMessageListenersIfNeeded()

        let sessionActor = roomSessionActor(for: roomID)
        let consumer = await sessionActor.addConsumer()

        if socket?.status != .connected, let identity {
            try await connect(identity: identity)
        }

        joinRoom(roomID)

        return ChatRoomSocketSession(
            roomID: roomID,
            messages: consumer.stream,
            close: { [weak self] in
                await self?.closeRoomSession(roomID: roomID, consumerID: consumer.id)
            }
        )
    }

    func closeRoomSession(roomID: String, consumerID: UUID) async {
        guard let sessionActor = roomSessionActors[roomID] else { return }

        let isEmpty = await sessionActor.removeConsumer(consumerID)
        if isEmpty {
            roomSessionActors.removeValue(forKey: roomID)
        }

        if roomSessionActors.isEmpty {
            detachChatListener()
            detachImageListener()
            detachVideoListener()
        }
    }

    func createRoom(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        pendingCreatedRooms.insert(roomID)
        emitCreateRoomIfNeeded(roomID)
    }

    func joinRoom(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        joinedRooms.insert(roomID)
        emitJoinRoomIfNeeded(roomID)
    }

    func leaveRoom(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        joinedRooms.remove(roomID)
        pendingRooms.remove(roomID)
        pendingCreatedRooms.remove(roomID)

        guard socket?.status == .connected else { return }
        socket?.emit("leave room", roomID)
    }

    func observeRoomClosed(roomID: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            let id = UUID()
            roomClosedContinuations[id] = continuation
            bindRoomClosedListenerIfNeeded()

            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeRoomClosedContinuation(id)
                }
            }
        }
    }

    func sendMessage(_ room: ChatRoom, _ message: ChatMessage, ackTimeout: Double = 5.0) async throws {
        guard let socket, socket.status == .connected else {
            throw makeSocketError(code: -1009, message: "소켓이 연결되어 있지 않습니다.")
        }

        let payload = message.toSocketRepresentation()
        print("📤 전송할 소켓 데이터: \(payload)")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.emitWithAck("chat message", payload).timingOut(after: ackTimeout) { [weak self] ackResponse in
                if ChatMessageEmitAckMapper.isSuccess(ackResponse) {
                    Task {
                        await self?.updateRoomSummaryAfterSend(
                            roomID: room.ID ?? "",
                            sentAt: message.sentAt ?? Date(),
                            preview: message.msg ?? ""
                        )
                    }
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: Self.makeSocketError(
                            code: -1,
                            message: "서버 ACK 실패 또는 timeout: \(ackResponse)"
                        )
                    )
                }
            }
        }
    }

    func preflightMediaUploadAwaitingAck(
        roomID: String,
        messageID: String,
        kind: String,
        attachmentCount: Int,
        expectedPathCount: Int,
        ackTimeout: Double = 5.0
    ) async throws {
        guard let socket, socket.status == .connected else {
            throw makeSocketError(code: -1009, message: "소켓이 연결되어 있지 않습니다.")
        }

        let body: [String: Any] = [
            "roomID": roomID,
            "messageID": messageID,
            "kind": kind,
            "attachmentCount": attachmentCount,
            "expectedPathCount": expectedPathCount,
            "senderID": identity?.email ?? ""
        ]

        try await emitAck(event: "chat:mediaPreflight", body, timeout: ackTimeout, failureMessage: "미디어 업로드 사전 확인 실패 또는 timeout")
    }

    func sendImagesAwaitingAck(
        _ room: ChatRoom,
        _ attachments: [[String: Any]],
        senderAvatarPath: String? = nil,
        clientMessageID: String? = nil,
        ackTimeout: Double = 15.0
    ) async throws {
        guard !attachments.isEmpty else { return }
        guard let socket, socket.status == .connected else {
            throw makeSocketError(code: -1009, message: "소켓이 연결되어 있지 않습니다.")
        }

        let roomID = room.ID ?? ""
        let senderID = identity?.email ?? ""
        let senderNickname = identity?.nickname ?? ""
        let resolvedClientMessageID = clientMessageID?.isEmpty == false ? clientMessageID! : UUID().uuidString
        let now = Date()
        let isoSentAt = Self.isoFormatter.string(from: now)

        var body: [String: Any] = [
            "roomID": roomID,
            "messageID": resolvedClientMessageID,
            "kind": "images",
            "type": "image",
            "msg": "",
            "attachments": attachments,
            "senderID": senderID,
            "senderNickname": senderNickname,
            "sentAt": isoSentAt
        ]
        if let avatar = senderAvatarPath ?? identity?.avatarPath, !avatar.isEmpty {
            body["senderAvatarPath"] = avatar
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.emitWithAck("chat:mediaFinalize", body).timingOut(after: ackTimeout) { [weak self] ackResponse in
                if ChatMessageEmitAckMapper.isSuccess(ackResponse) {
                    Task {
                        await self?.updateRoomSummaryAfterSend(
                            roomID: roomID,
                            sentAt: now,
                            preview: "사진 \(attachments.count)장"
                        )
                    }
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: Self.makeSocketError(
                            code: -1,
                            message: "서버 ACK 실패 또는 timeout: \(ackResponse)"
                        )
                    )
                }
            }
        }
    }

    func sendVideoAwaitingAck(
        roomID: String,
        payload: VideoMetaPayload,
        senderAvatarPath: String? = nil,
        ackTimeout: Double = 5.0
    ) async throws {
        guard let socket, socket.status == .connected else {
            throw makeSocketError(code: -1009, message: "소켓이 연결되어 있지 않습니다.")
        }

        var dict: [String: Any] = [
            "roomID": payload.roomID,
            "messageID": payload.messageID,
            "storagePath": payload.storagePath,
            "thumbnailPath": payload.thumbnailPath,
            "duration": payload.duration,
            "width": payload.width,
            "height": payload.height,
            "sizeBytes": payload.sizeBytes,
            "approxBitrateMbps": payload.approxBitrateMbps,
            "preset": payload.preset,
            "senderID": identity?.email ?? "",
            "senderNickname": identity?.nickname ?? "",
            "kind": "video"
        ]
        if let avatar = senderAvatarPath ?? identity?.avatarPath, !avatar.isEmpty {
            dict["senderAvatarPath"] = avatar
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.emitWithAck("chat:mediaFinalize", dict).timingOut(after: ackTimeout) { [weak self] items in
                if ChatMessageEmitAckMapper.isSuccess(items) {
                    Task {
                        await self?.updateRoomSummaryAfterSend(
                            roomID: roomID,
                            sentAt: Date(),
                            preview: "동영상"
                        )
                    }
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: Self.makeSocketError(
                            code: -1,
                            message: "서버 ACK 실패 또는 timeout: \(items)"
                        )
                    )
                }
            }
        }
    }

    func sendLookbookShare(
        roomID: String,
        sharedContent: LookbookSharedContent,
        messageText: String? = nil,
        ackTimeout: Double = 5.0
    ) async throws -> LookbookChatShareSendResult {
        let trimmedRoomID = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRoomID.isEmpty else { throw LookbookChatShareError.invalidRoomID }
        guard sharedContent.isValid else { throw LookbookChatShareError.invalidSharedContent }
        guard let socket, socket.status == .connected else { throw LookbookChatShareError.socketDisconnected }

        let now = Date()
        let messageID = UUID().uuidString
        let trimmedMessageText = (messageText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let localFallbackPreview = trimmedMessageText.isEmpty
            ? sharedContent.lookbookShareFallbackPreviewText
            : trimmedMessageText
        var payload: [String: Any] = [
            "ID": messageID,
            "messageID": messageID,
            "roomID": trimmedRoomID,
            "messageType": ChatMessageType.lookbookShare.rawValue,
            "msg": trimmedMessageText,
            "sentAt": Self.isoFormatter.string(from: now),
            "senderID": identity?.email ?? "",
            "senderNickname": identity?.nickname ?? "",
            "attachments": [],
            "sharedContent": sharedContent.toDict()
        ]
        if let avatar = identity?.avatarPath,
           !avatar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["senderAvatarPath"] = avatar
        }

        return try await withCheckedThrowingContinuation { continuation in
            socket.emitWithAck("chat:lookbookShare", payload).timingOut(after: ackTimeout) { [weak self] ackResponse in
                do {
                    let result = try LookbookChatShareAckMapper.parse(
                        ackResponse,
                        roomID: trimmedRoomID,
                        fallbackMessageID: messageID
                    )
                    Task {
                        await self?.updateRoomSummaryAfterSend(
                            roomID: trimmedRoomID,
                            sentAt: now,
                            preview: localFallbackPreview
                        )
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func sendFailedVideos(
        roomID: String,
        senderID: String,
        senderNickname: String,
        localURL: URL,
        thumbData: Data?,
        duration: Double,
        width: Int,
        height: Int,
        presetCode: String
    ) {
        let bytes: Int64 = (try? (FileManager.default
            .attributesOfItem(atPath: localURL.path)[.size] as? NSNumber)?.int64Value) ?? 0

        var thumbPath = ""
        if let data = thumbData, !data.isEmpty {
            let thumbURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("vidthumb_\(UUID().uuidString).jpg")
            do {
                try data.write(to: thumbURL, options: .atomic)
                thumbPath = thumbURL.path
            } catch {
                #if DEBUG
                print("[sendFailedVideos] thumbnail write failed:", error)
                #endif
            }
        }

        let clientMessageID = "failed-\(UUID().uuidString)"
        let attachment = Attachment(
            type: .video,
            index: 0,
            pathThumb: thumbPath,
            pathOriginal: localURL.path,
            width: width,
            height: height,
            bytesOriginal: Int(bytes),
            hash: clientMessageID,
            blurhash: nil,
            duration: duration
        )

        let message = ChatMessage(
            ID: clientMessageID,
            seq: 0,
            roomID: roomID,
            senderID: senderID,
            senderNickname: senderNickname,
            msg: "",
            sentAt: Date(),
            attachments: [attachment],
            replyPreview: nil,
            isFailed: true,
            isDeleted: false
        )

        #if DEBUG
        print("[sendFailedVideos] roomID=\(roomID) preset=\(presetCode) duration=\(duration)s size=\(bytes)B")
        #endif

        emitToRoomPipeline(message)
    }

    func leaveOrCloseRoom(roomID: String, ackTimeout: Double = 10.0) async throws -> ChatRoomExitMode {
        guard let socket, socket.status == .connected else {
            throw makeSocketError(code: -1009, message: "소켓이 연결되어 있지 않습니다.")
        }

        let payload: [String: Any] = [
            "roomID": roomID,
            "intent": "leave-or-close"
        ]

        return try await withCheckedThrowingContinuation { continuation in
            socket.emitWithAck("room:leave-or-close", payload).timingOut(after: ackTimeout) { items in
                if let first = items.first as? String,
                   first == SocketAckStatus.noAck.rawValue {
                    continuation.resume(
                        throwing: Self.makeSocketError(
                            code: -1001,
                            message: "서버 응답이 지연되고 있습니다. 잠시 후 다시 시도해 주세요."
                        )
                    )
                    return
                }

                if let first = items.first as? [String: Any] {
                    let ok = (first["ok"] as? Bool) ?? (first["success"] as? Bool) ?? false
                    if ok {
                        continuation.resume(returning: ChatRoomExitMode(serverValue: first["mode"] as? String))
                    } else {
                        let message = first["message"] as? String
                            ?? first["error"] as? String
                            ?? "방 나가기/종료 처리 실패"
                        continuation.resume(throwing: Self.makeSocketError(code: -1, message: message))
                    }
                    return
                }

                if items.isEmpty {
                    continuation.resume(returning: .unknown(nil))
                    return
                }

                continuation.resume(
                    throwing: Self.makeSocketError(
                        code: -2,
                        message: "알 수 없는 ACK 응답 형식: \(items)"
                    )
                )
            }
        }
    }

    private func replaceSocket(identity newIdentity: SocketSessionIdentity) {
        manager?.disconnect()
        manager = nil
        socket = nil
        didBindSocketLifecycle = false
        isChatMessageListenerBound = false
        isImageMessageListenerBound = false
        isVideoMessageListenerBound = false
        identity = newIdentity

        let manager = SocketManager(socketURL: newIdentity.socketURL, config: [
            .log(true),
            .compress,
            .secure(true),
            .forceWebsockets(true),
            .forcePolling(false),
            .connectParams(newIdentity.connectParams),
            .extraHeaders(newIdentity.extraHeaders),
            .reconnects(false)
        ])
        let socket = manager.defaultSocket
        self.manager = manager
        self.socket = socket
        bindSocketLifecycleIfNeeded(socket: socket)
    }

    private func bindSocketLifecycleIfNeeded(socket: SocketIOClient) {
        guard !didBindSocketLifecycle else { return }
        didBindSocketLifecycle = true

        socket.on(clientEvent: .connect) { [weak self] _, _ in
            Task { await self?.handleConnected() }
        }

        socket.on(clientEvent: .error) { [weak self] data, _ in
            Task { await self?.handleSocketError(data) }
        }

        socket.on(clientEvent: .disconnect) { [weak self] data, _ in
            Task { await self?.handleSocketDisconnect(data) }
        }

        socket.off("server:connect:ready")
        socket.on("server:connect:ready") { [weak self] data, _ in
            Task { await self?.handleServerConnectReady(data) }
        }
    }

    private func handleConnected() {
        print("Socket Connected")
        manualAttempt = 0
        socket?.emitWithAck("client:hello", ["attempt": 0]).timingOut(after: 3) { _ in }

        if let nickname = identity?.nickname, !nickname.isEmpty {
            socket?.emit("set username", nickname)
        }

        for roomID in Array(pendingCreatedRooms) {
            emitCreateRoomIfNeeded(roomID)
        }

        for roomID in Array(joinedRooms.union(pendingRooms)) {
            emitJoinRoomIfNeeded(roomID)
        }

        resumeConnectWaiters()
    }

    private func handleSocketError(_ data: [Any]) {
        print("소켓 에러:", data)
        failConnectWaiters(with: SocketError.connectionFailed(data))
        scheduleManualRetryIfNeeded()
    }

    private func handleSocketDisconnect(_ data: [Any]) {
        print("소켓 디스커넥트:", data)
        if !connectWaiters.isEmpty {
            failConnectWaiters(with: SocketError.connectionFailed(data))
        }
        scheduleManualRetryIfNeeded()
    }

    private func handleServerConnectReady(_ data: [Any]) {
        guard let root = data.first as? [String: Any],
              let p = root["policy"] as? [String: Any] else { return }

        func toDouble(_ any: Any?) -> Double? {
            if let d = any as? Double { return d }
            if let i = any as? Int { return Double(i) }
            if let s = any as? String, let v = Double(s) { return v }
            return nil
        }

        let maxAttempts = (p["maxAttempts"] as? Int) ?? clientPolicy.maxAttempts
        let baseDelayMs = toDouble(p["baseDelayMs"]) ?? (clientPolicy.baseDelay * 1000)
        let maxDelayMs = toDouble(p["maxDelayMs"]) ?? (clientPolicy.maxDelay * 1000)
        let jitter = toDouble(p["jitter"]) ?? clientPolicy.jitter

        serverPolicy = ReconnectPolicy(
            maxAttempts: maxAttempts,
            baseDelay: baseDelayMs / 1000.0,
            maxDelay: maxDelayMs / 1000.0,
            jitter: jitter
        )
    }

    private func bindMessageListenersIfNeeded() {
        attachChatListener()
        attachImageListener()
        attachVideoListener()
    }

    private func bindRoomClosedListenerIfNeeded() {
        guard let socket else { return }
        socket.off("room:closed")
        socket.on("room:closed") { [weak self] data, _ in
            guard
                let dict = data.first as? [String: Any],
                let closedRoomID = dict["roomID"] as? String
            else { return }

            Task { await self?.publishRoomClosed(closedRoomID) }
        }
    }

    private func publishRoomClosed(_ roomID: String) {
        for continuation in roomClosedContinuations.values {
            continuation.yield(roomID)
        }
    }

    private func removeRoomClosedContinuation(_ id: UUID) {
        roomClosedContinuations[id]?.finish()
        roomClosedContinuations.removeValue(forKey: id)
        if roomClosedContinuations.isEmpty {
            socket?.off("room:closed")
        }
    }

    private func attachChatListener() {
        guard !isChatMessageListenerBound, let socket else { return }
        isChatMessageListenerBound = true
        let event = "chat message"
        socket.off(event)
        socket.on(event) { [weak self] data, _ in
            guard let dict = data.first as? [String: Any] else { return }
            Task {
                await self?.handleIncomingPayload(dict, event: event)
            }
        }
    }

    private func detachChatListener() {
        guard isChatMessageListenerBound else { return }
        socket?.off("chat message")
        isChatMessageListenerBound = false
    }

    private func attachImageListener() {
        guard !isImageMessageListenerBound, let socket else { return }
        isImageMessageListenerBound = true
        let event = "receiveImages"
        socket.off(event)
        socket.on(event) { [weak self] data, _ in
            guard let dict = data.first as? [String: Any] else { return }
            Task {
                await self?.handleIncomingPayload(dict, event: event)
            }
        }
    }

    private func detachImageListener() {
        guard isImageMessageListenerBound else { return }
        socket?.off("receiveImages")
        isImageMessageListenerBound = false
    }

    private func attachVideoListener() {
        guard !isVideoMessageListenerBound, let socket else { return }
        isVideoMessageListenerBound = true
        let event = "receiveVideo"
        socket.off(event)
        socket.on(event) { [weak self] data, _ in
            guard let dict = data.first as? [String: Any] else { return }
            Task {
                await self?.handleIncomingPayload(dict, event: event)
            }
        }
    }

    private func detachVideoListener() {
        guard isVideoMessageListenerBound else { return }
        socket?.off("receiveVideo")
        isVideoMessageListenerBound = false
    }

    private func handleIncomingPayload(_ payload: [String: Any], event: String) {
        let normalized = normalizeIncomingPayload(payload, event: event)
        guard let message = ChatMessage.from(normalized) else {
            #if DEBUG
            print("[RealtimeSocketService] failed to parse \(event):", normalized)
            #endif
            return
        }
        emitToRoomPipeline(message)
    }

    private func emitToRoomPipeline(_ message: ChatMessage) {
        let roomID = message.roomID
        guard !roomID.isEmpty else { return }
        guard let sessionActor = roomSessionActors[roomID] else { return }

        Task {
            await sessionActor.publish(message)
        }
    }

    private func roomSessionActor(for roomID: String) -> ChatRoomSessionActor {
        if let actor = roomSessionActors[roomID] {
            return actor
        }

        let actor = ChatRoomSessionActor()
        roomSessionActors[roomID] = actor
        return actor
    }

    private func tearDownRoomStreams() {
        let actors = Array(roomSessionActors.values)
        roomSessionActors.removeAll()
        actors.forEach { actor in
            Task {
                await actor.finishAll()
            }
        }
        detachChatListener()
        detachImageListener()
        detachVideoListener()
    }

    private func emitJoinRoomIfNeeded(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        guard let socket, socket.status == .connected else {
            pendingRooms.insert(roomID)
            return
        }
        guard !joiningRooms.contains(roomID) else { return }

        joiningRooms.insert(roomID)
        socket.emitWithAck("join room", roomID).timingOut(after: 5) { [weak self] ackResponse in
            Task {
                await self?.handleJoinAck(roomID: roomID, ackResponse: ackResponse)
            }
        }
    }

    private func handleJoinAck(roomID: String, ackResponse: [Any]) {
        joiningRooms.remove(roomID)
        if ChatMessageEmitAckMapper.isSuccess(ackResponse) {
            pendingRooms.remove(roomID)
        } else {
            pendingRooms.insert(roomID)
            print("join room 실패:", roomID, ackResponse)
        }
    }

    private func emitCreateRoomIfNeeded(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        guard let socket, socket.status == .connected else {
            pendingCreatedRooms.insert(roomID)
            return
        }
        guard pendingCreatedRooms.contains(roomID) else { return }
        guard !creatingRooms.contains(roomID) else { return }

        creatingRooms.insert(roomID)
        socket.emitWithAck("create room", roomID).timingOut(after: 5) { [weak self] ackResponse in
            Task {
                await self?.handleCreateAck(roomID: roomID, ackResponse: ackResponse)
            }
        }
    }

    private func handleCreateAck(roomID: String, ackResponse: [Any]) {
        creatingRooms.remove(roomID)
        if ChatMessageEmitAckMapper.isSuccess(ackResponse) {
            pendingCreatedRooms.remove(roomID)
        } else {
            print("create room 실패:", roomID, ackResponse)
        }
    }

    private func emitAck(
        event: String,
        _ body: [String: Any],
        timeout: Double,
        failureMessage: String
    ) async throws {
        guard let socket else {
            throw makeSocketError(code: -1, message: "소켓을 초기화하지 못했습니다.")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.emitWithAck(event, body).timingOut(after: timeout) { items in
                if ChatMessageEmitAckMapper.isSuccess(items) {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: Self.makeSocketError(
                            code: -1,
                            message: "\(failureMessage): \(items)"
                        )
                    )
                }
            }
        }
    }

    private func updateRoomSummaryAfterSend(roomID: String, sentAt: Date, preview: String) async {
        guard !roomID.isEmpty else { return }
        let trimmedPreview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPreview.isEmpty else { return }
        let senderID = identity?.email ?? ""

        await chatRoomRepository.updateRoomLastMessage(
            roomID: roomID,
            date: sentAt,
            msg: trimmedPreview,
            senderID: senderID
        )
    }

    private func normalizeIncomingPayload(_ payload: [String: Any], event: String) -> [String: Any] {
        var normalized = payload

        if normalized["ID"] == nil {
            normalized["ID"] = normalized["messageID"] ?? normalized["id"] ?? UUID().uuidString
        }

        if normalized["messageType"] == nil {
            if event == "receiveImages" {
                normalized["messageType"] = ChatMessageType.image.rawValue
            } else if event == "receiveVideo" {
                normalized["messageType"] = ChatMessageType.video.rawValue
            } else if let type = normalized["type"] as? String {
                normalized["messageType"] = type
            } else {
                normalized["messageType"] = ChatMessageType.text.rawValue
            }
        }

        if normalized["sentAt"] == nil {
            normalized["sentAt"] = Self.isoFormatter.string(from: Date())
        }

        if event == "receiveImages",
           normalized["attachments"] == nil,
           let pathThumb = normalized["pathThumb"] as? String,
           let pathOriginal = normalized["pathOriginal"] as? String {
            let attachment: [String: Any] = [
                "type": "image",
                "index": 0,
                "pathThumb": pathThumb,
                "pathOriginal": pathOriginal,
                "width": normalized["width"] ?? 0,
                "height": normalized["height"] ?? 0,
                "bytesOriginal": normalized["bytesOriginal"] ?? 0,
                "hash": normalized["hash"] ?? ""
            ]
            normalized["attachments"] = [attachment]
        }

        if event == "receiveVideo",
           normalized["attachments"] == nil {
            let attachment: [String: Any] = [
                "type": "video",
                "index": 0,
                "pathThumb": normalized["thumbnailPath"] ?? normalized["pathThumb"] ?? "",
                "pathOriginal": normalized["storagePath"] ?? normalized["pathOriginal"] ?? "",
                "width": normalized["width"] ?? 0,
                "height": normalized["height"] ?? 0,
                "bytesOriginal": normalized["sizeBytes"] ?? 0,
                "hash": normalized["messageID"] ?? normalized["ID"] ?? "",
                "duration": normalized["duration"] ?? 0
            ]
            normalized["attachments"] = [attachment]
        }

        return normalized
    }

    private func resumeConnectWaiters() {
        guard !connectWaiters.isEmpty else { return }
        let waiters = connectWaiters
        connectWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func failConnectWaiters(with error: Error) {
        guard !connectWaiters.isEmpty else { return }
        let waiters = connectWaiters
        connectWaiters.removeAll()
        waiters.forEach { $0.resume(throwing: error) }
    }

    private static func makeSocketError(code: Int, message: String) -> NSError {
        NSError(
            domain: "SocketIO",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func makeSocketError(code: Int, message: String) -> NSError {
        Self.makeSocketError(code: code, message: message)
    }
}

private extension RealtimeSocketService {
    private var effectivePolicy: ReconnectPolicy {
        serverPolicy ?? clientPolicy
    }

    func backoffDelay(for attempt: Int) -> TimeInterval {
        let p = effectivePolicy
        let base = min(p.maxDelay, p.baseDelay * pow(2, Double(max(0, attempt - 1))))
        let jitter = base * p.jitter * Double.random(in: -1...1)
        return max(0, base + jitter)
    }

    func scheduleManualRetryIfNeeded() {
        guard allowReconnect else { return }
        guard socket?.status != .connected && socket?.status != .connecting else { return }
        guard pathMonitor.currentPath.status == .satisfied else {
            #if DEBUG
            print("[retry] waiting for network...")
            #endif
            return
        }
        guard let identity else { return }

        let limit = effectivePolicy.maxAttempts
        guard manualAttempt < limit else {
            #if DEBUG
            print("[retry] max attempts reached (\(limit)) — stop")
            #endif
            return
        }

        manualAttempt += 1
        let delay = backoffDelay(for: manualAttempt)
        #if DEBUG
        print("[retry] attempt \(manualAttempt)/\(limit) in \(String(format: "%.2f", delay))s")
        #endif

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task {
                guard let self else { return }
                if await self.shouldRetryConnect() {
                    try? await self.connect(identity: identity)
                }
            }
        }
    }

    func shouldRetryConnect() -> Bool {
        allowReconnect && socket?.status != .connected && socket?.status != .connecting
    }

    nonisolated func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task {
                await self?.scheduleManualRetryIfNeeded()
            }
        }
        pathMonitor.start(queue: pathQueue)
    }
}
