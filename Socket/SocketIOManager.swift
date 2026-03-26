//
//  SocketIOManager.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.

import UIKit
import SocketIO
import Combine
import CryptoKit
import Network

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

class SocketIOManager {
    static let shared = SocketIOManager()
    private let userProfileRepository: UserProfileRepositoryProtocol
    private let chatRoomRepository: FirebaseChatRoomRepositoryProtocol

    // ---- Reconnect Policy (client defaults; server can override via `server:connect:ready`) ----
    private struct ReconnectPolicy {
        var maxAttempts: Int
        var baseDelay: TimeInterval
        var maxDelay: TimeInterval
        var jitter: Double
    }
    
    private var clientPolicy = ReconnectPolicy(maxAttempts: 5, baseDelay: 0.5, maxDelay: 8.0, jitter: 0.3)
    private var serverPolicy: ReconnectPolicy? = nil
    private var manualAttempt: Int = 0
    private var allowReconnect: Bool = true

    // Network reachability (to wait when offline)
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "outpick.socket.pathmonitor")

    // Stable client key to help server track attempt windows
    private static let clientKey: String = {
        if let id = UIDevice.current.identifierForVendor?.uuidString { return "ios-\(id)" }
        return "ios-\(UUID().uuidString)"
    }()

    // MARK: - Socket Error
    enum SocketError: Error {
        case connectionFailed([Any])
        case invalidRoomID
    }
    
    var manager: SocketManager!
    var socket: SocketIOClient!
    
    private var connectWaiters: [CheckedContinuation<Void, Error>] = []
    
    // 연결 상태 확인 프로퍼티 추가
    var isConnected: Bool {
        return socket.status == .connected
    }
    
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    // Combine의 PassthroughSubject를 사용하여 이벤트 스트림 생성
    // 새로운 참여자 알림을 위한 Publisher 추가
    private let participantSubject = PassthroughSubject<(String, String), Never>() // (roomName, email)
    var participantUpdatePublisher: AnyPublisher<(String, String), Never> {
        return participantSubject.eraseToAnyPublisher()
    }
    
    private var didBindListeners = false
    
    private var joinedRooms = Set<String>()
    private var pendingRooms: Set<String> = []
    
    private var roomSessionActors = [String: ChatRoomSessionActor]()
    private var roomStreamTasks = [String: Task<Void, Never>]()
    private var roomBridgeReady = Set<String>()
    private var roomSubjects = [String: PassthroughSubject<ChatMessage, Never>]()
    private var subscriberCounts = [String: Int]() // 구독자 ref count
    private var isChatMessageListenerBound = false
    private var isImageMessageListenerBound = false
    private var isVideoMessageListenerBound = false
    
    // https://outpick-socket-715386497547.asia-northeast3.run.app - Cloud Run
    private init(repositories: FirebaseRepositoryProviding = FirebaseRepositoryProvider.shared) {
        self.userProfileRepository = repositories.userProfileRepository
        self.chatRoomRepository = repositories.chatRoomRepository
        manager = SocketManager(socketURL: URL(string: "http://192.168.123.172:3000")!, config: [
            .log(true),
            .compress,
            // 서버가 WebSocket only(transports:['websocket'])로 동작하므로 클라이언트도 폴링을 비활성화
            .forceWebsockets(true),
            .forcePolling(false),
            .connectParams(["clientKey": SocketIOManager.clientKey, "email": LoginManager.shared.getUserEmail]),
            .reconnects(false) // 수동 재연결을 사용(라이브러리 자동 재연결 비활성화)
        ])
        socket = manager.defaultSocket

        socket.on(clientEvent: .connect) {data, ack in
            print("Socket Connected")
            // reset manual attempts on successful connect
            self.manualAttempt = 0
            // lightweight hello → 서버가 정책/상태를 ack로 회신할 수 있음
            self.socket.emitWithAck("client:hello", ["attempt": 0]).timingOut(after: 3) { _ in
            }

            guard let nickName = LoginManager.shared.currentUserProfile?.nickname else { return }
            self.socket.emit("set username", nickName)

            // Re-join desired rooms on every connection (includes reconnects).
            let desiredRooms = self.joinedRooms.union(self.pendingRooms)
            for roomID in desiredRooms {
                self.socket.emit("join room", roomID)
                self.joinedRooms.insert(roomID)
            }
            self.pendingRooms.removeAll()
            self.resumeConnectWaiters()
        }

        socket.on(clientEvent: .error) { [weak self] data, _ in
            guard let self = self else { return }
            print("소켓 에러:", data)
            self.failConnectWaiters(with: SocketError.connectionFailed(data))
            self.scheduleManualRetryIfNeeded()
        }

        socket.on(clientEvent: .disconnect) { [weak self] data, _ in
            guard let self = self else { return }
            print("소켓 디스커넥트:", data)
            if !self.connectWaiters.isEmpty {
                self.failConnectWaiters(with: SocketError.connectionFailed(data))
            }
            self.scheduleManualRetryIfNeeded()
        }

        // 서버가 권장 재연결 정책을 알려줌
        socket.off("server:connect:ready")
        socket.on("server:connect:ready") { [weak self] data, _ in
            guard let self = self else { return }
            guard let root = data.first as? [String: Any],
                  let p = root["policy"] as? [String: Any] else { return }

            func toDouble(_ any: Any?) -> Double? {
                if let d = any as? Double { return d }
                if let i = any as? Int { return Double(i) }
                if let s = any as? String, let v = Double(s) { return v }
                return nil
            }

            let maxAttempts = (p["maxAttempts"] as? Int) ?? self.clientPolicy.maxAttempts
            let baseDelayMs = toDouble(p["baseDelayMs"]) ?? (self.clientPolicy.baseDelay * 1000)
            let maxDelayMs  = toDouble(p["maxDelayMs"])  ?? (self.clientPolicy.maxDelay  * 1000)
            let jitter      = toDouble(p["jitter"])      ?? self.clientPolicy.jitter

            self.serverPolicy = ReconnectPolicy(
                maxAttempts: maxAttempts,
                baseDelay: baseDelayMs / 1000.0,
                maxDelay: maxDelayMs / 1000.0,
                jitter: jitter
            )
            #if DEBUG
            print("[server:connect:ready] policy =", self.serverPolicy as Any)
            #endif
        }

        // 네트워크 상태 감시 시작(offline → online 전환 시 재시도)
        startPathMonitor()
    }
    
    func establishConnection() async throws {
        // 의도적 종료가 아니면 재연결 허용
        allowReconnect = true
        // 이미 연결된 경우
        if socket.status == .connected {
            print("이미 연결된 상태")
            return
        }

        // 연결 중인 경우
        if socket.status == .connecting {
            print("이미 연결 중인 상태")
            try await withCheckedThrowingContinuation { continuation in
                self.connectWaiters.append(continuation)
            }
            return
        }

        // 연결 시도
        try await withCheckedThrowingContinuation { continuation in
            self.connectWaiters.append(continuation)

            print("소켓 연결 시도")
            self.socket.connect()
        }
    }
    
    func closeConnection() {
        allowReconnect = false
        manualAttempt = 0
        tearDownRoomStreams()
        failConnectWaiters(with: SocketError.connectionFailed(["manual disconnect"]))
        socket.disconnect()
    }

    func resetRoomMembership() {
        joinedRooms.removeAll()
        pendingRooms.removeAll()
    }

    func openRoomSession(for roomID: String) async throws -> ChatRoomSocketSession {
        guard !roomID.isEmpty else { throw SocketError.invalidRoomID }

        bindMessageListenersIfNeeded()

        let sessionActor = roomSessionActor(for: roomID)
        let consumer = await sessionActor.addConsumer()

        do {
            try await establishConnection()
        } catch {
            let isEmpty = await sessionActor.removeConsumer(consumer.id)
            if isEmpty {
                roomSessionActors.removeValue(forKey: roomID)
            }
            throw error
        }

        joinRoom(roomID)

        return ChatRoomSocketSession(
            roomID: roomID,
            messages: consumer.stream,
            close: {
                await SocketIOManager.shared.closeRoomSession(roomID: roomID, consumerID: consumer.id)
            }
        )
    }

    func closeRoomSession(roomID: String, consumerID: UUID) async {
        guard let sessionActor = roomSessionActors[roomID] else { return }

        let isEmpty = await sessionActor.removeConsumer(consumerID)
        if isEmpty {
            roomSessionActors.removeValue(forKey: roomID)
            if roomSubjects[roomID] == nil && roomStreamTasks[roomID] == nil {
                leaveRoom(roomID)
            }
        }
    }
    
    func subscribeToMessages(for roomID: String) -> AnyPublisher<ChatMessage, Never> {
        print(#function, "✅✅✅✅✅ 2. subscribeToMessages 호출")
        
        subscriberCounts[roomID, default: 0] += 1

        if roomSubjects[roomID] == nil {
            let subject = PassthroughSubject<ChatMessage, Never>()
            roomSubjects[roomID] = subject
            startRoomStreamBridge(for: roomID)
        }

        return roomSubjects[roomID]!.eraseToAnyPublisher()
    }

    func unsubscribeFromMessages(for roomID: String) {
        guard let count = subscriberCounts[roomID], count > 0 else { return }
        subscriberCounts[roomID] = count - 1

        if subscriberCounts[roomID] == 0 {
            subscriberCounts[roomID] = nil
            roomStreamTasks[roomID]?.cancel()
            roomStreamTasks[roomID] = nil
            roomBridgeReady.remove(roomID)
            roomSubjects[roomID]?.send(completion: .finished)
            roomSubjects[roomID] = nil
        }

        if roomSubjects.isEmpty && roomStreamTasks.isEmpty {
            detachChatListener()
            detachImageListener()
            detachVideoListener()
        }
    }

    private func bindMessageListenersIfNeeded() {
        attachChatListener()
        attachImageListener()
        attachVideoListener()
    }

    private func publishIncoming(_ message: ChatMessage) {
        emitToRoomPipeline(message)
    }

    private func roomSessionActor(for roomID: String) -> ChatRoomSessionActor {
        if let actor = roomSessionActors[roomID] {
            return actor
        }

        let actor = ChatRoomSessionActor()
        roomSessionActors[roomID] = actor
        return actor
    }

    private func startRoomStreamBridge(for roomID: String) {
        _ = roomSessionActor(for: roomID)
        bindMessageListenersIfNeeded()

        roomStreamTasks[roomID]?.cancel()
        roomStreamTasks[roomID] = Task { [weak self] in
            guard let self else { return }

            do {
                let session = try await self.openRoomSession(for: roomID)
                self.roomBridgeReady.insert(roomID)
                defer {
                    self.roomBridgeReady.remove(roomID)
                    Task { [weak self] in
                        await session.close()
                    }
                }

                for await message in session.messages {
                    if Task.isCancelled { break }

                    await MainActor.run { [weak self] in
                        self?.roomSubjects[roomID]?.send(message)
                    }
                }
            } catch {
                #if DEBUG
                print("[SocketIOManager] failed to open room stream roomID=\(roomID): \(error)")
                #endif
            }
        }
    }

    private func emitToRoomPipeline(_ message: ChatMessage) {
        let roomID = message.roomID
        guard !roomID.isEmpty else { return }

        if roomBridgeReady.contains(roomID), let sessionActor = roomSessionActors[roomID] {
            Task {
                await sessionActor.publish(message)
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.roomSubjects[roomID]?.send(message)
        }
    }

    private func tearDownRoomStreams() {
        let tasks = Array(roomStreamTasks.values)
        roomStreamTasks.removeAll()
        roomBridgeReady.removeAll()
        tasks.forEach { $0.cancel() }

        let actors = Array(roomSessionActors.values)
        roomSessionActors.removeAll()
        Task {
            for actor in actors {
                await actor.finishAll()
            }
        }

        roomSubjects.values.forEach { $0.send(completion: .finished) }
        roomSubjects.removeAll()
        subscriberCounts.removeAll()

        detachChatListener()
        detachImageListener()
        detachVideoListener()
    }

    private func attachChatListener() {
        guard !isChatMessageListenerBound else { return }
        isChatMessageListenerBound = true

        let event = "chat message"
        print(#function, "bind →", event)
        socket.off(event)

        socket.on(event) { [weak self] data, _ in
            guard let self else { return }
            guard let dict = data.first as? [String: Any] else {
                #if DEBUG
                print("[attachChatListener] invalid payload (not dict):", data)
                #endif
                return
            }

            guard let message = ChatMessage.from(dict) else {
                #if DEBUG
                print("[attachChatListener] parse failed =", dict)
                #endif
                return
            }
            self.publishIncoming(message)
        }
    }

    private func detachChatListener() {
        isChatMessageListenerBound = false
        socket.off("chat message")
    }

    // 이미지 수신용 리스너
    private func attachImageListener() {
        guard !isImageMessageListenerBound else { return }
        isImageMessageListenerBound = true

        let event = "receiveImages"
        print(#function, "bind →", event)
        socket.off(event)

        socket.on(event) { [weak self] data, _ in
            guard let self else { return }
            guard let dict = data.first as? [String: Any] else {
                #if DEBUG
                print("[attachImageListener] invalid payload (not dict):", data)
                #endif
                return
            }
            // Normalize server payload (senderNickname vs senderNickName, id vs ID)
            var normalized = dict
            if normalized["senderNickName"] == nil, let v = normalized["senderNickname"] { normalized["senderNickName"] = v }
            if normalized["ID"] == nil, let v = normalized["id"] as? String { normalized["ID"] = v }

            guard let message = ChatMessage.from(normalized) else {
                #if DEBUG
                print("[attachImageListener] parse failed normalized=", normalized)
                #endif
                return
            }
            self.publishIncoming(message)
        }
    }

    // 비디오 수신용 리스너
    private func attachVideoListener() {
        guard !isVideoMessageListenerBound else { return }
        isVideoMessageListenerBound = true

        let event = "receiveVideo"
        print(#function, "bind →", event)
        socket.off(event)

        socket.on(event) { [weak self] data, _ in
            guard let self else { return }
            guard let dict = data.first as? [String: Any] else {
                #if DEBUG
                print("[attachVideoListener] invalid payload (not dict):", data)
                #endif
                return
            }

            // Normalize server payload (senderNickname vs senderNickName, id vs ID)
            var normalized = dict
            if normalized["senderNickName"] == nil, let v = normalized["senderNickname"] { normalized["senderNickName"] = v }
            if normalized["ID"] == nil, let v = normalized["id"] as? String { normalized["ID"] = v }

            guard let message = ChatMessage.from(normalized) else {
                #if DEBUG
                print("[attachVideoListener] parse failed normalized=", normalized)
                #endif
                return
            }
            self.publishIncoming(message)
        }
    }

    private func detachVideoListener() {
        isVideoMessageListenerBound = false
        socket.off("receiveVideo")
    }

    private func detachImageListener() {
        isImageMessageListenerBound = false
        socket.off("receiveImages")
    }
    
    func joinRoom(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        if socket.status == .connected {
            guard joinedRooms.insert(roomID).inserted else {
                print("이미 참여한 방:", roomID); return
            }
            socket.emit("join room", roomID)
        } else {
            // Not connected: queue for joining after connect
            pendingRooms.insert(roomID)
        }
        // listener off/on은 유지해도 됨. emit 자체가 중복되지 않는 게 핵심
    }

    func leaveRoom(_ roomID: String) {
        guard !roomID.isEmpty else { return }

        pendingRooms.remove(roomID)
        let wasJoined = joinedRooms.remove(roomID) != nil
        guard wasJoined else { return }

        if socket.status == .connected {
            socket.emit("leave room", roomID)
        }
    }
    
    func createRoom(_ roomID: String) {
        print("createRoom 호출 - roomID: ", roomID)
        
        guard socket.status == .connected else {
            print("소켓이 연결되지 않음")
            return
        }
        
        // 기존 방 생성 관련 리스너 제거 (중복 방지)
        socket.off("room created")
        socket.off("room error")
        
        socket.emit("create room", roomID)
        
        // 방 생성 성공/실패 모니터링
        socket.on("room created") { data, _ in
            print("방 생성 성공: ", data)
        }
        socket.on("room error") { data, _ in
            print("방 생성 실패: ", data)
        }
    }

    private func updateRoomSummaryAfterSend(roomID: String, sentAt: Date, preview: String) {
        guard !roomID.isEmpty else { return }
        let trimmedPreview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPreview.isEmpty else { return }
        let senderID = LoginManager.shared.getUserEmail

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.chatRoomRepository.updateRoomLastMessage(
                roomID: roomID,
                date: sentAt,
                msg: trimmedPreview,
                senderID: senderID
            )
        }
    }

    /// 서버 ACK 형식이 환경별로 달라도(딕셔너리/문자열/빈 응답) 보수적으로 성공 여부를 판별
    private func isEmitAckSuccess(_ ackItems: [Any]) -> Bool {
        guard let first = ackItems.first else {
            // 일부 서버는 ACK payload를 비워두므로 성공으로 간주
            return true
        }

        if let dict = first as? [String: Any] {
            if let ok = dict["ok"] as? Bool { return ok || ((dict["duplicate"] as? Bool) ?? false) }
            if let success = dict["success"] as? Bool { return success || ((dict["duplicate"] as? Bool) ?? false) }
            if let duplicate = dict["duplicate"] as? Bool, duplicate { return true }

            if let status = (dict["status"] as? String)?.lowercased() {
                if ["ok", "success", "accepted", "duplicate"].contains(status) { return true }
                if ["error", "failed", "fail"].contains(status) { return false }
            }
            if dict["error"] != nil { return false }
            return true
        }

        if let text = first as? String {
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized.isEmpty || normalized == "no ack" { return true }
            if normalized.contains("error") || normalized.contains("fail") { return false }
            return true
        }

        return true
    }
    
    func sendMessage(_ room: ChatRoom, _ message: ChatMessage) {
        // 1. Optimistic UI: Publish the message immediately as not failed
        // 2. If not connected, mark as failed and publish (again, so UI can update)
        guard socket.status == .connected else {
            print("소켓이 연결되지 않음")
            var failedMessage = message
            failedMessage.isFailed = true
            emitToRoomPipeline(failedMessage)
            return
        }

        let payload = message.toSocketRepresentation()
        print("📤 전송할 소켓 데이터: \(payload)")  // 디버깅용

        socket.emitWithAck("chat message", payload).timingOut(after: 5) { [weak self] ackResponse in
            guard let self = self else { return }

            if self.isEmitAckSuccess(ackResponse) {
                self.updateRoomSummaryAfterSend(
                    roomID: room.ID ?? "",
                    sentAt: message.sentAt ?? Date(),
                    preview: message.msg ?? ""
                )
            } else {
                // Failure: mark the same message as failed and re-publish for UI update
                var failedMessage = message
                failedMessage.isFailed = true
                self.emitToRoomPipeline(failedMessage)
            }
        }
    }
    
    // MARK: - Emit (meta-only attachments)
    /// 메타 전용 첨부(썸네일/원본 경로 등)를 소켓으로 전송
    /// ChatViewController에서 attachments.map { $0.toDict() } 로 호출합니다.
    func sendImages(_ room: ChatRoom,
                    _ attachments: [[String: Any]],
                    senderAvatarPath: String? = nil,
                    clientMessageID: String? = nil) {
        // 0) 가드
        guard !attachments.isEmpty else { return }
        let roomID = room.ID ?? ""
        let senderID = LoginManager.shared.getUserEmail
        let senderNickname = LoginManager.shared.currentUserProfile?.nickname ?? ""
        let resolvedClientMessageID: String = {
            if let clientMessageID, !clientMessageID.isEmpty {
                return clientMessageID
            }
            return UUID().uuidString
        }()
        let now = Date()
        let isoSentAt = Self.isoFormatter.string(from: now)
        print(#function," attachments", attachments)
        // 헬퍼: dict -> Attachment 모델 변환 (로컬 퍼블리시용)
        func makeAttachment(from dict: [String: Any], fallbackIndex: Int) -> Attachment {
            let index = dict["index"] as? Int ?? fallbackIndex
            let pathThumb = (dict["pathThumb"] as? String) ?? ""
            let pathOriginal = (dict["pathOriginal"] as? String) ?? ""
            let width = (dict["w"] as? Int) ?? (dict["width"] as? Int) ?? 0
            let height = (dict["h"] as? Int) ?? (dict["height"] as? Int) ?? 0
            let bytesOriginal = (dict["bytesOriginal"] as? Int) ?? (dict["size"] as? Int) ?? 0
            let hash = (dict["hash"] as? String) ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let blurhash = dict["blurhash"] as? String
            return Attachment(
                type: .image,
                index: index,
                pathThumb: pathThumb,
                pathOriginal: pathOriginal,
                width: width,
                height: height,
                bytesOriginal: bytesOriginal,
                hash: hash,
                blurhash: blurhash,
                duration: nil
            )
        }

        // 연결 안 되어 있으면 실패 메시지 로컬 퍼블리시
        guard socket.status == .connected else {
            let atts = attachments.enumerated().map { makeAttachment(from: $0.element, fallbackIndex: $0.offset) }
            var failed = ChatMessage(
                ID: resolvedClientMessageID, seq: 0,
                roomID: roomID,
                senderID: senderID,
                senderNickname: senderNickname,
                msg: "",
                sentAt: now,
                attachments: atts,
                replyPreview: nil,
                isFailed: true
            )
            if let avatar = senderAvatarPath, !avatar.isEmpty {
                failed.senderAvatarPath = avatar
            }
            emitToRoomPipeline(failed)
            return
        }
            
        // 1) 서버 이벤트/페이로드 구성(메타만 포함)
        let eventName = "send images" // 새 프로토콜 이벤트명 (서버 index.js와 일치)
        var body: [String: Any] = [
            "roomID": roomID,
            "messageID": resolvedClientMessageID,
            "type": "image",
            "msg": "",
            "attachments": attachments,
            "senderID": senderID,
            "senderNickname": senderNickname,
            "sentAt": isoSentAt
        ]
        if let avatar = senderAvatarPath, !avatar.isEmpty {
            body["senderAvatarPath"] = avatar
        }

        // NOTE: 성공 시에는 로컬 퍼블리시를 하지 않는다.
        // reason: 서버 브로드캐스트가 ACK보다 먼저 도착할 수 있어, 이후에 퍼블리시된 seq=0 스텁이
        //         정규 메시지를 덮어써 UI 상에서 seq가 0으로 보이는 문제가 발생할 수 있음.
        socket.emitWithAck(eventName, body).timingOut(after: 15) { [weak self] ackResponse in
            guard let self = self else { return }

            if self.isEmitAckSuccess(ackResponse) {
                // 성공/중복(이미 서버가 브로드캐스트했을 가능성) 시에는
                // 로컬에 seq=0 메시지를 퍼블리시하지 않습니다.
                // → 서버의 'receiveImages' 브로드캐스트로 도착하는 정규 메시지(정확한 seq 포함)에 UI를 맡깁니다.
                self.updateRoomSummaryAfterSend(
                    roomID: roomID,
                    sentAt: now,
                    preview: "사진 \(attachments.count)장"
                )
                return
            }

            // 실패/타임아웃: 실패 메시지를 로컬에만 퍼블리시해 재시도 UX 제공
            let atts = attachments.enumerated().map { makeAttachment(from: $0.element, fallbackIndex: $0.offset) }
            var failed = ChatMessage(
                ID: resolvedClientMessageID, seq: 0,
                roomID: roomID,
                senderID: senderID,
                senderNickname: senderNickname,
                msg: "",
                sentAt: now,
                attachments: atts,
                replyPreview: nil,
                isFailed: true
            )
            if let avatar = senderAvatarPath, !avatar.isEmpty {
                failed.senderAvatarPath = avatar
            }
            self.emitToRoomPipeline(failed)
        }
    }
    
    /// 업로드/송신 실패 시: preparePairs에서 받은 ImagePair 배열을 이용해
    /// 로컬 프리뷰 파일을 만들고 실패 메시지(ChatMessage)를 생성한다.
    /// - Parameters:
    ///   - room: 대상 방
    ///   - pairs: ImagePair 배열 (index 순서로 정렬됨이 보장되지는 않음)
    ///   - publish: true면 내부에서 roomSubject로 곧바로 퍼블리시, false면 퍼블리시하지 않음
    ///   - onBuilt: 실패 메시지 객체를 콜백으로 전달(썸네일 캐시/추가 가공 후 VC에서 addMessages 호출용)
    func sendFailedImages(_ room: ChatRoom,
                          fromPairs pairs: [DefaultMediaProcessingService.ImagePair],
                          publish: Bool = true) {
        guard !pairs.isEmpty else { return }

        let roomID = room.ID ?? ""
        let senderID = LoginManager.shared.getUserEmail
        let senderNickname = LoginManager.shared.currentUserProfile?.nickname ?? ""

        // 로컬 파일 저장 디렉터리 (앱 캐시)
        let fm = FileManager.default
        let baseDir: URL = {
            let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("failed-attachments", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }()

        @discardableResult
        func writeTempFile(_ data: Data, ext: String = "jpg") -> URL? {
            let name = UUID().uuidString + "." + ext
            let url = baseDir.appendingPathComponent(name)
            do {
                try data.write(to: url, options: .atomic)
                return url
            } catch {
                print("[sendFailedImages] failed to write temp file: \(error)")
                return nil
            }
        }

        var atts: [Attachment] = []
        atts.reserveCapacity(pairs.count)

        for p in pairs.sorted(by: { $0.index < $1.index }) {
            autoreleasepool {
                guard let fileURL = writeTempFile(p.thumbData) else { return }
                let att = Attachment(
                    type: .image,
                    index: p.index,
                    pathThumb: fileURL.absoluteString,     // "file://" 로컬 경로
                    pathOriginal: fileURL.absoluteString,  // 뷰어에서도 프리뷰 노출을 위해 동일 경로
                    width: p.originalWidth,
                    height: p.originalHeight,
                    bytesOriginal: p.thumbData.count,
                    hash: p.sha256,
                    blurhash: nil,
                    duration: nil
                )
                atts.append(att)
            }
        }

        let failedMessage = ChatMessage(
            ID: UUID().uuidString, seq: 0,
            roomID: roomID,
            senderID: senderID,
            senderNickname: senderNickname,
            msg: "",
            sentAt: Date(),
            attachments: atts,
            replyPreview: nil,
            isFailed: true
        )

        emitToRoomPipeline(failedMessage)
    }

    
    private func processFailedImages(_ room: ChatRoom, _ images: [UIImage]) async {
        // 빈 입력이면 종료
        guard !images.isEmpty else { return }

        // 실패 시에도 메모리 사용을 줄이기 위해 다운스케일 + 압축(로컬 프리뷰용)
        let maxDimension: CGFloat = 1600
        let jpegQuality: CGFloat = 0.6

        // 로컬 파일 저장 디렉터리 (앱 캐시)
        let fm = FileManager.default
        let baseDir: URL = {
            let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("failed-attachments", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }()

        // 헬퍼: 이미지 다운스케일 후 JPEG Data 생성
        func downscaleJPEGData(_ image: UIImage, maxEdge: CGFloat, quality: CGFloat) -> Data? {
            let size = image.size
            guard size.width > 0 && size.height > 0 else { return image.jpegData(compressionQuality: quality) }
            let scale = Swift.min(1.0, maxEdge / Swift.max(size.width, size.height))
            let targetSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
            if scale >= 1.0 {
                return image.jpegData(compressionQuality: quality)
            }
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1.0
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            let scaled = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            return scaled.jpegData(compressionQuality: quality)
        }

        // 헬퍼: SHA-256(hex)
        func sha256Hex(_ data: Data) -> String {
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        }

        // 헬퍼: 캐시 디렉터리에 파일 저장 후 file:// URL 반환
        func writeTempFile(_ data: Data, ext: String = "jpg") -> URL? {
            let name = UUID().uuidString + "." + ext
            let url = baseDir.appendingPathComponent(name)
            do {
                try data.write(to: url, options: .atomic)
                return url
            } catch {
                print("failed to write temp file: \(error)")
                return nil
            }
        }

        var localAttachments: [Attachment] = []
        localAttachments.reserveCapacity(images.count)

        // 순차 처리 + autoreleasepool로 메모리 피크 완화
        for (idx, image) in images.enumerated() {
            autoreleasepool {
                guard let data = downscaleJPEGData(image, maxEdge: maxDimension, quality: jpegQuality),
                      let fileURL = writeTempFile(data) else { return }

                let hash = sha256Hex(data)
                let pw = image.cgImage?.width ?? Int(image.size.width * image.scale)
                let ph = image.cgImage?.height ?? Int(image.size.height * image.scale)

                // 메타 전용 Attachment (로컬 미리보기이므로 Thumb/Original을 동일 파일로 설정)
                let att = Attachment(
                    type: .image,
                    index: idx,
                    pathThumb: fileURL.absoluteString,     // "file://" 경로
                    pathOriginal: fileURL.absoluteString,  // "file://" 경로
                    width: pw,
                    height: ph,
                    bytesOriginal: data.count,
                    hash: hash,
                    blurhash: nil,
                    duration: nil
                )
                localAttachments.append(att)
            }
        }

        // 일부라도 생성되었으면 실패 메시지 전송 (메타만 포함)
        guard !localAttachments.isEmpty else { return }
        let failedMessage = ChatMessage(
            ID: UUID().uuidString, seq: 0,
            roomID: room.ID ?? "",
            senderID: LoginManager.shared.getUserEmail,
            senderNickname: LoginManager.shared.currentUserProfile?.nickname ?? "",
            msg: "",
            sentAt: Date(),
            attachments: localAttachments,
            replyPreview: nil,
            isFailed: true
        )

        emitToRoomPipeline(failedMessage)
    }
    
    // MARK: - Send: Video
    /// 비디오 메타만 서버로 전송 (바이너리 X). 서버는 이 메타로 메시지를 생성/중계한다.
    /// - Parameters:
    ///   - roomID: 방 ID
    ///   - payload: 업로드 완료된 비디오의 메타 정보
    ///   - ackTimeout: (선택) ACK 대기 시간
    ///   - completion: (선택) 성공/실패 콜백
    // MARK: - Send: Video
    /// 비디오 메타만 서버로 전송 (바이너리 X). 서버는 이 메타로 메시지를 생성/중계한다.
    /// 소켓 미연결/ACK 실패 시 로컬 실패 메시지를 주입한다.
    func sendVideo(roomID: String,
                   payload: VideoMetaPayload,
                   senderAvatarPath: String? = nil,
                   ackTimeout: Double = 5.0,
                   completion: ((Result<Void, Error>) -> Void)? = nil) {
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
            // (선택) 보낸이 정보 포함
            "senderID": LoginManager.shared.getUserEmail,
            "senderNickname": LoginManager.shared.currentUserProfile?.nickname ?? ""
        ]
        if let avatar = senderAvatarPath, !avatar.isEmpty {
            dict["senderAvatarPath"] = avatar
        }

        #if canImport(SocketIO)
        if socket.status == .connected {
            socket.emitWithAck("chat:video", dict).timingOut(after: ackTimeout) { [weak self] items in
                guard let self = self else { return }
                if self.isEmitAckSuccess(items) {
                    self.updateRoomSummaryAfterSend(
                        roomID: roomID,
                        sentAt: Date(),
                        preview: "동영상"
                    )
                    completion?(.success(()))
                } else {
                    // ACK 실패 → 로컬 실패 메시지 주입
                    self.sendFailedVideos(roomID: payload.roomID, payload: payload)
                    let err = NSError(domain: "SocketIO", code: -1,
                                      userInfo: [NSLocalizedDescriptionKey: "서버 ACK 실패 또는 형식 불일치: \(items)"])
                    completion?(.failure(err))
                }
            }
        } else {
            // 미연결: 실패 메시지 먼저 주입하고 재연결 시도
            self.sendFailedVideos(roomID: payload.roomID, payload: payload)
            socket.connect()
            let err = NSError(domain: "SocketIO", code: -1009,
                              userInfo: [NSLocalizedDescriptionKey: "소켓이 연결되어 있지 않습니다."])
            completion?(.failure(err))
        }
        #else
        // SocketIO 미링크 환경에서도 컴파일 가능하도록
        completion?(.success(()))
        #endif
    }
    
    // MARK: - Local Fail: Video
    /// 업로드 실패 또는 소켓 미연결 시, 로컬에서 '실패한 비디오 메시지'를 스트림에 주입합니다.
    /// 서버로는 아무 것도 전송하지 않으며, 재시도 UX를 위해 타임라인에 즉시 반영합니다.
    /// - Parameters:
    ///   - roomID: 방 ID
    ///   - senderID: 보낸 사람 UID
    ///   - senderNickname: 보낸 사람 닉네임
    ///   - localURL: 압축된 비디오의 로컬 파일 URL (mp4 등)
    ///   - thumbData: 썸네일 JPEG 데이터(옵션). 있으면 임시 파일로 저장해 pathThumb에 넣습니다.
    ///   - duration: 비디오 길이(초)
    ///   - width: 비디오 가로 해상도
    ///   - height: 비디오 세로 해상도
    ///   - presetCode: "standard720" | "dataSaver720" | "high1080" 등 (로깅용)
    func sendFailedVideos(roomID: String,
                          senderID: String,
                          senderNickname: String,
                          localURL: URL,
                          thumbData: Data?,
                          duration: Double,
                          width: Int,
                          height: Int,
                          presetCode: String) {
        // 1) 파일 크기
        let bytes: Int64 = (try? (FileManager.default
            .attributesOfItem(atPath: localURL.path)[.size] as? NSNumber)?.int64Value) ?? 0
        
        // 2) 썸네일을 임시 경로로 저장 (UI에서 즉시 표시 가능)
        var thumbPath: String = ""
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
        
        // 3) 실패 메시지용 ID/해시
        let clientMessageID = "failed-\(UUID().uuidString)"
        
        // 4) 첨부(.video) 구성 — 로컬 경로를 그대로 넣어 미리보기/재시도에 활용
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
        
        // 5) 실패 ChatMessage 구성
        let message = ChatMessage(
            ID: clientMessageID, seq: 0,
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
        
        // 6) 로컬 스트림으로 즉시 발행 (UI 업데이트)
        emitToRoomPipeline(message)
    }
    
    /// 업로드는 성공했으나 소켓 전송(브로드캐스트)이 실패한 경우: 원격(Storage) 경로 기반으로 실패 메시지 발행
    func sendFailedVideos(roomID: String, payload: VideoMetaPayload) {
        let senderID = LoginManager.shared.getUserEmail
        let senderNickname = LoginManager.shared.currentUserProfile?.nickname ?? ""

        // 서버 브로드캐스트 포맷과 동일한 첨부(.video), 단 isFailed만 true
        let attachment = Attachment(
            type: .video,
            index: 0,
            pathThumb: payload.thumbnailPath,
            pathOriginal: payload.storagePath,
            width: payload.width,
            height: payload.height,
            bytesOriginal: Int(payload.sizeBytes),
            hash: payload.messageID,
            blurhash: nil,
            duration: payload.duration
        )

        // 실패 메시지 ID는 충돌 방지를 위해 prefix 부여
        let failedID = "failed-\(payload.messageID)"
        let message = ChatMessage(
            ID: failedID, seq: 0,
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

        emitToRoomPipeline(message)
    }
    
    /// 방 나가기 / 방 종료 요청
    /// - Note:
    ///   클라이언트는 roomID와 "leave-or-close" 의도만 서버로 전달하고,
    ///   실제 방장 여부 판단 및 Firestore 상태 변경(방 종료 / 단순 나가기)은 서버에서 처리합니다.
    /// - Parameters:
    ///   - roomID: 나가거나 종료하려는 방 ID
    ///   - ackTimeout: 서버 ACK 대기 시간(초)
    ///   - completion: 성공 / 실패 결과 콜백 (옵션)
    func requestLeaveOrCloseRoom(roomID: String,
                                 ackTimeout: Double = 5.0,
                                 completion: ((Result<Void, Error>) -> Void)? = nil) {
        // 소켓 미연결 시 즉시 실패 콜백
        guard socket.status == .connected else {
            #if DEBUG
            print("[requestLeaveOrCloseRoom] socket not connected")
            #endif
            let err = NSError(
                domain: "SocketIO",
                code: -1009,
                userInfo: [NSLocalizedDescriptionKey: "소켓이 연결되어 있지 않습니다."]
            )
            completion?(.failure(err))
            return
        }

        // 클라는 roomID + "나가기/종료 의도"만 전달
        // 서버는 Socket.IO 연결 정보(이메일 등) + Firestore 상태를 보고
        // 방장이라면 방 종료, 참가자라면 단순 나가기 처리
        let payload: [String: Any] = [
            "roomID": roomID,
            "intent": "leave-or-close"
        ]

        let eventName = "room:leave-or-close"
        #if DEBUG
        print("[requestLeaveOrCloseRoom] emit \(eventName) payload=", payload)
        #endif

        socket.emitWithAck(eventName, payload).timingOut(after: ackTimeout) { items in
            // 서버에서 { ok: Bool, message?: String } 형태로 응답한다고 가정
            if let first = items.first as? [String: Any] {
                let ok = (first["ok"] as? Bool) ?? (first["success"] as? Bool) ?? false
                if ok {
                    completion?(.success(()))
                    return
                } else {
                    let message = first["message"] as? String ?? "방 나가기/종료 처리 실패"
                    let err = NSError(
                        domain: "SocketIO",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: message]
                    )
                    completion?(.failure(err))
                    return
                }
            }

            // 응답이 비어 있는 경우: 서버가 ACK를 사용하지 않는 환경일 수 있으므로 성공으로 간주
            if items.isEmpty {
                #if DEBUG
                print("[requestLeaveOrCloseRoom] empty ACK items, treat as success")
                #endif
                completion?(.success(()))
                return
            }

            // 알 수 없는 형식의 응답
            let err = NSError(
                domain: "SocketIO",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "알 수 없는 ACK 응답 형식: \(items)"]
            )
            completion?(.failure(err))
        }
    }

    func setUserName(_ userName: String) {
        print("setUserName 호출됨: \(userName)")
        socket.emit("set username", userName)
        print("유저 이름 이벤트 emit 완료")
    }

    func notifyNewParticipant(roomID: String, email: String) {
        guard socket.status == .connected else {
            print("소켓이 연결되어 있지 않아 새 참여자 알림 emit 실패")
            return
        }
        
        print("새 참여자 알림 emit - room: \(roomID), email: \(email)")
        socket.emit("new participant joined", roomID, email)
    }
    
    func listenToNewParticipant() {
        socket.off("room participant updated")
        socket.on("room participant updated") { [weak self] data, _ in
            guard let self = self,
                  let dict = data.first as? [String: String],
                  let roomID = dict["roomID"],
                  let email = dict["email"] else {
                print("room participant updated 수신 실패: 데이터 형식 불일치")
                return
            }

            Task { @MainActor in
                do {
                    let profile = try await self.userProfileRepository.fetchUserProfileFromFirestore(email: email)
                    
                    // GRDB를 통해 로컬 DB에 저장
                    try await GRDBManager.shared.dbPool.write { db in
                        try profile.save(db)
                        try db.execute(
                            sql: "INSERT OR REPLACE INTO roomParticipant (roomID, email) VALUES (?, ?)",
                            arguments: [roomID, email]
                        )
                    }
                    
                    // 새로운 참여자 알림 발행
                    self.participantSubject.send((roomID, email))
                    
                } catch {
                    print("새 참여자 프로필 불러오기/저장 실패: \(error)")
                }
            }
        }
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
}

extension SocketIOManager {
    // 현재 적용 정책(서버 우선)
    private var effectivePolicy: ReconnectPolicy {
        serverPolicy ?? clientPolicy
    }

    private func backoffDelay(for attempt: Int) -> TimeInterval {
        let p = effectivePolicy
        let base = min(p.maxDelay, p.baseDelay * pow(2, Double(max(0, attempt - 1))))
        let jitter = base * p.jitter * Double.random(in: -1...1)
        return max(0, base + jitter)
    }

    private func scheduleManualRetryIfNeeded() {
        guard allowReconnect else { return }
        // 이미 연결 중이면 중복 connect 방지
        guard socket.status != .connected && socket.status != .connecting else { return }

        // 네트워크 없으면 대기(online 전환 시 pathMonitor가 재시도)
        if pathMonitor.currentPath.status != .satisfied {
            #if DEBUG
            print("[retry] waiting for network...")
            #endif
            return
        }

        let limit = effectivePolicy.maxAttempts
        guard manualAttempt < limit else {
            #if DEBUG
            print("[retry] max attempts reached (\(limit)) — stop")
            #endif
            return
        }
        manualAttempt += 1
        let d = backoffDelay(for: manualAttempt)
        #if DEBUG
        print("[retry] attempt \(manualAttempt)/\(limit) in \(String(format: "%.2f", d))s")
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in
            guard let self = self, self.allowReconnect else { return }
            if self.socket.status != .connected && self.socket.status != .connecting {
                self.socket.connect()
            }
        }
    }

    private func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            if path.status == .satisfied {
                // 온라인 복구 시 남은 횟수 안에서 재시도
                self.scheduleManualRetryIfNeeded()
            }
        }
        pathMonitor.start(queue: pathQueue)
    }
}
