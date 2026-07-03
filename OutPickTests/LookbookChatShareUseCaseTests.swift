//
//  LookbookChatShareUseCaseTests.swift
//  OutPickTests
//
//  Created by Codex on 6/16/26.
//

import FirebaseFirestore
import Foundation
import Testing
@testable import OutPick

struct LookbookChatShareUseCaseTests {
    @Test func loadShareableJoinedRoomsFiltersUnavailableRooms() async throws {
        let fake = JoinedRoomsUseCaseFake(rooms: [
            makeRoom(id: "room-1", participants: ["me@example.com"], lastMessageAt: Date(timeIntervalSince1970: 100)),
            makeRoom(id: "room-2", participants: ["me@example.com"], isClosed: true),
            makeRoom(id: "room-3", participants: ["other@example.com"], lastMessageAt: Date(timeIntervalSince1970: 150)),
            makeRoom(id: nil, participants: ["me@example.com"]),
            makeRoom(id: "room-4", participants: [" ME@EXAMPLE.COM "], lastMessageAt: Date(timeIntervalSince1970: 200))
        ])
        let useCase = LoadShareableJoinedRoomsUseCase(
            joinedRoomsUseCase: fake,
            currentUserIDProvider: { "me@example.com" }
        )

        let rooms = try await useCase.execute(limit: 20)

        #expect(fake.requestedHeadLimits == [20])
        #expect(rooms.map { $0.ID ?? "" } == ["room-4", "room-3", "room-1"])
    }

    @Test func loadShareableJoinedRoomsDoesNotTrustLegacyParticipantArray() async throws {
        let fake = JoinedRoomsUseCaseFake(rooms: [
            makeRoom(id: "room-legacy-empty", participants: []),
            makeRoom(id: "room-legacy-stale", participants: ["other@example.com"])
        ])
        let useCase = LoadShareableJoinedRoomsUseCase(
            joinedRoomsUseCase: fake,
            currentUserIDProvider: { "me@example.com" }
        )

        let rooms = try await useCase.execute(limit: 20)

        #expect(rooms.map { $0.ID ?? "" } == ["room-legacy-empty", "room-legacy-stale"])
    }

    @Test func shareLookbookContentSendsThroughRepository() async throws {
        let expected = LookbookChatShareSendResult(roomID: "room-1", messageID: "message-1", seq: 42)
        let repository = LookbookChatShareSendingRepositorySpy(result: expected)
        let useCase = ShareLookbookContentToChatUseCase(
            repository: repository,
            currentUserIDProvider: { "me@example.com" }
        )
        let content = makeSharedContent()
        let room = makeRoom(id: "room-1", participants: ["me@example.com"])

        let result = try await useCase.execute(sharedContent: content, to: room)

        #expect(result == expected)
        #expect(repository.calls.count == 1)
        #expect(repository.calls.first?.sharedContent == content)
        #expect(repository.calls.first?.messageText == nil)
        #expect(repository.calls.first?.room.ID == "room-1")
    }

    @Test func shareLookbookContentForwardsOptionalMessageText() async throws {
        let repository = LookbookChatShareSendingRepositorySpy()
        let useCase = ShareLookbookContentToChatUseCase(
            repository: repository,
            currentUserIDProvider: { "me@example.com" }
        )
        let room = makeRoom(id: "room-1", participants: ["me@example.com"])

        _ = try await useCase.execute(
            sharedContent: makeSharedContent(),
            messageText: "이 시즌 봐봐",
            to: room
        )

        #expect(repository.calls.first?.messageText == "이 시즌 봐봐")
    }

    @Test func shareLookbookContentRejectsClosedRoomBeforeSending() async {
        let repository = LookbookChatShareSendingRepositorySpy()
        let useCase = ShareLookbookContentToChatUseCase(
            repository: repository,
            currentUserIDProvider: { "me@example.com" }
        )
        let room = makeRoom(id: "room-1", participants: ["me@example.com"], isClosed: true)

        await expectShareError(.roomClosed) {
            _ = try await useCase.execute(sharedContent: makeSharedContent(), to: room)
        }
        #expect(repository.calls.isEmpty)
    }

