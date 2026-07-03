//
//  ChatRoomViewModelMessageActionTests.swift
//  OutPickTests
//
//  Created by Codex on 6/17/26.
//

import Combine
import Foundation
import Testing
@testable import OutPick

@MainActor
struct ChatRoomViewModelMessageActionTests {
    @Test func messageActionPolicyUsesCurrentRoomCreator() {
        let viewModel = makeViewModel(
            room: makeRoom(id: "room-1", creatorUID: "admin-uid"),
            currentUserProvider: CurrentUserProviderStub(email: "admin@example.com", canonicalUserID: "admin-uid")
        )
        let message = makeMessage(senderUID: "sender-uid", msg: "공지 후보")

        let policy = viewModel.messageActionPolicy(for: message)

        #expect(policy.canAnnounce)
        #expect(policy.canDelete)
        #expect(policy.canReport == false)
    }

    @Test func performDeleteServerActionDelegatesToMessageUseCase() async throws {
        let messageUseCase = ChatRoomMessageUseCaseSpy()
        let viewModel = makeViewModel(messageUseCase: messageUseCase)
        let message = makeMessage(senderUID: "me@example.com", msg: "삭제할 메시지")

        try await viewModel.performMessageServerAction(.delete, for: message)

        #expect(messageUseCase.deletedMessages.map(\.ID) == ["message-1"])
        #expect(messageUseCase.deletedRooms.map(\.ID) == ["room-1"])
    }

    @Test func performAnnounceServerActionDelegatesToLifecycleUseCase() async throws {
        let lifecycleUseCase = ChatRoomLifecycleUseCaseSpy()
        let viewModel = makeViewModel(lifecycleUseCase: lifecycleUseCase)
        let message = makeMessage(senderUID: "me@example.com", msg: "공지할 메시지")

        try await viewModel.performMessageServerAction(
            .announce(authorID: "관리자"),
            for: message
        )

        let call = try #require(lifecycleUseCase.setAnnouncementCalls.first)
        #expect(call.roomID == "room-1")
        #expect(call.messageID == "message-1")
        #expect(call.payload?.text == "공지할 메시지")
        #expect(call.payload?.authorID == "관리자")
    }

    @Test func persistFinalLastReadSeqMarksSharedReadStateStoreAfterFlush() async throws {
        let lifecycleUseCase = ChatRoomLifecycleUseCaseSpy()
        let readStateStore = ChatRoomReadStateStore()
        let viewModel = makeViewModel(
            lifecycleUseCase: lifecycleUseCase,
            roomReadStateStore: readStateStore
        )
        let message = makeMessage(senderUID: "other@example.com", msg: "새 메시지", seq: 12)

        viewModel.applyVisibleWindowAfterSearchJump([message])
        try await viewModel.persistFinalLastReadSeq(userUID: "user-1")

        let call = try #require(lifecycleUseCase.lastReadSeqCalls.first)
        #expect(call.roomID == "room-1")
        #expect(call.lastReadSeq == 12)
        #expect(readStateStore.snapshot(for: "room-1")?.lastReadSeq == 12)
    }

    @Test func currentUserProviderDrivesParticipantAndAdminChecks() {
        let viewModel = makeViewModel(
            room: makeRoom(id: "room-1", creatorUID: "me-uid"),
            currentUserProvider: CurrentUserProviderStub(email: "me@example.com", canonicalUserID: "me-uid")
        )

        #expect(viewModel.isCurrentUserParticipant)
        #expect(viewModel.isCurrentUser("me-uid"))
        #expect(viewModel.isCurrentUserAdmin(of: viewModel.room))
    }

    @Test func currentUserProviderSuppliesLastReadSeqUserID() async throws {
        let lifecycleUseCase = ChatRoomLifecycleUseCaseSpy()
        let viewModel = makeViewModel(
            lifecycleUseCase: lifecycleUseCase,
            currentUserProvider: CurrentUserProviderStub(canonicalUserID: "document-123")
        )
        let message = makeMessage(senderUID: "other@example.com", msg: "새 메시지", seq: 9)

        viewModel.applyVisibleWindowAfterSearchJump([message])
        try await viewModel.persistFinalLastReadSeqForCurrentUser()

        let call = try #require(lifecycleUseCase.lastReadSeqCalls.first)
        #expect(call.userUID == "document-123")
        #expect(call.lastReadSeq == 9)
    }

    private func makeViewModel(
        room: ChatRoom? = nil,
        messageUseCase: ChatRoomMessageUseCaseProtocol = ChatRoomMessageUseCaseSpy(),
        lifecycleUseCase: ChatRoomLifecycleUseCaseProtocol = ChatRoomLifecycleUseCaseSpy(),
        currentUserProvider: CurrentUserProviding = CurrentUserProviderStub(),
        roomReadStateStore: ChatRoomReadStateStore? = nil
    ) -> ChatRoomViewModel {
        ChatRoomViewModel(
            room: room ?? makeRoom(id: "room-1", creatorUID: "owner@example.com"),
            initialLoadUseCase: ChatInitialLoadUseCaseStub(),
            messageUseCase: messageUseCase,
            searchUseCase: ChatRoomSearchUseCaseStub(),
            lifecycleUseCase: lifecycleUseCase,
            realtimeUseCase: ChatRoomRealtimeUseCaseStub(),
            runtimeUseCase: ChatRoomRuntimeUseCaseStub(),
            currentUserProvider: currentUserProvider,
            roomReadStateStore: roomReadStateStore
        )
    }

