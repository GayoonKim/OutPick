//
//  OutPickTests.swift
//  OutPickTests
//
//  Created by 김가윤 on 7/11/25.
//

import Foundation
import Testing
@testable import OutPick

struct OutPickTests {

    @MainActor
    @Test func loadInitialSkipsFailedLocalMediaBeforeFetchingRemote() async throws {
        let now = Date()
        let localRepository = LocalMediaRepositoryStub(
            imageCount: 3,
            latestImages: [
                makeImageMeta(
                    messageID: "failed-local",
                    hash: "failed-hash",
                    originalURL: "file:///failed.jpg",
                    isFailed: true,
                    sentAt: now
                ),
                makeImageMeta(
                    messageID: "local-visible-1",
                    hash: "visible-1",
                    originalURL: "rooms/room-1/messages/local-visible-1/original.jpg",
                    sentAt: now.addingTimeInterval(-1)
                )
            ],
            olderImagePages: [[
                makeImageMeta(
                    messageID: "local-visible-2",
                    hash: "visible-2",
                    originalURL: "rooms/room-1/messages/local-visible-2/original.jpg",
                    sentAt: now.addingTimeInterval(-2)
                )
            ]]
        )
        let remoteRepository = RemoteMediaRepositoryStub(
            latestEntries: [
                makeRemoteEntry(
                    roomID: "room-1",
                    messageID: "remote-should-not-load",
                    hash: "remote-hash",
                    originalURL: "rooms/room-1/messages/remote/original.jpg",
                    sentAt: now.addingTimeInterval(-3)
                )
            ]
        )
        let useCase = LoadChatRoomMediaUseCase(
            localMediaRepository: localRepository,
            remoteMediaRepository: remoteRepository,
            pageSize: 2
        )

        let result = try await useCase.loadInitial(room: makeRoom(id: "room-1"))

        #expect(result.items.map(\.id) == ["local-visible-1#0", "local-visible-2#0"])
        #expect(result.items.allSatisfy { $0.hash != "failed-hash" })
        #expect(remoteRepository.latestFetchCalls == 0)
    }

    @MainActor
    @Test func loadInitialDedupesMediaByHashAndStoragePath() async throws {
        let now = Date()
        let localRepository = LocalMediaRepositoryStub(
            imageCount: 3,
            latestImages: [
                makeImageMeta(
                    messageID: "local-hash-primary",
                    hash: "shared-hash",
                    originalURL: "rooms/room-2/messages/local-hash-primary/original.jpg",
                    sentAt: now
                ),
                makeImageMeta(
                    messageID: "local-hash-duplicate",
                    hash: "shared-hash",
                    originalURL: "rooms/room-2/messages/local-hash-duplicate/original.jpg",
                    sentAt: now.addingTimeInterval(-1)
                ),
                makeImageMeta(
                    messageID: "local-storage-primary",
                    hash: nil,
                    originalURL: "rooms/room-2/shared/original.jpg",
                    sentAt: now.addingTimeInterval(-2)
                )
            ]
        )
        let remoteRepository = RemoteMediaRepositoryStub(
            latestEntries: [
                makeRemoteEntry(
                    roomID: "room-2",
                    messageID: "remote-storage-duplicate",
                    hash: nil,
                    originalURL: "rooms/room-2/shared/original.jpg",
                    sentAt: now.addingTimeInterval(-3)
                ),
                makeRemoteEntry(
                    roomID: "room-2",
                    messageID: "remote-unique",
                    hash: "remote-unique-hash",
                    originalURL: "rooms/room-2/messages/remote-unique/original.jpg",
                    sentAt: now.addingTimeInterval(-4)
                )
            ]
        )
        let useCase = LoadChatRoomMediaUseCase(
            localMediaRepository: localRepository,
            remoteMediaRepository: remoteRepository,
            pageSize: 4
        )

        let result = try await useCase.loadInitial(room: makeRoom(id: "room-2"))

        #expect(result.items.map(\.id) == [
            "local-hash-primary#0",
            "local-storage-primary#0",
            "remote-unique#0"
        ])
        #expect(remoteRepository.latestFetchCalls == 1)
    }

}

private final class LocalMediaRepositoryStub: ChatRoomMediaIndexRepositoryProtocol {
    let imageCount: Int
    let videoCount: Int
    let latestImages: [ImageIndexMeta]
    let latestVideos: [VideoIndexMeta]
    var olderImagePages: [[ImageIndexMeta]]
    var olderVideoPages: [[VideoIndexMeta]]