    @Test func shareLookbookContentDoesNotTrustLegacyParticipantArrayBeforeSending() async throws {
        let repository = LookbookChatShareSendingRepositorySpy()
        let useCase = ShareLookbookContentToChatUseCase(
            repository: repository,
            currentUserIDProvider: { "me@example.com" }
        )
        let room = makeRoom(id: "room-1", participants: ["other@example.com"])

        _ = try await useCase.execute(sharedContent: makeSharedContent(), to: room)

        #expect(repository.calls.count == 1)
    }

    @Test func shareLookbookContentRejectsInvalidContentBeforeSending() async {
        let repository = LookbookChatShareSendingRepositorySpy()
        let useCase = ShareLookbookContentToChatUseCase(
            repository: repository,
            currentUserIDProvider: { "me@example.com" }
        )
        let invalidContent = LookbookSharedContent(
            schemaVersion: 1,
            contentType: .post,
            brandID: "brand-1",
            seasonID: nil,
            postID: "post-1",
            titleSnapshot: "포스트"
        )

        await expectShareError(.invalidSharedContent) {
            _ = try await useCase.execute(
                sharedContent: invalidContent,
                to: makeRoom(id: "room-1", participants: ["me@example.com"])
            )
        }
        #expect(repository.calls.isEmpty)
    }