    private func makeRoom(id: String?, creatorUID: String) -> ChatRoom {
        ChatRoom(
            ID: id,
            roomName: "Test Room",
            roomDescription: "Test Description",
            participants: ["me-uid", "sender-uid"],
            creatorUID: creatorUID,
            createdAt: Date(timeIntervalSince1970: 0),
            thumbPath: nil,
            originalPath: nil,
            lastMessageAt: nil,
            lastMessage: nil,
            lastMessageSenderUID: nil,
            seq: 0,
            isClosed: false,
            activeAnnouncementID: nil,
            activeAnnouncement: nil,
            announcementUpdatedAt: nil
        )
    }

    private func makeMessage(senderUID: String, msg: String?, seq: Int64 = 1) -> ChatMessage {
        ChatMessage(
            ID: "message-1",
            seq: seq,
            roomID: "room-1",
            senderUID: senderUID,
            senderEmail: nil,
            senderNickname: "sender",
            senderAvatarPath: nil,
            msg: msg,
            sentAt: Date(timeIntervalSince1970: 123),
            attachments: [],
            replyPreview: nil
        )
    }
}

private final class ChatRoomMessageUseCaseSpy: ChatRoomMessageUseCaseProtocol {
    private(set) var deletedMessages: [ChatMessage] = []
    private(set) var deletedRooms: [ChatRoom] = []

    func makeTextMessage(text: String, replyPreview: ReplyPreview?, room: ChatRoom) -> ChatMessage? {
        nil
    }

    func sendPreparedMessage(_ message: ChatMessage, room: ChatRoom) async throws {}

    func loadMessagesAroundAnchor(
        room: ChatRoom,
        anchor: ChatMessage,
        beforeLimit: Int,
        afterLimit: Int
    ) async throws -> [ChatMessage] {
        throw MessageActionTestError.unimplemented
    }

    func loadOlderMessages(room: ChatRoom, before messageID: String?) async throws -> [ChatMessage] {
        throw MessageActionTestError.unimplemented
    }

    func loadNewerMessages(room: ChatRoom, after messageID: String?) async throws -> [ChatMessage] {
        throw MessageActionTestError.unimplemented
    }

    func handleIncomingMessage(_ message: ChatMessage, room: ChatRoom) async throws {
        throw MessageActionTestError.unimplemented
    }

    func setupDeletionListener(roomID: String, onDeleted: @escaping (String) -> Void) -> AnyCancellable {
        AnyCancellable {}
    }

    func deleteMessage(message: ChatMessage, room: ChatRoom) async throws {
        deletedMessages.append(message)
        deletedRooms.append(room)
    }
}

private final class ChatRoomLifecycleUseCaseSpy: ChatRoomLifecycleUseCaseProtocol {
    struct SetAnnouncementCall {
        let roomID: String
        let messageID: String?
        let payload: AnnouncementPayload?
    }

    struct LastReadSeqCall {
        let roomID: String
        let userUID: String
        let lastReadSeq: Int64
    }

    private(set) var setAnnouncementCalls: [SetAnnouncementCall] = []
    private(set) var lastReadSeqCalls: [LastReadSeqCall] = []

    @MainActor
    func handleRoomSaved(roomID: String) {}

    @MainActor
    func joinRoom(roomID: String) async throws -> ChatRoom {
        throw MessageActionTestError.unimplemented
    }

    func updateLastReadSeq(roomID: String, userUID: String, lastReadSeq: Int64) async throws {
        lastReadSeqCalls.append(
            LastReadSeqCall(
                roomID: roomID,
                userUID: userUID,
                lastReadSeq: lastReadSeq
            )
        )
    }

    @MainActor
    func setActiveAnnouncement(roomID: String, messageID: String?, payload: AnnouncementPayload?) async throws {
        setAnnouncementCalls.append(
            SetAnnouncementCall(
                roomID: roomID,
                messageID: messageID,
                payload: payload
            )
        )
    }

    @MainActor
    func clearActiveAnnouncement(roomID: String) async throws {}
}

private struct ChatInitialLoadUseCaseStub: ChatInitialLoadUseCaseProtocol {
    func execute(
        room: ChatRoom,
        isParticipant: Bool
    ) -> AsyncStream<ChatInitialLoadEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

private struct ChatRoomSearchUseCaseStub: ChatRoomSearchUseCaseProtocol {
    func searchMessages(roomID: String, keyword: String) async throws -> ChatMessageSearchResult {
        ChatMessageSearchResult(
            keyword: keyword,
            totalCount: 0,
            hits: [],
            source: .localOffline,
            isAuthoritative: false
        )
    }

    func applyHighlight(messageIDs: Set<String>) -> Set<String> {
        messageIDs
    }

    func clearHighlight() -> Set<String> {
        []
    }
}

@MainActor
private struct ChatRoomRuntimeUseCaseStub: ChatRoomRuntimeUseCaseProtocol {
    func observeRoomClosed(roomID: String, onClosed: @escaping (String) -> Void) -> ChatRoomRuntimeSubscription {
        ChatRoomRuntimeSubscription()
    }

    func enterVisibleRoom(roomID: String) async {}

    func leaveVisibleRoom() async {}

    func cleanTransientLocalRoomData(roomID: String) async {}
}

private struct ChatRoomRealtimeUseCaseStub: ChatRoomRealtimeUseCaseProtocol {
    func openMessageStream(roomID: String) async throws -> ChatRoomRealtimeSession {
        ChatRoomRealtimeSession(
            roomID: roomID,
            messages: AsyncStream { continuation in
                continuation.finish()
            },
            close: {}
        )
    }
}

private enum MessageActionTestError: Error {
    case unimplemented
}

private struct CurrentUserProviderStub: CurrentUserProviding {
    var email: String = "me@example.com"
    var canonicalUserID: String = "user-1"
    var nickname: String? = "me"
    var avatarPath: String? = nil
    var profile: UserProfile? = nil
}
