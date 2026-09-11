import Foundation
import Testing
@testable import OutPick

@MainActor
struct RoomListsViewModelDeletionTests {
    @Test func staleCachedPreviewUsesPersistedDeletionMarker() async throws {
        let database = try TemporaryAppDatabase.make()
        let store = GRDBChatDeletionSyncStore(database: database)
        let room = ChatRoom(id: "room-1", roomName: "QA", roomDescription: "", participants: [], ownerUID: "owner", createdAt: Date())
        let original = GRDBTestFixtures.message(id: "preview", seq: 1, text: "삭제 전 원문")
        _ = try await store.apply([ChatDeletionDelta(messageID: "preview", roomID: room.id,
            seq: 1, revision: 1, deletedAt: nil)], accountID: "account-1", roomID: room.id)
        let result = await RoomListUseCase.resolveCachedPreviews([(room, [original])]) { messages, roomID in
            try await store.sanitize(messages, accountID: "account-1", roomID: roomID)
        }
        #expect(original.msg == "삭제 전 원문")
        #expect(result.first?.messages.first?.isDeleted == true)
        #expect(result.first?.messages.first?.msg == nil)
    }

    @Test func localReadFailureKeepsRoomButNeverFallsBackToOriginal() async {
        let room = ChatRoom(id: "room-1", roomName: "QA", roomDescription: "", participants: [], ownerUID: "owner", createdAt: Date())
        let original = GRDBTestFixtures.message(id: "preview", seq: 1, text: "원문")
        let result = await RoomListUseCase.resolveCachedPreviews([(room, [original])]) { _, _ in
            throw CancellationError()
        }
        #expect(result.first?.room.id == room.id)
        #expect(result.first?.messages.isEmpty == true)
    }

    @Test func returningToListClearsOldPreviewBeforeLocalReadCompletes() async {
        let useCase = GatedRoomListUseCase()
        let viewModel = RoomListsViewModel(useCase: useCase)
        viewModel.onAppear()
        await useCase.waitForRequest(1)
        useCase.finish(0, deleted: false)
        await useCase.waitForProfileRefresh()
        #expect(viewModel.state.rooms.first?.messages.first?.msg == "원문")
        viewModel.onAppear()
        #expect(viewModel.state.rooms.first?.messages.isEmpty == true)
        await useCase.waitForRequest(2)
        useCase.finish(1, deleted: true)
        for _ in 0..<100 { await Task.yield() }
        #expect(viewModel.state.rooms.first?.messages.first?.isDeleted == true)
    }

    @Test func staleReadCannotRestoreOriginalAfterNewerDeletionRead() async {
        let useCase = GatedRoomListUseCase()
        let viewModel = RoomListsViewModel(useCase: useCase)
        viewModel.onAppear()
        await useCase.waitForRequest(1)
        viewModel.onAppear()
        await useCase.waitForRequest(2)
        useCase.finish(1, deleted: true)
        await useCase.waitForProfileRefresh()
        useCase.finish(0, deleted: false)
        for _ in 0..<100 { await Task.yield() }
        #expect(viewModel.state.rooms.first?.messages.first?.isDeleted == true)
        #expect(viewModel.state.rooms.first?.messages.first?.msg == nil)
    }
}

@MainActor
private final class GatedRoomListUseCase: RoomListUseCaseProtocol {
    var requests: [CheckedContinuation<[ChatRoomPreviewItem], Never>] = []
    var last: [ChatRoomPreviewItem] = []
    var profileRefreshes = 0
    func cachedTopRooms() async -> [ChatRoomPreviewItem] {
        await withCheckedContinuation { requests.append($0) }
    }
    func refreshTopRooms(limit: Int) async throws -> [ChatRoomPreviewItem] { last }
    func refreshCachedProfiles() async -> [ChatRoomPreviewItem] {
        profileRefreshes += 1
        return last
    }
    func removeCachedRoom(roomID: String) {}
    func waitForRequest(_ count: Int) async {
        for _ in 0..<10_000 {
            if requests.count >= count { return }
            await Task.yield()
        }
        Issue.record("목록 조회가 시작되지 않음")
    }
    func waitForProfileRefresh() async {
        for _ in 0..<10_000 {
            if profileRefreshes > 0 { return }
            await Task.yield()
        }
        Issue.record("로컬 결과가 표시되지 않음")
    }
    func finish(_ index: Int, deleted: Bool) {
        let room = ChatRoom(id: "room-1", roomName: "QA", roomDescription: "", participants: [], ownerUID: "owner", createdAt: Date())
        let message = ChatMessage(ID: "preview", seq: 1, roomID: "room-1", senderUID: "sender",
            senderNickname: "QA", msg: deleted ? nil : "원문", sentAt: Date(),
            attachments: [], replyPreview: nil, isDeleted: deleted)
        last = [ChatRoomPreviewItem(room: room, messages: [message])]
        requests[index].resume(returning: last)
    }
}