    @Test func ackMapperParsesSuccessAck() throws {
        let result = try LookbookChatShareAckMapper.parse(
            [["ok": true, "messageID": "server-message", "seq": 42]],
            roomID: "room-1",
            fallbackMessageID: "client-message"
        )

        #expect(result == LookbookChatShareSendResult(
            roomID: "room-1",
            messageID: "server-message",
            seq: 42
        ))
    }

    @Test func ackMapperMapsFailureCodes() {
        expectAckError(.notJoined) {
            _ = try LookbookChatShareAckMapper.parse(
                [["ok": false, "error": "not_joined"]],
                roomID: "room-1",
                fallbackMessageID: "client-message"
            )
        }

        expectAckError(.roomClosed) {
            _ = try LookbookChatShareAckMapper.parse(
                [["ok": false, "error": "room_closed"]],
                roomID: "room-1",
                fallbackMessageID: "client-message"
            )
        }

        expectAckError(.timeout) {
            _ = try LookbookChatShareAckMapper.parse(
                ["NO ACK"],
                roomID: "room-1",
                fallbackMessageID: "client-message"
            )
        }
    }

    @Test func makeSharedContentUseCaseBuildsPostSnapshotWithFetchedBrandAndSeason() async throws {
        let brand = makeBrand(id: "brand-1", name: "Hatchingroom")
        let season = makeSeason(id: "season-1", brandID: brand.id, title: "26 S/S")
        let post = makePost(brandID: brand.id, seasonID: season.id, postID: PostID(value: "post-1"))
        let useCase = MakeLookbookSharedContentUseCase(
            brandRepository: BrandRepositoryFake(brands: [brand]),
            seasonRepository: SeasonRepositoryFake(seasons: [season])
        )

        let content = try await useCase.execute(target: .post(post))

        #expect(content.contentType == .post)
        #expect(content.brandID == "brand-1")
        #expect(content.seasonID == "season-1")
        #expect(content.postID == "post-1")
        #expect(content.titleSnapshot == "포스트")
        #expect(content.subtitleSnapshot == "Hatchingroom · 26 S/S")
        #expect(content.thumbnailPathSnapshot == "post-thumb.jpg")
    }

    @Test @MainActor func shareViewModelRequiresExplicitRoomSelectionBeforeSending() async throws {
        let content = makeSharedContent()
        let roomsUseCase = ShareableRoomsUseCaseFake(rooms: [
            makeRoom(id: "room-1", participants: ["me@example.com"])
        ])
        let shareUseCase = ShareLookbookContentUseCaseSpy(
            result: LookbookChatShareSendResult(roomID: "room-1", messageID: "message-1", seq: 7)
        )
        let viewModel = LookbookChatShareViewModel(
            target: .season(makeSeason(id: "season-1", brandID: BrandID(value: "brand-1"), title: "26 S/S")),
            makeSharedContentUseCase: SharedContentUseCaseFake(content: content),
            loadRoomsUseCase: roomsUseCase,
            shareUseCase: shareUseCase
        )

        await viewModel.loadIfNeeded()

        #expect(viewModel.phase == .ready)
        #expect(viewModel.selectedRoomID == nil)
        #expect(viewModel.canSend == false)

        viewModel.selectedRoomID = "room-1"
        await viewModel.send()

        #expect(viewModel.selectedRoomID == "room-1")
        #expect(viewModel.canSend == true)
        #expect(roomsUseCase.requestedLimits == [50])
        #expect(shareUseCase.calls.count == 1)
        #expect(shareUseCase.calls.first?.sharedContent == content)
        #expect(viewModel.completion == LookbookChatShareViewModel.Completion(
            roomID: "room-1",
            roomName: "Test Room",
            messageID: "message-1"
        ))
    }

    @Test @MainActor func shareViewModelShowsEmptyWhenNoRooms() async {
        let viewModel = LookbookChatShareViewModel(
            target: .brand(makeBrand(id: "brand-1", name: "Brand")),
            makeSharedContentUseCase: SharedContentUseCaseFake(content: makeSharedContent()),
            loadRoomsUseCase: ShareableRoomsUseCaseFake(rooms: []),
            shareUseCase: ShareLookbookContentUseCaseSpy()
        )

        await viewModel.loadIfNeeded()

        #expect(viewModel.phase == .empty)
        #expect(viewModel.rooms.isEmpty)
        #expect(viewModel.canSend == false)
    }

    private func expectShareError(
        _ expected: LookbookChatShareError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            #expect(Bool(false), "Expected \(expected)")
        } catch let error as LookbookChatShareError {
            #expect(error == expected)
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    private func expectAckError(
        _ expected: LookbookChatShareError,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            #expect(Bool(false), "Expected \(expected)")
        } catch let error as LookbookChatShareError {
            #expect(error == expected)
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    private func makeSharedContent() -> LookbookSharedContent {
        LookbookSharedContent(
            schemaVersion: 1,
            contentType: .season,
            brandID: "brand-1",
            seasonID: "season-1",
            titleSnapshot: "2026 Summer",
            subtitleSnapshot: "Brand"
        )
    }

    private func makeRoom(
        id: String?,
        participants: [String],
        isClosed: Bool = false,
        lastMessageAt: Date? = nil
    ) -> ChatRoom {
        ChatRoom(
            ID: id,
            roomName: "Test Room",
            roomDescription: "Test Description",
            participants: participants,
            creatorUID: "owner@example.com",
            createdAt: Date(timeIntervalSince1970: 0),
            thumbPath: nil,
            originalPath: nil,
            lastMessageAt: lastMessageAt,
            lastMessage: nil,
            lastMessageSenderUID: nil,
            seq: 0,
            isClosed: isClosed,
            activeAnnouncementID: nil,
            activeAnnouncement: nil,
            announcementUpdatedAt: nil
        )
    }

    private func makeBrand(id: String, name: String) -> Brand {
        Brand(
            id: BrandID(value: id),
            name: name,
            websiteURL: nil,
            lookbookArchiveURL: nil,
            logoThumbPath: "brand-thumb.jpg",
            logoDetailPath: nil,
            logoOriginalPath: nil,
            isFeatured: false,
            discoveryStatus: .idle,
            lastDiscoveryErrorMessage: nil,
            lastDiscoveryRequestedAt: nil,
            lastDiscoveryCompletedAt: nil,
            metrics: BrandMetrics(likeCount: 0, viewCount: 0, popularScore: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeSeason(id: String, brandID: BrandID, title: String) -> Season {
        Season(
            id: SeasonID(value: id),
            brandID: brandID,
            displayTitle: title,
            sourceTitle: nil,
            year: nil,
            term: nil,
            coverPath: "season-cover.jpg",
            coverRemoteURL: nil,
            description: "",
            tagIDs: [],
            tagConceptIDs: nil,
            status: .published,
            assetSyncStatus: .ready,
            metadataStatus: .confirmed,
            metadataConfidence: nil,
            sourceURL: nil,
            sourceImportJobID: nil,
            sourceSortIndex: nil,
            postCount: 1,
            likeCount: 0,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makePost(brandID: BrandID, seasonID: SeasonID, postID: PostID) -> LookbookPost {
        LookbookPost(
            id: postID,
            brandID: brandID,
            seasonID: seasonID,
            authorID: nil,
            media: [
                MediaAsset(
                    type: .image,
                    remoteURL: URL(string: "https://example.com/post.jpg")!,
                    thumbPath: "post-thumb.jpg",
                    detailPath: "post-detail.jpg",
                    sourcePageURL: nil
                )
            ],
            caption: nil,
            tagIDs: [],
            metrics: PostMetrics(
                likeCount: 0,
                commentCount: 0,
                replacementCount: 0,
                saveCount: 0,
                viewCount: nil
            ),
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

private final class SharedContentUseCaseFake: MakeLookbookSharedContentUseCaseProtocol {
    private let content: LookbookSharedContent

    init(content: LookbookSharedContent) {
        self.content = content
    }

    func execute(target: LookbookShareTarget) async throws -> LookbookSharedContent {
        content
    }
}

private final class ShareableRoomsUseCaseFake: LoadShareableJoinedRoomsUseCaseProtocol {
    private let rooms: [ChatRoom]
    private(set) var requestedLimits: [Int] = []

    init(rooms: [ChatRoom]) {
        self.rooms = rooms
    }

    func execute(limit: Int) async throws -> [ChatRoom] {
        requestedLimits.append(limit)
        return rooms
    }
}

private final class ShareLookbookContentUseCaseSpy: ShareLookbookContentToChatUseCaseProtocol {
    struct Call {
        let sharedContent: LookbookSharedContent
        let messageText: String?
        let room: ChatRoom
    }

    private let result: LookbookChatShareSendResult
    var error: Error?
    private(set) var calls: [Call] = []

    init(
        result: LookbookChatShareSendResult = LookbookChatShareSendResult(
            roomID: "room-1",
            messageID: "message-1",
            seq: nil
        )
    ) {
        self.result = result
    }

    func execute(
        sharedContent: LookbookSharedContent,
        messageText: String?,
        to room: ChatRoom
    ) async throws -> LookbookChatShareSendResult {
        calls.append(Call(sharedContent: sharedContent, messageText: messageText, room: room))
        if let error {
            throw error
        }
        return result
    }
}

private final class BrandRepositoryFake: BrandRepositoryProtocol {
    private let brandsByID: [BrandID: Brand]

    init(brands: [Brand]) {
        self.brandsByID = Dictionary(uniqueKeysWithValues: brands.map { ($0.id, $0) })
    }

    func fetchBrand(brandID: BrandID) async throws -> Brand {
        guard let brand = brandsByID[brandID] else {
            throw NSError(domain: "BrandRepositoryFake", code: -1)
        }
        return brand
    }

    func fetchBrands(sort: BrandSort?, limit: Int, after last: DocumentSnapshot?) async throws -> BrandPage {
        BrandPage(items: Array(brandsByID.values), last: nil)
    }

    func fetchFeaturedBrands(sort: BrandSort?, limit: Int, after last: DocumentSnapshot?) async throws -> BrandPage {
        BrandPage(items: Array(brandsByID.values), last: nil)
    }
}

private final class SeasonRepositoryFake: SeasonRepositoryProtocol {
    private let seasonsByKey: [String: Season]

    init(seasons: [Season]) {
        self.seasonsByKey = Dictionary(
            uniqueKeysWithValues: seasons.map { ("\($0.brandID.value)|\($0.id.value)", $0) }
        )
    }

    func createSeason(
        brandID: BrandID,
        year: Int,
        term: SeasonTerm,
        description: String,
        coverImageData: Data?,
        tagIDs: [TagID],
        tagConceptIDs: [String]?
    ) async throws -> Season {
        throw NSError(domain: "SeasonRepositoryFake", code: -2)
    }

    func fetchSeason(brandID: BrandID, seasonID: SeasonID) async throws -> Season {
        let key = "\(brandID.value)|\(seasonID.value)"
        guard let season = seasonsByKey[key] else {
            throw NSError(domain: "SeasonRepositoryFake", code: -1)
        }
        return season
    }

    func fetchSeasons(brandID: BrandID, pageSize: Int, after last: DocumentSnapshot?) async throws -> SeasonPage {
        SeasonPage(items: Array(seasonsByKey.values), last: nil)
    }

    func fetchAllSeasons(brandID: BrandID) async throws -> [Season] {
        Array(seasonsByKey.values).filter { $0.brandID == brandID }
    }
}

private final class JoinedRoomsUseCaseFake: JoinedRoomsUseCaseProtocol {
    private let rooms: [ChatRoom]
    private(set) var requestedHeadLimits: [Int] = []

    init(rooms: [ChatRoom]) {
        self.rooms = rooms
    }

    func fetchJoinedRooms(limit: Int?) async throws -> [JoinedRoomListItem] {
        if let limit {
            requestedHeadLimits.append(limit)
        }
        let source = limit.map { Array(rooms.prefix($0)) } ?? rooms
        return source.enumerated().map { index, room in
            let projectionRoomID = room.ID ?? "missing-room-\(index)"
            return JoinedRoomListItem(
                room: room,
                projection: JoinedRoomProjection(
                    documentID: projectionRoomID,
                    data: [
                        "roomID": projectionRoomID,
                        "lastReadSeq": room.seq,
                        "isClosed": room.isClosed
                    ]
                )!
            )
        }
    }

    func fetchUnreadCount(roomID: String, lastMessageSeqHint: Int64?, lastMessageSenderUID: String?) async -> Int64 {
        0
    }

    func fetchReadSnapshot(roomID: String, lastMessageSeqHint: Int64?, lastMessageSenderUID: String?) async -> ChatRoomReadSnapshot? {
        ChatRoomReadSnapshot(
            roomID: roomID,
            latestSeq: lastMessageSeqHint,
            lastReadSeq: lastMessageSeqHint,
            lastMessageSenderUID: lastMessageSenderUID
        )
    }

    func canLeaveFromList(room: ChatRoom) -> Bool {
        true
    }

    func leave(room: ChatRoom) async throws -> ChatRoomExitResult {
        ChatRoomExitResult(roomID: room.ID ?? "", mode: .left)
    }
}

private final class LookbookChatShareSendingRepositorySpy: LookbookChatShareSendingRepositoryProtocol {
    struct Call {
        let sharedContent: LookbookSharedContent
        let messageText: String?
        let room: ChatRoom
    }

    private let result: LookbookChatShareSendResult
    var error: Error?
    private(set) var calls: [Call] = []

    init(
        result: LookbookChatShareSendResult = LookbookChatShareSendResult(
            roomID: "room-1",
            messageID: "message-1",
            seq: nil
        )
    ) {
        self.result = result
    }

    func sendLookbookShare(
        sharedContent: LookbookSharedContent,
        messageText: String?,
        to room: ChatRoom
    ) async throws -> LookbookChatShareSendResult {
        calls.append(Call(sharedContent: sharedContent, messageText: messageText, room: room))
        if let error {
            throw error
        }
        return result
    }
}
