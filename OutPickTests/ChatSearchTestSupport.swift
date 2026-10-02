import Foundation
import Combine
import Testing
@testable import OutPick

@MainActor final class SearchSessionFixture {
    let database: AppDatabase
    let remote = SearchPageFake()
    let network = SearchNetworkFake()
    let visibility = UserBlockVisibilityStore()
    let validation = SearchValidationFake()
    let fence = ChatSearchDeletionFence()
    let store: SearchStoreSpy
    let local: SearchLocalSpy
    let controller: ChatSearchSessionController
    var emissions: [ChatSearchSessionSnapshot?] = []
    init() throws {
        database = try TemporaryAppDatabase.make()
        store = SearchStoreSpy(base: GRDBChatSearchStore(database: database))
        local = SearchLocalSpy(base: GRDBChatSearchLocalReader(database: database))
        visibility.beginSession(accountID: "account-1", cachedIDs: [])
        controller = ChatSearchSessionController(remote: remote, local: local, store: store,
            visibility: visibility, validation: validation, network: network, deletionFence: fence)
        controller.observe { [weak self] in self?.emissions.append($0) }
    }
    func seed(_ messages: [ChatMessage]) async throws {
        try await GRDBChatMessageStore(database: database, currentAccountID: { "account-1" }).saveChatMessages(messages)
    }
    static func message(_ id: String, _ seq: Int64, text: String = "ㅋㅋ", author: String = "author") -> ChatMessage {
        GRDBTestFixtures.message(id: id, seq: seq, senderUID: author, text: text)
    }
    static func page(_ messages: [ChatMessage], cursor: String = "end", exhausted: Bool = true) -> ChatSearchCandidatePage {
        ChatSearchCandidatePage(candidates: messages, nextCursor: ChatSearchCursor(opaqueValue: Data(cursor.utf8)), isExhausted: exhausted)
    }
    func completed(_ count: Int) async throws {
        try await Self.until { self.controller.snapshot?.count == .completed(totalCount: count) }
    }
    func idle(_ count: Int) async throws {
        try await Self.until { self.controller.snapshot?.count == .scanning(knownCount: count)
            && self.controller.snapshot?.isFetching == false && self.controller.active?.task == nil }
    }
    func continueAfterIdle(_ count: Int) async throws {
        try await idle(count)
        controller.continueSearch(session: try #require(controller.snapshot?.identity))
    }
    static func until(_ predicate: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while !predicate(), ProcessInfo.processInfo.systemUptime < deadline { await Task.yield() }
        guard predicate() else { Issue.record("검색 상태 전이가 제한 시간 안에 완료되지 않음"); throw WaitError.timeout }
    }
    enum WaitError: Error { case timeout }
}

@MainActor final class SearchPageFake: ChatSearchCandidateReading {
    var upper: Int64 = 100
    var upperFailure: ChatSearchFailure?
    var pages: [Result<ChatSearchCandidatePage, ChatSearchFailure>] = []
    var gates: [Int: SearchWriteBarrier] = [:]
    var calls: [(ChatSearchScope, ChatSearchCursor?)] = []
    var upperCalls = 0
    var inFlight = 0
    var maximumInFlight = 0
    func fetchSearchUpperSequence(roomID: String) async throws -> Int64 {
        upperCalls += 1; if let upperFailure { throw upperFailure }; return upper
    }
    func fetchSearchCandidatePage(scope: ChatSearchScope, after: ChatSearchCursor?, limit: Int) async throws -> ChatSearchCandidatePage {
        #expect(limit == 100)
        let index = calls.count; calls.append((scope, after))
        inFlight += 1; maximumInFlight = max(maximumInFlight, inFlight)
        defer { inFlight -= 1 }
        if let gate = gates[index] { await gate.suspend() }
        guard pages.indices.contains(index) else { Issue.record("예상하지 않은 추가 페이지 요청"); throw ChatSearchFailure.malformedData }
        return try pages[index].get()
    }
}

final class SearchNetworkFake: NetworkStatusProviding {
    var online = true
    var currentStatus: NetworkStatus { NetworkStatus(isOnline: online, isExpensive: false, isConstrained: false, accessClass: .wifi, updatedAt: Date()) }
    var statusPublisher: AnyPublisher<NetworkStatus, Never> { Just(currentStatus).eraseToAnyPublisher() }
    func startMonitoring() {}
    func stopMonitoring() {}
}

@MainActor final class SearchValidationFake: ChatSearchValidating {
    var accessCalls = 0
    var deletionCalls = 0
    var accessFailure: ChatSearchFailure?
    var deletionFailure: ChatSearchFailure?
    var accessGate: SearchWriteBarrier?
    func validateAccess(accountID: String, roomID: String) async throws {
        accessCalls += 1
        if let gate = accessGate { accessGate = nil; await gate.suspend() }
        if let accessFailure { throw accessFailure }
    }
    func reconcileDeletion(accountID: String, roomID: String) async throws {
        deletionCalls += 1; if let deletionFailure { throw deletionFailure }
    }
}

@MainActor final class SearchLocalSpy: ChatSearchLocalReading {
    let base: GRDBChatSearchLocalReader
    var opens = 0
    init(base: GRDBChatSearchLocalReader) { self.base = base }
    func openSearchSnapshot(roomID: String) async throws -> any ChatSearchLocalSnapshot {
        opens += 1; return try await base.openSearchSnapshot(roomID: roomID)
    }
}

@MainActor final class SearchStoreSpy: ChatSearchPersisting {
    let base: GRDBChatSearchStore
    var failCommit = false
    var failVisibility = false
    var failState = false
    var beforeCommit: SearchWriteBarrier?
    var afterCommit: SearchWriteBarrier?
    var afterState: SearchWriteBarrier?
    var commits = 0
    var maximumHitPage = 0
    var maximumResultPage = 0
    init(base: GRDBChatSearchStore) { self.base = base }
    func createSession(scope: ChatSearchScope, visibilityRevision: UInt64, blockedAuthorIDs: Set<String>) async throws {
        try await base.createSession(scope: scope, visibilityRevision: visibilityRevision, blockedAuthorIDs: blockedAuthorIDs)
    }
    func commitPage(identity: ChatSearchSessionIdentity, visibilityRevision: UInt64, expectedCursor: ChatSearchCursor?, hits: [ChatSearchResultMetadata], nextCursor: ChatSearchCursor?, isExhausted: Bool) async throws -> ChatSearchStoredState {
        maximumHitPage = max(maximumHitPage, hits.count)
        if let gate = beforeCommit { beforeCommit = nil; await gate.suspend() }
        if failCommit { failCommit = false; throw ChatSearchFailure.localStorage }
        let value = try await base.commitPage(identity: identity, visibilityRevision: visibilityRevision, expectedCursor: expectedCursor, hits: hits, nextCursor: nextCursor, isExhausted: isExhausted)
        commits += 1
        if let gate = afterCommit { afterCommit = nil; await gate.suspend() }
        return value
    }
    func applyVisibility(identity: ChatSearchSessionIdentity, revision: UInt64, blockedAuthorIDs: Set<String>) async throws -> ChatSearchStoredState {
        if failVisibility { throw ChatSearchFailure.localStorage }
        return try await base.applyVisibility(identity: identity, revision: revision, blockedAuthorIDs: blockedAuthorIDs)
    }
    func state(identity: ChatSearchSessionIdentity) async throws -> ChatSearchStoredState {
        if failState { failState = false; throw ChatSearchFailure.localStorage }
        let value = try await base.state(identity: identity)
        if let gate = afterState { afterState = nil; await gate.suspend() }
        return value
    }
    func results(identity: ChatSearchSessionIdentity, offset: Int, limit: Int) async throws -> [ChatSearchResultMetadata] {
        #expect(limit <= 100)
        let result = try await base.results(identity: identity, offset: offset, limit: limit)
        maximumResultPage = max(maximumResultPage, result.count)
        return result
    }
    func ordinal(identity: ChatSearchSessionIdentity, messageID: String) async throws -> Int? { try await base.ordinal(identity: identity, messageID: messageID) }
    func closeSession(identity: ChatSearchSessionIdentity) async throws { try await base.closeSession(identity: identity) }
    func neighbor(identity: ChatSearchSessionIdentity, anchor: ChatSearchResultMetadata, direction: ChatSearchDirection) async throws -> ChatSearchResultMetadata? {
        try await base.neighbor(identity: identity, anchor: anchor, direction: direction)
    }
}