    init(
        imageCount: Int = 0,
        videoCount: Int = 0,
        latestImages: [ImageIndexMeta] = [],
        latestVideos: [VideoIndexMeta] = [],
        olderImagePages: [[ImageIndexMeta]] = [],
        olderVideoPages: [[VideoIndexMeta]] = []
    ) {
        self.imageCount = imageCount
        self.videoCount = videoCount
        self.latestImages = latestImages
        self.latestVideos = latestVideos
        self.olderImagePages = olderImagePages
        self.olderVideoPages = olderVideoPages
    }

    func countImageIndex(inRoom roomID: String) throws -> Int {
        imageCount
    }

    func countVideoIndex(inRoom roomID: String) throws -> Int {
        videoCount
    }

    func fetchLatestImageIndex(inRoom roomID: String, limit: Int) throws -> [ImageIndexMeta] {
        Array(latestImages.prefix(limit))
    }

    func fetchLatestVideoIndex(inRoom roomID: String, limit: Int) throws -> [VideoIndexMeta] {
        Array(latestVideos.prefix(limit))
    }

    func fetchOlderImageIndex(
        inRoom roomID: String,
        beforeSentAt: Date,
        beforeMessageID: String,
        limit: Int
    ) throws -> [ImageIndexMeta] {
        guard !olderImagePages.isEmpty else { return [] }
        return Array(olderImagePages.removeFirst().prefix(limit))
    }

    func fetchOlderVideoIndex(
        inRoom roomID: String,
        beforeSentAt: Date,
        beforeMessageID: String,
        limit: Int
    ) throws -> [VideoIndexMeta] {
        guard !olderVideoPages.isEmpty else { return [] }
        return Array(olderVideoPages.removeFirst().prefix(limit))
    }

    func upsertMediaIndexEntries(_ entries: [ChatRoomMediaIndexEntry]) throws {}
}

private final class RemoteMediaRepositoryStub: RemoteChatRoomMediaIndexRepositoryProtocol {
    var latestEntries: [ChatRoomMediaIndexEntry]
    var olderEntries: [ChatRoomMediaIndexEntry]
    private(set) var latestFetchCalls: Int = 0
    private(set) var olderFetchCalls: Int = 0

    init(
        latestEntries: [ChatRoomMediaIndexEntry] = [],
        olderEntries: [ChatRoomMediaIndexEntry] = []
    ) {
        self.latestEntries = latestEntries
        self.olderEntries = olderEntries
    }

    func fetchLatestMedia(inRoom roomID: String, limit: Int) async throws -> [ChatRoomMediaIndexEntry] {
        latestFetchCalls += 1
        return Array(latestEntries.prefix(limit))
    }

    func fetchOlderMedia(
        inRoom roomID: String,
        before cursor: ChatRoomMediaIndexCursor,
        limit: Int
    ) async throws -> [ChatRoomMediaIndexEntry] {
        olderFetchCalls += 1
        return Array(olderEntries.prefix(limit))
    }
}

private func makeRoom(id: String) -> ChatRoom {
    ChatRoom(
        ID: id,
        roomName: "Test Room",
        roomDescription: "Test Description",
        participants: [],
        creatorID: "owner@test.com",
        createdAt: Date(),
        thumbPath: nil,
        originalPath: nil,
        lastMessageAt: nil,
        lastMessage: nil,
        lastMessageSenderID: nil,
        seq: 0,
        isClosed: false,
        activeAnnouncementID: nil,
        activeAnnouncement: nil,
        announcementUpdatedAt: nil
    )
}

private func makeImageMeta(
    messageID: String,
    idx: Int = 0,
    hash: String?,
    originalURL: String?,
    thumbURL: String? = nil,
    isFailed: Bool = false,
    sentAt: Date
) -> ImageIndexMeta {
    ImageIndexMeta(
        roomID: "room",
        messageID: messageID,
        idx: idx,
        thumbKey: hash,
        originalKey: hash.map { "\($0):orig" },
        thumbURL: thumbURL,
        originalURL: originalURL,
        width: 100,
        height: 100,
        bytesOriginal: 1_024,
        hash: hash,
        isFailed: isFailed,
        localThumb: nil,
        sentAt: sentAt
    )
}

private func makeRemoteEntry(
    roomID: String,
    messageID: String,
    idx: Int = 0,
    hash: String?,
    originalURL: String?,
    thumbURL: String? = nil,
    sentAt: Date
) -> ChatRoomMediaIndexEntry {
    ChatRoomMediaIndexEntry(
        roomID: roomID,
        messageID: messageID,
        idx: idx,
        seq: 0,
        senderID: "sender@test.com",
        type: .image,
        thumbKey: hash,
        originalKey: hash.map { "\($0):orig" },
        thumbURL: thumbURL,
        originalURL: originalURL,
        width: 100,
        height: 100,
        bytesOriginal: 1_024,
        duration: nil,
        hash: hash,
        isDeleted: false,
        sentAt: sentAt
    )
}
