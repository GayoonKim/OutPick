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
    let uid: String
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
        let idToken = try await currentFirebaseIDToken(forcingRefresh: false)
        return SocketSessionIdentity(
            uid: currentUserProvider.canonicalUserID
                .trimmingCharacters(in: .whitespacesAndNewlines),
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

    func replacingIDToken(_ idToken: String) throws -> SocketSessionIdentity {
        let trimmedToken = idToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw SocketIdentityError.missingIDToken
        }

        return SocketSessionIdentity(
            uid: uid,
            email: email,
            nickname: nickname,
            avatarPath: avatarPath,
            clientKey: clientKey,
            socketURL: socketURL,
            idToken: trimmedToken
        )
    }

    @MainActor
    static func refreshingIDToken(
        for identity: SocketSessionIdentity
    ) async throws -> SocketSessionIdentity {
        let idToken = try await currentFirebaseIDToken(forcingRefresh: true)
        return try identity.replacingIDToken(idToken)
    }

    @MainActor
    private static func currentFirebaseIDToken(
        forcingRefresh: Bool
    ) async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw SocketIdentityError.missingFirebaseUser
        }

        return try await withCheckedThrowingContinuation { continuation in
            user.getIDTokenForcingRefresh(forcingRefresh) { token, error in
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

#if DEBUG
struct SocketDebugQAConfiguration: Sendable {
    static let socketURLKey = "OUTPICK_DEBUG_SOCKET_URL"
    static let dropFirstMessageAckKindKey = "OUTPICK_DEBUG_DROP_FIRST_MESSAGE_ACK_KIND"

    private let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    func socketURL(productionURL: URL) -> URL {
        guard let rawValue = environment[Self.socketURLKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty,
              let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return productionURL
        }
        return url
    }

    func shouldDropFirstMessageAck(kind: String) -> Bool {
        let configuredKinds = Set(
            (environment[Self.dropFirstMessageAckKindKey] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        return configuredKinds.contains("all") || configuredKinds.contains(kind.lowercased())
    }
}
#endif

struct ChatRoomSocketSession: Sendable {
    let roomID: String
    let messages: AsyncStream<ChatMessage>
    let close: @Sendable () async -> Void
}

struct RealtimeVisibleRoomLease: Equatable, Sendable {
    let roomID: String
    let generation: UInt64
    let baselineSeq: Int64
    let promotionHighWatermark: Int64
}

enum RealtimeRoomIngressRoute: Equatable, Sendable {
    case background
    case visible(RealtimeVisibleRoomLease)
}

struct RealtimeRoomJoinState {
    enum BeginResult: Equatable {
        case alreadyJoined
        case inFlight(UUID)
        case started(UUID)
    }

    private(set) var confirmedRooms = Set<String>()
    private(set) var attempts = [String: UUID]()

    mutating func begin(roomID: String, attemptID: UUID = UUID()) -> BeginResult {
        if confirmedRooms.contains(roomID) {
            return .alreadyJoined
        }
        if let currentAttempt = attempts[roomID] {
            return .inFlight(currentAttempt)
        }
        attempts[roomID] = attemptID
        return .started(attemptID)
    }

    mutating func resolve(roomID: String, attemptID: UUID, succeeded: Bool) -> Bool {
        guard attempts[roomID] == attemptID else { return false }
        attempts.removeValue(forKey: roomID)
        if succeeded {
            confirmedRooms.insert(roomID)
        }
        return true
    }

    mutating func invalidateMembership() {
        confirmedRooms.removeAll()
        attempts.removeAll()
    }

    mutating func removeRoom(_ roomID: String) {
        confirmedRooms.remove(roomID)
        attempts.removeValue(forKey: roomID)
    }

    func isConfirmed(_ roomID: String) -> Bool {
        confirmedRooms.contains(roomID)
    }
}

struct RealtimeSocketReconnectState {
    struct ScheduledAttempt: Equatable {
        let id: UUID
        let number: Int
    }

    struct ScheduledNetworkProbe: Equatable {
        let id: UUID
        let number: Int
    }

    private(set) var isNetworkAvailable = false
    private(set) var needsReconnect = false
    private(set) var attemptCount = 0
    private(set) var scheduledAttempt: ScheduledAttempt?
    private(set) var networkProbeCount = 0
    private(set) var scheduledNetworkProbe: ScheduledNetworkProbe?
    private(set) var connectWatchdogID: UUID?

    mutating func updateNetworkAvailability(_ isAvailable: Bool) {
        isNetworkAvailable = isAvailable
        if isAvailable {
            networkProbeCount = 0
            scheduledNetworkProbe = nil
        } else {
            if scheduledAttempt != nil {
                attemptCount = max(0, attemptCount - 1)
            }
            scheduledAttempt = nil
        }
    }

    mutating func requestReconnect() {
        needsReconnect = true
    }

    mutating func scheduleIfPossible(
        isAllowed: Bool,
        maxAttempts: Int,
        attemptID: UUID = UUID()
    ) -> ScheduledAttempt? {
        guard isAllowed, needsReconnect, isNetworkAvailable else { return nil }
        guard scheduledAttempt == nil, attemptCount < max(0, maxAttempts) else { return nil }

        attemptCount += 1
        let attempt = ScheduledAttempt(id: attemptID, number: attemptCount)
        scheduledAttempt = attempt
        return attempt
    }

    mutating func consumeScheduledAttempt(id: UUID) -> Bool {
        guard scheduledAttempt?.id == id else { return false }
        scheduledAttempt = nil
        return needsReconnect && isNetworkAvailable
    }

    mutating func scheduleNetworkProbeIfPossible(
        isAllowed: Bool,
        probeID: UUID = UUID()
    ) -> ScheduledNetworkProbe? {
        guard isAllowed, needsReconnect, !isNetworkAvailable else { return nil }
        guard scheduledNetworkProbe == nil else { return nil }

        networkProbeCount += 1
        let probe = ScheduledNetworkProbe(id: probeID, number: networkProbeCount)
        scheduledNetworkProbe = probe
        return probe
    }

    mutating func consumeScheduledNetworkProbe(id: UUID) -> Bool {
        guard scheduledNetworkProbe?.id == id else { return false }
        scheduledNetworkProbe = nil
        return needsReconnect && !isNetworkAvailable
    }

    mutating func scheduleConnectWatchdogIfPossible(
        watchdogID: UUID = UUID()
    ) -> UUID? {
        guard needsReconnect, connectWatchdogID == nil else { return nil }
        connectWatchdogID = watchdogID
        return watchdogID
    }

    mutating func consumeConnectWatchdog(id: UUID) -> Bool {
        guard connectWatchdogID == id else { return false }
        connectWatchdogID = nil
        return needsReconnect
    }

    mutating func invalidateConnectWatchdog() {
        connectWatchdogID = nil
    }

    mutating func markConnected() {
        needsReconnect = false
        attemptCount = 0
        scheduledAttempt = nil
        networkProbeCount = 0
        scheduledNetworkProbe = nil
        connectWatchdogID = nil
    }

    mutating func cancelReconnect() {
        needsReconnect = false
        attemptCount = 0
        scheduledAttempt = nil
        networkProbeCount = 0
        scheduledNetworkProbe = nil
        connectWatchdogID = nil
    }
}

enum RealtimeRoomJoinAckMapper {
    static func isRoomNotFound(_ ackResponse: [Any]) -> Bool {
        guard let payload = ackResponse.first as? [String: Any] else { return false }
        let values = [payload["message"], payload["error"], payload["code"]]
        return values.contains { value in
            guard let text = value as? String else { return false }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "room_not_found"
        }
    }
}

struct RealtimeAuthoritativeRoomClosureState {
    private var closedRoomIDs = Set<String>()

    mutating func markClosed(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        closedRoomIDs.insert(roomID)
    }

    mutating func markCreated(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        closedRoomIDs.remove(roomID)
    }

    func isClosed(_ roomID: String) -> Bool {
        closedRoomIDs.contains(roomID)
    }
}

struct RealtimeRoomRoutingState {
    private(set) var visibleLease: RealtimeVisibleRoomLease?
    private var generation: UInt64 = 0
    private var backgroundHighWatermarks: [String: Int64] = [:]

    mutating func recordBackgroundAcceptance(roomID: String, seq: Int64) {
        guard !roomID.isEmpty, seq > 0 else { return }
        backgroundHighWatermarks[roomID] = max(
            backgroundHighWatermarks[roomID] ?? 0,
            seq
        )
    }

    mutating func acceptBackground(roomID: String, seq: Int64) -> Bool {
        guard !roomID.isEmpty, seq > 0 else { return false }
        guard seq > (backgroundHighWatermarks[roomID] ?? 0) else { return false }
        backgroundHighWatermarks[roomID] = seq
        return true
    }

    mutating func promote(roomID: String, baselineSeq: Int64) -> RealtimeVisibleRoomLease {
        generation &+= 1
        let lease = RealtimeVisibleRoomLease(
            roomID: roomID,
            generation: generation,
            baselineSeq: baselineSeq,
            promotionHighWatermark: max(
                baselineSeq,
                backgroundHighWatermarks[roomID] ?? 0
            )
        )
        visibleLease = lease
        return lease
    }

    @discardableResult
    mutating func end(
        _ lease: RealtimeVisibleRoomLease,
        strictLastReleasedSeq: Int64
    ) -> Bool {
        guard strictLastReleasedSeq >= 0 else { return false }
        guard visibleLease == lease else { return false }
        recordBackgroundAcceptance(
            roomID: lease.roomID,
            seq: strictLastReleasedSeq
        )
        visibleLease = nil
        return true
    }

    func route(for roomID: String) -> RealtimeRoomIngressRoute {
        guard let visibleLease, visibleLease.roomID == roomID else {
            return .background
        }
        return .visible(visibleLease)
    }

    func backgroundHighWatermark(for roomID: String) -> Int64 {
        backgroundHighWatermarks[roomID] ?? 0
    }

    mutating func removeRoom(_ roomID: String) {
        backgroundHighWatermarks.removeValue(forKey: roomID)
        if visibleLease?.roomID == roomID {
            visibleLease = nil
        }
    }

    mutating func reset() {
        visibleLease = nil
        backgroundHighWatermarks.removeAll(keepingCapacity: false)
    }
}

struct RealtimeSocketAdmissionState {
    private struct RoomState {
        var messageIDs = Set<String>()
        var messageIDOrder: [String] = []
    }

    private let capacityPerRoom: Int
    private var rooms: [String: RoomState] = [:]

    init(capacityPerRoom: Int = 300) {
        self.capacityPerRoom = max(1, capacityPerRoom)
    }

    mutating func admit(_ message: ChatMessage) -> Bool {
        guard message.seq > 0 else { return true }
        guard !message.roomID.isEmpty, !message.ID.isEmpty else { return false }

        var room = rooms[message.roomID] ?? RoomState()
        guard room.messageIDs.insert(message.ID).inserted else { return false }
        room.messageIDOrder.append(message.ID)

        if room.messageIDOrder.count > capacityPerRoom {
            let oldestID = room.messageIDOrder.removeFirst()
            room.messageIDs.remove(oldestID)
        }

        rooms[message.roomID] = room
        return true
    }

    mutating func removeRoom(_ roomID: String) {
        rooms.removeValue(forKey: roomID)
    }

    mutating func reset() {
        rooms.removeAll(keepingCapacity: false)
    }
}

actor ChatRoomSessionActor {
    struct Consumer: Sendable {
        let id: UUID
        let stream: AsyncStream<ChatMessage>
    }

    private let roomID: String
    private let recentMessageCapacity: Int
    private var continuations: [UUID: AsyncStream<ChatMessage>.Continuation] = [:]
    private var recentMessageIDs = Set<String>()
    private var recentMessageOrder: [String] = []
    private var recentSeqByMessageID: [String: Int64] = [:]

    init(roomID: String, recentMessageCapacity: Int = 300) {
        self.roomID = roomID
        self.recentMessageCapacity = max(1, recentMessageCapacity)
    }

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
        let isEmpty = continuations.isEmpty
        if isEmpty {
            removeRecentMessages()
        }
        return isEmpty
    }

    func publishIncoming(_ message: ChatMessage) {
        if recentMessageIDs.contains(message.ID) {
            let previousSeq = recentSeqByMessageID[message.ID] ?? message.seq
            #if DEBUG
            if previousSeq != message.seq {
                print(
                    "[ChatRoomSessionActor] duplicate seq mismatch " +
                    "roomID=\(roomID) messageID=\(message.ID) " +
                    "previousSeq=\(previousSeq) incomingSeq=\(message.seq)"
                )
            }
            #endif
            return
        }

        recentMessageIDs.insert(message.ID)
        recentMessageOrder.append(message.ID)
        recentSeqByMessageID[message.ID] = message.seq

        if recentMessageOrder.count > recentMessageCapacity {
            let oldestMessageID = recentMessageOrder.removeFirst()
            recentMessageIDs.remove(oldestMessageID)
            recentSeqByMessageID.removeValue(forKey: oldestMessageID)
        }

        yield(message)
    }

    func publishLocal(_ message: ChatMessage) {
        yield(message)
    }

    private func yield(_ message: ChatMessage) {
        for continuation in continuations.values {
            continuation.yield(message)
        }
    }

    func finishAll() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
        removeRecentMessages()
    }

    private func removeRecentMessages() {
        recentMessageIDs.removeAll(keepingCapacity: false)
        recentMessageOrder.removeAll(keepingCapacity: false)
        recentSeqByMessageID.removeAll(keepingCapacity: false)
    }

    nonisolated private static func makeStream() -> (AsyncStream<ChatMessage>, AsyncStream<ChatMessage>.Continuation) {
        var continuation: AsyncStream<ChatMessage>.Continuation!
        let stream = AsyncStream<ChatMessage> { continuation = $0 }
        return (stream, continuation)
    }
}

actor RealtimeSocketService {
    static let shared = RealtimeSocketService(
        gapRecoveryLoader: UnavailableChatRealtimeGapRecoveryLoader()
    )

    enum SocketError: Error {
        case connectionFailed([Any])
        case invalidRoomID
        case invalidBaselineSeq
    }

    private struct ReconnectPolicy {
        var maxAttempts: Int
        var baseDelay: TimeInterval
        var maxDelay: TimeInterval
        var jitter: Double
    }

    private struct VisibleStrictSession {
        let lease: RealtimeVisibleRoomLease
        let actor: ChatRoomStrictSessionActor
    }

    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "outpick.socket.pathmonitor")

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var listenerBinder: RealtimeSocketListenerBinder?
    private var messageIngressQueue: RealtimeSocketMessageIngressQueue?
    private var messageIngressTask: Task<Void, Never>?
    private var identity: SocketSessionIdentity?
    private var socketGeneration: UInt64 = 0

    private var clientPolicy = ReconnectPolicy(maxAttempts: 5, baseDelay: 0.5, maxDelay: 8.0, jitter: 0.3)
    private var serverPolicy: ReconnectPolicy?
    private var allowReconnect = true
    private var reconnectState = RealtimeSocketReconnectState()

    private var connectWaiters: [CheckedContinuation<Void, Error>] = []

    private var joinedRooms = Set<String>()
    private var pendingRooms: Set<String> = []
    private var pendingCreatedRooms = Set<String>()
    private var roomJoinState = RealtimeRoomJoinState()
    private var roomJoinWaiters = [String: [CheckedContinuation<Void, Error>]]()
    private var creatingRooms = Set<String>()

    private var backgroundSessionActors = [String: ChatRoomSessionActor]()
    private var visibleStrictSession: VisibleStrictSession?
    private var admissionState = RealtimeSocketAdmissionState()
    private var routingState = RealtimeRoomRoutingState()
    private let gapRecoveryLoader: ChatRealtimeGapRecoveryLoading
    private let orderingClock: RealtimeOrderingClock
    private let reconnectIdentityRefresher: @Sendable (SocketSessionIdentity) async throws -> SocketSessionIdentity
    private struct RoomClosedObserver {
        let roomID: String
        let continuation: AsyncStream<String>.Continuation
    }

    private var roomClosedObservers = [UUID: RoomClosedObserver]()
    private var authoritativeRoomClosureState = RealtimeAuthoritativeRoomClosureState()

    #if DEBUG
    private let debugQAConfiguration = SocketDebugQAConfiguration()
    private var debugAckLossArmedMessageKeys = Set<String>()
    #endif

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let productionSocketURL = URL(string: "https://outpick-socket-2w7zhxurhq-du.a.run.app")!

    init(
        gapRecoveryLoader: ChatRealtimeGapRecoveryLoading,
        orderingClock: RealtimeOrderingClock = LiveRealtimeOrderingClock(),
        reconnectIdentityRefresher: @escaping @Sendable (SocketSessionIdentity) async throws -> SocketSessionIdentity = {
            try await SocketSessionIdentity.refreshingIDToken(for: $0)
        }
    ) {
        self.gapRecoveryLoader = gapRecoveryLoader
        self.orderingClock = orderingClock
        self.reconnectIdentityRefresher = reconnectIdentityRefresher
        startPathMonitor()
    }

    nonisolated static func makeSocketURL() -> URL {
        #if DEBUG
        return SocketDebugQAConfiguration().socketURL(productionURL: productionSocketURL)
        #else
        productionSocketURL
        #endif
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
        reconnectState.cancelReconnect()
        invalidateRoomJoinState(
            error: Self.makeSocketError(code: -1009, message: "소켓 연결이 종료됐습니다.")
        )
        tearDownRoomStreams()
        admissionState.reset()
        routingState.reset()
        failConnectWaiters(with: SocketError.connectionFailed(["manual disconnect"]))
        socket?.disconnect()
    }

    func suspendForBackground() async {
        allowReconnect = false
        reconnectState.cancelReconnect()
        failConnectWaiters(with: SocketError.connectionFailed(["background disconnect"]))
        await suspendVisibleStrictSession()
        pendingRooms.formUnion(joinedRooms)
        invalidateRoomJoinState(
            error: Self.makeSocketError(code: -1009, message: "백그라운드 진입으로 방 연결이 중단됐습니다.")
        )
        creatingRooms.removeAll()
        guard socket?.status == .connected || socket?.status == .connecting else { return }
        print("백그라운드 진입으로 소켓 연결 해제")
        socket?.disconnect()
    }

    func resetMembership() {
        joinedRooms.removeAll()
        pendingRooms.removeAll()
        pendingCreatedRooms.removeAll()
        invalidateRoomJoinState(
            error: Self.makeSocketError(code: -1009, message: "방 연결 상태가 초기화됐습니다.")
        )
        creatingRooms.removeAll()
        admissionState.reset()
        routingState.reset()
    }

    func openBackgroundRoomSession(for roomID: String) async throws -> ChatRoomSocketSession {
        guard !roomID.isEmpty else { throw SocketError.invalidRoomID }

        let sessionActor = backgroundSessionActor(for: roomID)
        let consumer = await sessionActor.addConsumer()

        do {
            if socket?.status != .connected {
                let resolvedIdentity: SocketSessionIdentity
                if let identity {
                    resolvedIdentity = identity
                } else {
                    resolvedIdentity = try await SocketSessionIdentity.current()
                }
                try await connect(identity: resolvedIdentity)
            }

            try await joinRoomAwaitingAck(roomID)
        } catch {
            await closeBackgroundRoomSession(roomID: roomID, consumerID: consumer.id)
            throw error
        }

        return ChatRoomSocketSession(
            roomID: roomID,
            messages: consumer.stream,
            close: { [weak self] in
                await self?.closeBackgroundRoomSession(
                    roomID: roomID,
                    consumerID: consumer.id
                )
            }
        )
    }

    func openVisibleRoomSession(
        for roomID: String,
        baselineSeq: Int64
    ) async throws -> ChatRoomSocketSession {
        guard !roomID.isEmpty else { throw SocketError.invalidRoomID }
        guard baselineSeq >= 0 else { throw SocketError.invalidBaselineSeq }

        if socket?.status != .connected {
            let resolvedIdentity: SocketSessionIdentity
            if let identity {
                resolvedIdentity = identity
            } else {
                resolvedIdentity = try await SocketSessionIdentity.current()
            }
            try await connect(identity: resolvedIdentity)
        }

        try await joinRoomAwaitingAck(roomID)

        let previousSession = visibleStrictSession
        let lease = routingState.promote(roomID: roomID, baselineSeq: baselineSeq)
        let strictActor = ChatRoomStrictSessionActor(
            roomID: roomID,
            baselineSeq: baselineSeq,
            promotionHighWatermark: lease.promotionHighWatermark,
            recoveryLoader: gapRecoveryLoader,
            clock: orderingClock
        )
        visibleStrictSession = VisibleStrictSession(lease: lease, actor: strictActor)

        if let previousSession {
            await previousSession.actor.finish()
        }
        await strictActor.start()

        return ChatRoomSocketSession(
            roomID: roomID,
            messages: strictActor.messages,
            close: { [weak self] in
                await self?.closeVisibleRoomSession(lease: lease)
            }
        )
    }

    private func closeBackgroundRoomSession(roomID: String, consumerID: UUID) async {
        guard let sessionActor = backgroundSessionActors[roomID] else { return }

        let isEmpty = await sessionActor.removeConsumer(consumerID)
        if isEmpty {
            backgroundSessionActors.removeValue(forKey: roomID)
        }
    }

    private func closeVisibleRoomSession(lease: RealtimeVisibleRoomLease) async {
        guard let session = visibleStrictSession, session.lease == lease else { return }
        let lastReleasedSeq = await session.actor.currentLastReleasedSeq()
        guard let currentSession = visibleStrictSession,
              currentSession.lease == lease else { return }

        guard routingState.end(
            lease,
            strictLastReleasedSeq: lastReleasedSeq
        ) else { return }
        visibleStrictSession = nil
        await currentSession.actor.finish()
    }

    func createRoom(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        authoritativeRoomClosureState.markCreated(roomID)
        pendingCreatedRooms.insert(roomID)
        emitCreateRoomIfNeeded(roomID)
    }

    func joinRoom(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        guard !authoritativeRoomClosureState.isClosed(roomID) else {
            publishRoomClosed(roomID)
            return
        }
        joinedRooms.insert(roomID)
        emitJoinRoomIfNeeded(roomID)
    }

    func leaveRoom(_ roomID: String) async {
        guard !roomID.isEmpty else { return }
        await removeRealtimeRoomState(roomID)

        guard socket?.status == .connected else { return }
        socket?.emit("leave room", roomID)
    }

    private func removeRealtimeRoomState(_ roomID: String) async {
        joinedRooms.remove(roomID)
        pendingRooms.remove(roomID)
        pendingCreatedRooms.remove(roomID)
        roomJoinState.removeRoom(roomID)
        failRoomJoinWaiters(
            roomID: roomID,
            error: Self.makeSocketError(code: -1009, message: "방 연결이 종료됐습니다.")
        )
        admissionState.removeRoom(roomID)
        routingState.removeRoom(roomID)
        if let backgroundActor = backgroundSessionActors.removeValue(forKey: roomID) {
            await backgroundActor.finishAll()
        }
        if visibleStrictSession?.lease.roomID == roomID {
            let session = visibleStrictSession
            visibleStrictSession = nil
            await session?.actor.finish()
        }
    }

    func observeRoomClosed(roomID: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            guard !roomID.isEmpty else {
                continuation.finish()
                return
            }
            let id = UUID()
            roomClosedObservers[id] = RoomClosedObserver(
                roomID: roomID,
                continuation: continuation
            )
            if authoritativeRoomClosureState.isClosed(roomID) {
                continuation.yield(roomID)
            }

            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeRoomClosedContinuation(id)
                }
            }
        }
    }

    func sendMessage(
        _ room: ChatRoom,
        _ message: ChatMessage,
        ackTimeout: Double = 5.0
    ) async throws -> ChatMessageSendReceipt {
        guard let socket, socket.status == .connected else {
            throw makeSocketError(code: -1009, message: "소켓이 연결되어 있지 않습니다.")
        }

        let payload = message.toSocketRepresentation()
        let shouldDropSuccessfulAck = armDebugAckLossIfNeeded(kind: "text", messageID: message.ID)

        return try await withCheckedThrowingContinuation { continuation in
            socket.emitWithAck("chat message", payload).timingOut(after: ackTimeout) { ackResponse in
                if let receipt = ChatMessageEmitAckMapper.receipt(
                    from: ackResponse,
                    roomID: room.id,
                    fallbackMessageID: message.ID
                ) {
                    if shouldDropSuccessfulAck {
                        #if DEBUG
                        print("[SocketDebugQA] 성공 ACK를 결과 불명으로 처리 kind=text messageID=\(message.ID)")
                        #endif
                        continuation.resume(
                            throwing: Self.makeSocketError(
                                code: -1001,
                                message: "DEBUG QA: 서버 성공 ACK 유실을 재현했습니다."
                            )
                        )
                        return
                    }
                    continuation.resume(returning: receipt)
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
            "senderUID": identity?.uid ?? "",
            "senderEmail": identity?.email ?? ""
        ]

        try await emitAck(event: "chat:mediaPreflight", body, timeout: ackTimeout, failureMessage: "미디어 업로드 사전 확인 실패 또는 timeout")
    }

    func sendImagesAwaitingAck(
        _ room: ChatRoom,
        _ attachments: [[String: Any]],
        senderAvatarPath: String? = nil,
        clientMessageID: String? = nil,
        ackTimeout: Double = 15.0
    ) async throws -> ChatMessageSendReceipt {
        guard !attachments.isEmpty else {
            throw makeSocketError(code: -2, message: "이미지 attachment가 비어 있습니다.")
        }
        guard let socket, socket.status == .connected else {
            throw makeSocketError(code: -1009, message: "소켓이 연결되어 있지 않습니다.")
        }

        let roomID = room.id
        let senderUID = identity?.uid ?? ""
        let senderEmail = identity?.email ?? ""
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
            "senderUID": senderUID,
            "senderEmail": senderEmail,
            "senderNickname": senderNickname,
            "sentAt": isoSentAt
        ]
        if let avatar = senderAvatarPath ?? identity?.avatarPath, !avatar.isEmpty {
            body["senderAvatarPath"] = avatar
        }
        let shouldDropSuccessfulAck = armDebugAckLossIfNeeded(
            kind: "images",
            messageID: resolvedClientMessageID
        )

        return try await withCheckedThrowingContinuation { continuation in
            socket.emitWithAck("chat:mediaFinalize", body).timingOut(after: ackTimeout) { ackResponse in
                if let receipt = ChatMessageEmitAckMapper.receipt(
                    from: ackResponse,
                    roomID: roomID,
                    fallbackMessageID: resolvedClientMessageID
                ) {
                    if shouldDropSuccessfulAck {
                        #if DEBUG
                        print("[SocketDebugQA] 성공 ACK를 결과 불명으로 처리 kind=images messageID=\(resolvedClientMessageID)")
                        #endif
                        continuation.resume(
                            throwing: Self.makeSocketError(
                                code: -1001,
                                message: "DEBUG QA: 서버 성공 ACK 유실을 재현했습니다."
                            )
                        )
                        return
                    }
                    continuation.resume(returning: receipt)
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
    ) async throws -> ChatMessageSendReceipt {
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
            "senderUID": identity?.uid ?? "",
            "senderEmail": identity?.email ?? "",
            "senderNickname": identity?.nickname ?? "",
            "kind": "video"
        ]
        if let avatar = senderAvatarPath ?? identity?.avatarPath, !avatar.isEmpty {
            dict["senderAvatarPath"] = avatar
        }
        let shouldDropSuccessfulAck = armDebugAckLossIfNeeded(
            kind: "video",
            messageID: payload.messageID
        )

        return try await withCheckedThrowingContinuation { continuation in
            socket.emitWithAck("chat:mediaFinalize", dict).timingOut(after: ackTimeout) { items in
                if let receipt = ChatMessageEmitAckMapper.receipt(
                    from: items,
                    roomID: roomID,
                    fallbackMessageID: payload.messageID
                ) {
                    if shouldDropSuccessfulAck {
                        #if DEBUG
                        print("[SocketDebugQA] 성공 ACK를 결과 불명으로 처리 kind=video messageID=\(payload.messageID)")
                        #endif
                        continuation.resume(
                            throwing: Self.makeSocketError(
                                code: -1001,
                                message: "DEBUG QA: 서버 성공 ACK 유실을 재현했습니다."
                            )
                        )
                        return
                    }
                    continuation.resume(returning: receipt)
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
        messageID: String,
        sharedContent: LookbookSharedContent,
        messageText: String? = nil,
        ackTimeout: Double = 5.0
    ) async throws -> LookbookChatShareSendResult {
        let trimmedRoomID = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRoomID.isEmpty else { throw LookbookChatShareError.invalidRoomID }
        let trimmedMessageID = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessageID.isEmpty else { throw LookbookChatShareError.server("invalid_message_id") }
        guard sharedContent.isValid else { throw LookbookChatShareError.invalidSharedContent }
        guard let socket, socket.status == .connected else { throw LookbookChatShareError.socketDisconnected }

        let now = Date()
        let trimmedMessageText = (messageText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var payload: [String: Any] = [
            "ID": trimmedMessageID,
            "messageID": trimmedMessageID,
            "roomID": trimmedRoomID,
            "messageType": ChatMessageType.lookbookShare.rawValue,
            "msg": trimmedMessageText,
            "sentAt": Self.isoFormatter.string(from: now),
            "senderUID": identity?.uid ?? "",
            "senderEmail": identity?.email ?? "",
            "senderNickname": identity?.nickname ?? "",
            "attachments": [],
            "sharedContent": sharedContent.toDict()
        ]
        if let avatar = identity?.avatarPath,
           !avatar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["senderAvatarPath"] = avatar
        }
        let shouldDropSuccessfulAck = armDebugAckLossIfNeeded(
            kind: "lookbook",
            messageID: trimmedMessageID
        )

        return try await withCheckedThrowingContinuation { continuation in
            socket.emitWithAck("chat:lookbookShare", payload).timingOut(after: ackTimeout) { ackResponse in
                do {
                    let result = try LookbookChatShareAckMapper.parse(
                        ackResponse,
                        roomID: trimmedRoomID,
                        fallbackMessageID: trimmedMessageID
                    )
                    if shouldDropSuccessfulAck {
                        #if DEBUG
                        print("[SocketDebugQA] 성공 ACK를 결과 불명으로 처리 kind=lookbook messageID=\(trimmedMessageID)")
                        #endif
                        continuation.resume(
                            throwing: Self.makeSocketError(
                                code: -1001,
                                message: "DEBUG QA: 서버 성공 ACK 유실을 재현했습니다."
                            )
                        )
                        return
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
        senderUID: String,
        senderEmail: String?,
        senderNickname: String,
        localURL: URL,
        thumbData: Data?,
        duration: Double,
        width: Int,
        height: Int,
        presetCode: String
    ) async {
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
            senderUID: senderUID,
            senderEmail: senderEmail,
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

        await emitToRoomPipeline(message, source: .local)
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

    private func replaceSocket(
        identity newIdentity: SocketSessionIdentity,
        cancelReconnectState: Bool = true
    ) {
        let didChangeUser = identity.map { $0.uid != newIdentity.uid } ?? false
        socketGeneration &+= 1
        if cancelReconnectState {
            reconnectState.cancelReconnect()
        }
        let generation = socketGeneration
        invalidateRoomJoinState(
            error: Self.makeSocketError(code: -1009, message: "소켓 client가 교체됐습니다.")
        )
        if didChangeUser {
            tearDownRoomStreams()
            admissionState.reset()
            routingState.reset()
        }

        stopMessageIngress()
        manager?.disconnect()
        manager = nil
        socket = nil
        listenerBinder = nil
        identity = newIdentity

        let manager = SocketManager(socketURL: newIdentity.socketURL, config: [
            .compress,
            .secure(true),
            .forceWebsockets(true),
            .forcePolling(false),
            .forceNew(true),
            .connectParams(newIdentity.connectParams),
            .extraHeaders(newIdentity.extraHeaders),
            .reconnects(false)
        ])
        let socket = manager.defaultSocket
        self.manager = manager
        self.socket = socket
        let ingressQueue = RealtimeSocketMessageIngressQueue()
        messageIngressQueue = ingressQueue
        messageIngressTask = Task { [weak self] in
            for await ingressEvent in ingressQueue.stream {
                guard !Task.isCancelled else { break }
                await self?.handleIncomingData(
                    ingressEvent.data,
                    event: ingressEvent.event
                )
            }
        }
        bindSocketListenersOnce(
            socket: socket,
            generation: generation,
            messageIngressQueue: ingressQueue
        )
    }

    private func armDebugAckLossIfNeeded(kind: String, messageID: String) -> Bool {
        #if DEBUG
        guard debugQAConfiguration.shouldDropFirstMessageAck(kind: kind) else { return false }
        return debugAckLossArmedMessageKeys.insert("\(kind)::\(messageID)").inserted
        #else
        return false
        #endif
    }

    private func bindSocketListenersOnce(
        socket: SocketIOClient,
        generation: UInt64,
        messageIngressQueue: RealtimeSocketMessageIngressQueue
    ) {
        let binder = RealtimeSocketListenerBinder()
        let listener = SocketIOEventListenerAdapter(socket: socket)
        binder.bind(
            to: listener,
            callbacks: RealtimeSocketListenerCallbacks(
                connected: { [weak self] _ in
                    Task { await self?.handleConnected(generation: generation) }
                },
                error: { [weak self] data in
                    Task { await self?.handleSocketError(data, generation: generation) }
                },
                disconnected: { [weak self] data in
                    Task { await self?.handleSocketDisconnect(data, generation: generation) }
                },
                serverConnectReady: { [weak self] data in
                    Task { await self?.handleServerConnectReady(data, generation: generation) }
                },
                chatMessage: { [weak messageIngressQueue] data in
                    messageIngressQueue?.enqueue(
                        data: data,
                        event: RealtimeSocketListenerBinder.chatMessageEvent
                    )
                },
                imagesReceived: { [weak messageIngressQueue] data in
                    messageIngressQueue?.enqueue(
                        data: data,
                        event: RealtimeSocketListenerBinder.imagesReceivedEvent
                    )
                },
                videoReceived: { [weak messageIngressQueue] data in
                    messageIngressQueue?.enqueue(
                        data: data,
                        event: RealtimeSocketListenerBinder.videoReceivedEvent
                    )
                },
                roomClosed: { [weak self] data in
                    Task {
                        guard await self?.isCurrentSocketGeneration(generation) == true else { return }
                        await self?.handleRoomClosedData(data)
                    }
                }
            )
        )
        listenerBinder = binder
    }

    private func handleConnected(generation: UInt64) {
        guard generation == socketGeneration else { return }
        print("Socket Connected")
        reconnectState.markConnected()
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

    private func handleSocketError(_ data: [Any], generation: UInt64) {
        guard generation == socketGeneration else { return }
        print("소켓 에러:", data)
        failConnectWaiters(with: SocketError.connectionFailed(data))
        reconnectState.invalidateConnectWatchdog()
        reconnectState.requestReconnect()
        scheduleManualRetryIfNeeded()
    }

    private func handleSocketDisconnect(_ data: [Any], generation: UInt64) async {
        guard generation == socketGeneration else { return }
        print("소켓 디스커넥트:", data)
        await suspendVisibleStrictSession()
        pendingRooms.formUnion(joinedRooms)
        invalidateRoomJoinState(error: SocketError.connectionFailed(data))
        creatingRooms.removeAll()
        if !connectWaiters.isEmpty {
            failConnectWaiters(with: SocketError.connectionFailed(data))
        }
        reconnectState.invalidateConnectWatchdog()
        reconnectState.requestReconnect()
        scheduleManualRetryIfNeeded()
    }

    private func handleServerConnectReady(_ data: [Any], generation: UInt64) {
        guard generation == socketGeneration else { return }
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

    private func handleRoomClosedData(_ data: [Any]) async {
        guard
            let dict = data.first as? [String: Any],
            let closedRoomID = dict["roomID"] as? String
        else { return }
        await handleAuthoritativeRoomClosure(closedRoomID)
    }

    private func handleAuthoritativeRoomClosure(_ roomID: String) async {
        authoritativeRoomClosureState.markClosed(roomID)
        await removeRealtimeRoomState(roomID)
        publishRoomClosed(roomID)
    }

    private func publishRoomClosed(_ roomID: String) {
        for observer in roomClosedObservers.values where observer.roomID == roomID {
            observer.continuation.yield(roomID)
        }
    }

    private func removeRoomClosedContinuation(_ id: UUID) {
        roomClosedObservers[id]?.continuation.finish()
        roomClosedObservers.removeValue(forKey: id)
    }

    private func handleIncomingData(_ data: [Any], event: String) async {
        guard let payload = data.first as? [String: Any] else { return }
        await handleIncomingPayload(payload, event: event)
    }

    private func handleIncomingPayload(_ payload: [String: Any], event: String) async {
        let normalized = normalizeIncomingPayload(payload, event: event)
        guard let message = ChatMessage.from(normalized) else {
            #if DEBUG
            print("[RealtimeSocketService] failed to parse \(event):", normalized)
            #endif
            return
        }
        await emitToRoomPipeline(message, source: .socketIngress)
    }

    private enum RoomPipelineSource {
        case socketIngress
        case local
    }

    private func emitToRoomPipeline(
        _ message: ChatMessage,
        source: RoomPipelineSource
    ) async {
        let roomID = message.roomID
        guard !roomID.isEmpty else { return }
        let route = routingState.route(for: roomID)
        let hasTarget: Bool
        switch route {
        case .background:
            hasTarget = backgroundSessionActors[roomID] != nil
        case .visible(let lease):
            hasTarget = visibleStrictSession?.lease == lease
        }
        guard hasTarget else {
            #if DEBUG
            print("[RealtimeSocketService] dropped incoming message without room session roomID=\(roomID) messageID=\(message.ID) seq=\(message.seq)")
            #endif
            return
        }

        switch source {
        case .socketIngress:
            guard admissionState.admit(message) else { return }
            switch route {
            case .background:
                guard routingState.acceptBackground(
                    roomID: roomID,
                    seq: message.seq
                ) else { return }
                guard let backgroundActor = backgroundSessionActors[roomID] else { return }
                await backgroundActor.publishIncoming(message)
            case .visible(let lease):
                guard let strictSession = visibleStrictSession,
                      strictSession.lease == lease else { return }
                await strictSession.actor.receive(message)

                // visible 방도 방 목록 preview/read metadata는 계속 갱신해야 한다.
                // background actor는 느슨한 high-watermark만 적용하고 BannerManager가 UI 표시만 억제한다.
                if routingState.acceptBackground(roomID: roomID, seq: message.seq),
                   let backgroundActor = backgroundSessionActors[roomID] {
                    await backgroundActor.publishIncoming(message)
                }
            }
        case .local:
            if case .visible(let lease) = route,
               let strictSession = visibleStrictSession,
               strictSession.lease == lease {
                await strictSession.actor.publishLocal(message)
                if let backgroundActor = backgroundSessionActors[roomID] {
                    await backgroundActor.publishLocal(message)
                }
            } else if let backgroundActor = backgroundSessionActors[roomID] {
                await backgroundActor.publishLocal(message)
            }
        }
    }

    private func backgroundSessionActor(for roomID: String) -> ChatRoomSessionActor {
        if let actor = backgroundSessionActors[roomID] {
            return actor
        }

        let actor = ChatRoomSessionActor(roomID: roomID)
        backgroundSessionActors[roomID] = actor
        return actor
    }

    private func tearDownRoomStreams() {
        let actors = Array(backgroundSessionActors.values)
        backgroundSessionActors.removeAll()
        let strictSession = visibleStrictSession
        visibleStrictSession = nil
        actors.forEach { actor in
            Task {
                await actor.finishAll()
            }
        }
        if let strictSession {
            Task {
                await strictSession.actor.finish()
            }
        }
    }

    private func stopMessageIngress() {
        messageIngressQueue?.finish()
        messageIngressQueue = nil
        messageIngressTask?.cancel()
        messageIngressTask = nil
    }

    private func emitJoinRoomIfNeeded(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        guard joinedRooms.contains(roomID) else { return }
        if roomJoinState.isConfirmed(roomID) {
            pendingRooms.remove(roomID)
            resumeRoomJoinWaiters(roomID: roomID)
            return
        }
        guard let socket, socket.status == .connected else {
            pendingRooms.insert(roomID)
            return
        }
        let attemptID: UUID
        switch roomJoinState.begin(roomID: roomID) {
        case .alreadyJoined:
            pendingRooms.remove(roomID)
            resumeRoomJoinWaiters(roomID: roomID)
            return
        case .inFlight:
            return
        case .started(let startedAttemptID):
            attemptID = startedAttemptID
        }
        socket.emitWithAck("join room", roomID).timingOut(after: 5) { [weak self] ackResponse in
            Task {
                await self?.handleJoinAck(
                    roomID: roomID,
                    attemptID: attemptID,
                    ackResponse: ackResponse
                )
            }
        }
    }

    private func handleJoinAck(
        roomID: String,
        attemptID: UUID,
        ackResponse: [Any]
    ) async {
        let succeeded = ChatMessageEmitAckMapper.isSuccess(ackResponse)
        guard roomJoinState.resolve(
            roomID: roomID,
            attemptID: attemptID,
            succeeded: succeeded
        ) else { return }

        if succeeded {
            pendingRooms.remove(roomID)
            resumeRoomJoinWaiters(roomID: roomID)
            if let strictSession = visibleStrictSession,
               strictSession.lease.roomID == roomID {
                await strictSession.actor.resumeAfterRejoin()
            }
        } else {
            if RealtimeRoomJoinAckMapper.isRoomNotFound(ackResponse) {
                // room:closed broadcast가 transport 경계에서 유실되더라도,
                // 서버의 권위 있는 join 거절을 동일한 종료 신호로 승격한다.
                await handleAuthoritativeRoomClosure(roomID)
                return
            }
            pendingRooms.insert(roomID)
            failRoomJoinWaiters(
                roomID: roomID,
                error: Self.makeRoomJoinError(roomID: roomID, ackResponse: ackResponse)
            )
            print("join room 실패:", roomID, ackResponse)
        }
    }

    private func joinRoomAwaitingAck(_ roomID: String) async throws {
        guard !roomID.isEmpty else { throw SocketError.invalidRoomID }
        guard !authoritativeRoomClosureState.isClosed(roomID) else {
            publishRoomClosed(roomID)
            throw Self.makeSocketError(
                code: -1003,
                message: "이미 종료된 채팅방입니다."
            )
        }
        joinedRooms.insert(roomID)

        if roomJoinState.isConfirmed(roomID) {
            return
        }

        guard socket?.status == .connected else {
            pendingRooms.insert(roomID)
            throw makeSocketError(code: -1009, message: "소켓이 연결되어 있지 않습니다.")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            roomJoinWaiters[roomID, default: []].append(continuation)
            emitJoinRoomIfNeeded(roomID)
        }
    }

    private func invalidateRoomJoinState(error: Error) {
        roomJoinState.invalidateMembership()
        let waiters = roomJoinWaiters
        roomJoinWaiters.removeAll()
        waiters.values.flatMap { $0 }.forEach { $0.resume(throwing: error) }
    }

    private func resumeRoomJoinWaiters(roomID: String) {
        let waiters = roomJoinWaiters.removeValue(forKey: roomID) ?? []
        waiters.forEach { $0.resume() }
    }

    private func failRoomJoinWaiters(roomID: String, error: Error) {
        let waiters = roomJoinWaiters.removeValue(forKey: roomID) ?? []
        waiters.forEach { $0.resume(throwing: error) }
    }

    private static func makeRoomJoinError(roomID: String, ackResponse: [Any]) -> NSError {
        let isTimeout = ackResponse.contains { value in
            (value as? String)?.uppercased() == "NO ACK"
        }
        return makeSocketError(
            code: isTimeout ? -1001 : -1003,
            message: "join room 실패(\(roomID)): \(ackResponse)"
        )
    }

    private func suspendVisibleStrictSession() async {
        guard let strictSession = visibleStrictSession else { return }
        await strictSession.actor.suspend()
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

    private func isCurrentSocketGeneration(_ generation: UInt64) -> Bool {
        generation == socketGeneration
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
        guard reconnectState.needsReconnect else { return }
        guard reconnectState.isNetworkAvailable else {
            #if DEBUG
            print("[retry] waiting for network...")
            #endif
            scheduleNetworkAvailabilityProbeIfNeeded()
            return
        }
        guard let identity else { return }

        guard let attempt = reconnectState.scheduleIfPossible(
            isAllowed: allowReconnect,
            maxAttempts: effectivePolicy.maxAttempts
        ) else { return }
        let delay = backoffDelay(for: attempt.number)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task {
                guard let self else { return }
                await self.performScheduledReconnect(
                    attemptID: attempt.id,
                    identity: identity
                )
            }
        }
    }

    func performScheduledReconnect(
        attemptID: UUID,
        identity: SocketSessionIdentity
    ) async {
        guard reconnectState.consumeScheduledAttempt(id: attemptID) else { return }
        guard allowReconnect else { return }
        await beginReconnectAttempt(identity: identity)
    }

    func handleNetworkPathUpdate(isAvailable: Bool) {
        #if DEBUG
        print("[retry] network path available=\(isAvailable)")
        #endif
        reconnectState.updateNetworkAvailability(isAvailable)
        scheduleManualRetryIfNeeded()
    }

    func scheduleNetworkAvailabilityProbeIfNeeded() {
        guard let probe = reconnectState.scheduleNetworkProbeIfPossible(
            isAllowed: allowReconnect
        ) else { return }

        let delay = min(8.0, pow(2.0, Double(max(0, probe.number - 1))))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task {
                await self?.performNetworkAvailabilityProbe(probeID: probe.id)
            }
        }
    }

    func performNetworkAvailabilityProbe(probeID: UUID) async {
        guard reconnectState.consumeScheduledNetworkProbe(id: probeID) else { return }
        let isAvailable = pathMonitor.currentPath.status == .satisfied
        reconnectState.updateNetworkAvailability(isAvailable)

        if isAvailable {
            scheduleManualRetryIfNeeded()
            return
        }

        guard allowReconnect, let identity else { return }
        #if DEBUG
        print("[retry] probing socket despite unavailable path")
        #endif
        await beginReconnectAttempt(identity: identity)
    }

    func beginReconnectAttempt(identity sourceIdentity: SocketSessionIdentity) async {
        guard allowReconnect, reconnectState.needsReconnect else { return }
        if socket?.status == .connected {
            reconnectState.markConnected()
            return
        }

        let refreshedIdentity: SocketSessionIdentity
        do {
            refreshedIdentity = try await reconnectIdentityRefresher(sourceIdentity)
        } catch {
            #if DEBUG
            print("[retry] Firebase ID Token 갱신 실패:", error.localizedDescription)
            #endif
            reconnectState.requestReconnect()
            scheduleManualRetryIfNeeded()
            return
        }

        guard allowReconnect, reconnectState.needsReconnect else { return }
        guard identity == sourceIdentity else { return }

        // Socket.IO handshake는 manager 생성 당시의 header도 보유하므로,
        // 갱신된 auth payload만 넘기지 않고 client 세대 전체를 교체한다.
        replaceSocket(
            identity: refreshedIdentity,
            cancelReconnectState: false
        )
        guard let socket else { return }

        print("소켓 재연결 시도")
        socket.connect(withPayload: refreshedIdentity.authPayload)
        scheduleReconnectWatchdogIfNeeded()
    }

    func scheduleReconnectWatchdogIfNeeded() {
        guard let watchdogID = reconnectState.scheduleConnectWatchdogIfPossible() else { return }
        // 서버 reconnect 제한은 clientKey 기준 60초당 5회다.
        // path가 실제 연결 가능 상태를 늦게 반영해도 probe가 제한을 스스로 갱신하지 않게 한다.
        let delay = max(15.0, effectivePolicy.maxDelay)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task {
                await self?.handleReconnectWatchdog(watchdogID: watchdogID)
            }
        }
    }

    func handleReconnectWatchdog(watchdogID: UUID) async {
        guard reconnectState.consumeConnectWatchdog(id: watchdogID) else { return }
        guard allowReconnect, socket?.status != .connected else { return }
        guard let identity else { return }

        #if DEBUG
        print("[retry] replacing stalled socket client")
        #endif
        if !connectWaiters.isEmpty {
            failConnectWaiters(
                with: Self.makeSocketError(
                    code: -1001,
                    message: "소켓 재연결 시도가 시간을 초과했습니다."
                )
            )
        }
        // 다음 시도는 토큰을 다시 갱신하고 새 client 세대로 시작한다.
        await beginReconnectAttempt(identity: identity)
    }

    nonisolated func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task {
                await self?.handleNetworkPathUpdate(
                    isAvailable: path.status == .satisfied
                )
            }
        }
        pathMonitor.start(queue: pathQueue)
    }
}
