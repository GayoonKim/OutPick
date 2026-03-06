//
//  LoadChatRoomMediaUseCase.swift
//  OutPick
//
//  Created by Codex on 3/7/26.
//

import Foundation
import FirebaseFirestore

struct ChatRoomMediaLoadResult {
    let items: [ChatRoomSettingMediaItem]
    let hasMore: Bool
}

protocol LoadChatRoomMediaUseCaseProtocol {
    func loadInitial(room: ChatRoom) async throws -> ChatRoomMediaLoadResult
    func loadMore(room: ChatRoom) async throws -> ChatRoomMediaLoadResult
}

@MainActor
final class LoadChatRoomMediaUseCase: LoadChatRoomMediaUseCaseProtocol {
    private let localMediaRepository: ChatRoomMediaIndexRepositoryProtocol
    private let remoteMediaRepository: RemoteChatRoomMediaIndexRepositoryProtocol
    private let pageSize: Int

    private var activeRoomID: String?
    private var imageIndexItems: [ImageIndexMeta] = []
    private var videoIndexItems: [VideoIndexMeta] = []
    private var pendingLocalItems: [ChatRoomSettingMediaItem] = []
    private var deliveredItems: [ChatRoomSettingMediaItem] = []
    private var deliveredItemIDs = Set<String>()
    private var localImageTotalCount: Int = 0
    private var localVideoTotalCount: Int = 0
    private var localHasMore: Bool = true
    private var remoteHasMore: Bool = false
    private var isUsingRemoteHistory: Bool = false
    private var lastRemoteCursor: ChatRoomMediaIndexCursor?

    init(
        localMediaRepository: ChatRoomMediaIndexRepositoryProtocol,
        remoteMediaRepository: RemoteChatRoomMediaIndexRepositoryProtocol,
        pageSize: Int = 60
    ) {
        self.localMediaRepository = localMediaRepository
        self.remoteMediaRepository = remoteMediaRepository
        self.pageSize = pageSize
    }

    func loadInitial(room: ChatRoom) async throws -> ChatRoomMediaLoadResult {
        let roomID = room.ID ?? ""
        resetState(for: roomID)

        try loadInitialLocalBatch(roomID: roomID)

        var items = dequeueLocalItems(limit: pageSize)
        if items.count < pageSize {
            let remoteItems = await fetchRemoteItemsIfAvailable(
                roomID: roomID,
                limit: pageSize - items.count
            )
            items.append(contentsOf: remoteItems)
        }

        return makeResult(items: items)
    }

    func loadMore(room: ChatRoom) async throws -> ChatRoomMediaLoadResult {
        let roomID = room.ID ?? ""
        guard activeRoomID == roomID else {
            return try await loadInitial(room: room)
        }
        guard hasMoreAvailable else {
            return makeResult(items: [])
        }

        if !pendingLocalItems.isEmpty && !isUsingRemoteHistory {
            let items = dequeueLocalItems(limit: pageSize)
            return makeResult(items: items)
        }

        if localHasMore && !isUsingRemoteHistory {
            try loadNextLocalBatch(roomID: roomID)
            if !pendingLocalItems.isEmpty {
                let items = dequeueLocalItems(limit: pageSize)
                return makeResult(items: items)
            }
        }

        let items = await fetchRemoteItemsIfAvailable(roomID: roomID, limit: pageSize)
        return makeResult(items: items)
    }

    private func makeUnifiedMediaItems(
        images: [ImageIndexMeta],
        videos: [VideoIndexMeta],
        limit: Int? = nil
    ) -> [ChatRoomSettingMediaItem] {
        var unified: [ChatRoomSettingMediaItem] = images.map {
            ChatRoomSettingMediaItem(
                messageID: $0.messageID,
                idx: $0.idx,
                thumbKey: $0.thumbKey,
                originalKey: $0.originalKey,
                thumbURL: $0.thumbURL,
                originalURL: $0.originalURL,
                localThumb: $0.localThumb,
                sentAt: $0.sentAt,
                isVideo: false
            )
        }
        unified.append(contentsOf: videos.map {
            ChatRoomSettingMediaItem(
                messageID: $0.messageID,
                idx: $0.idx,
                thumbKey: $0.thumbKey,
                originalKey: $0.originalKey,
                thumbURL: $0.thumbURL,
                originalURL: $0.originalURL,
                localThumb: $0.localThumb,
                sentAt: $0.sentAt,
                isVideo: true
            )
        })

        unified.sort { lhs, rhs in
            if lhs.sentAt != rhs.sentAt { return lhs.sentAt > rhs.sentAt }
            if lhs.messageID != rhs.messageID { return lhs.messageID > rhs.messageID }
            return lhs.idx < rhs.idx
        }

        if let limit, unified.count > limit {
            return Array(unified.prefix(limit))
        }
        return unified
    }

    private var hasMoreAvailable: Bool {
        let remotePotential = !isUsingRemoteHistory && !deliveredItems.isEmpty
        return !pendingLocalItems.isEmpty || localHasMore || remoteHasMore || remotePotential
    }

    private func resetState(for roomID: String) {
        activeRoomID = roomID
        imageIndexItems = []
        videoIndexItems = []
        pendingLocalItems = []
        deliveredItems = []
        deliveredItemIDs = []
        localImageTotalCount = 0
        localVideoTotalCount = 0
        localHasMore = true
        remoteHasMore = false
        isUsingRemoteHistory = false
        lastRemoteCursor = nil
    }

    private func loadInitialLocalBatch(roomID: String) throws {
        localImageTotalCount = try localMediaRepository.countImageIndex(inRoom: roomID)
        localVideoTotalCount = try localMediaRepository.countVideoIndex(inRoom: roomID)

        let imgPage = try localMediaRepository.fetchLatestImageIndex(inRoom: roomID, limit: pageSize)
        let vidPage = try localMediaRepository.fetchLatestVideoIndex(inRoom: roomID, limit: pageSize)

        imageIndexItems = imgPage
        videoIndexItems = vidPage

        enqueueLocalItems(makeUnifiedMediaItems(images: imgPage, videos: vidPage))
        refreshLocalHasMore()
    }

    private func loadNextLocalBatch(roomID: String) throws {
        let existingImageKeys = Set(imageIndexItems.map { "\($0.messageID)#\($0.idx)" })
        let existingVideoKeys = Set(videoIndexItems.map { "\($0.messageID)#\($0.idx)" })

        var newImgs: [ImageIndexMeta] = []
        var newVids: [VideoIndexMeta] = []

        if let anchor = imageIndexItems.last {
            newImgs = try localMediaRepository.fetchOlderImageIndex(
                inRoom: roomID,
                beforeSentAt: anchor.sentAt,
                beforeMessageID: anchor.messageID,
                limit: pageSize
            ).filter { !existingImageKeys.contains("\($0.messageID)#\($0.idx)") }
        }

        if let anchor = videoIndexItems.last {
            newVids = try localMediaRepository.fetchOlderVideoIndex(
                inRoom: roomID,
                beforeSentAt: anchor.sentAt,
                beforeMessageID: anchor.messageID,
                limit: pageSize
            ).filter { !existingVideoKeys.contains("\($0.messageID)#\($0.idx)") }
        }

        imageIndexItems.append(contentsOf: newImgs)
        videoIndexItems.append(contentsOf: newVids)
        enqueueLocalItems(makeUnifiedMediaItems(images: newImgs, videos: newVids))
        refreshLocalHasMore()
    }

    private func enqueueLocalItems(_ items: [ChatRoomSettingMediaItem]) {
        guard !items.isEmpty else { return }

        var knownIDs = Set(pendingLocalItems.map(\.id))
        knownIDs.formUnion(deliveredItemIDs)

        let unique = items.filter { knownIDs.insert($0.id).inserted }
        pendingLocalItems.append(contentsOf: unique)
    }

    private func dequeueLocalItems(limit: Int) -> [ChatRoomSettingMediaItem] {
        guard !pendingLocalItems.isEmpty, limit > 0 else { return [] }

        let count = min(limit, pendingLocalItems.count)
        let page = Array(pendingLocalItems.prefix(count))
        pendingLocalItems.removeFirst(count)
        registerDelivered(page)
        refreshLocalHasMore()
        return page
    }

    private func fetchRemoteItems(
        roomID: String,
        limit: Int
    ) async throws -> [ChatRoomSettingMediaItem] {
        guard limit > 0 else { return [] }
        if isUsingRemoteHistory && !remoteHasMore {
            return []
        }

        let entries: [ChatRoomMediaIndexEntry]
        if let cursor = lastRemoteCursor {
            entries = try await remoteMediaRepository.fetchOlderMedia(inRoom: roomID, before: cursor, limit: limit)
        } else if let cursor = deliveredItems.last?.cursor {
            entries = try await remoteMediaRepository.fetchOlderMedia(inRoom: roomID, before: cursor, limit: limit)
        } else {
            entries = try await remoteMediaRepository.fetchLatestMedia(inRoom: roomID, limit: limit)
        }

        isUsingRemoteHistory = true
        remoteHasMore = entries.count == limit
        lastRemoteCursor = entries.last?.cursor

        guard !entries.isEmpty else {
            remoteHasMore = false
            return []
        }

        try localMediaRepository.upsertMediaIndexEntries(entries)

        var knownIDs = deliveredItemIDs
        let items = entries
            .map(makeMediaItem(from:))
            .filter { knownIDs.insert($0.id).inserted }

        registerDelivered(items)
        return items
    }

    private func fetchRemoteItemsIfAvailable(
        roomID: String,
        limit: Int
    ) async -> [ChatRoomSettingMediaItem] {
        do {
            return try await fetchRemoteItems(roomID: roomID, limit: limit)
        } catch let error as NSError {
            if error.domain == FirestoreErrorDomain,
               error.code == FirestoreErrorCode.failedPrecondition.rawValue {
                isUsingRemoteHistory = true
                remoteHasMore = false
                print("⚠️ Firestore mediaIndex 인덱스가 아직 배포되지 않아 원격 미디어 보충을 건너뜁니다.")
                return []
            }

            print("❌ 원격 미디어 로드 실패:", error)
            return []
        } catch {
            print("❌ 원격 미디어 로드 실패:", error)
            return []
        }
    }

    private func registerDelivered(_ items: [ChatRoomSettingMediaItem]) {
        guard !items.isEmpty else { return }

        deliveredItems.append(contentsOf: items)
        for item in items {
            deliveredItemIDs.insert(item.id)
        }
    }

    private func refreshLocalHasMore() {
        let hasBufferedItems = !pendingLocalItems.isEmpty
        let canFetchMoreImages = imageIndexItems.count < localImageTotalCount
        let canFetchMoreVideos = videoIndexItems.count < localVideoTotalCount
        localHasMore = hasBufferedItems || canFetchMoreImages || canFetchMoreVideos
    }

    private func makeResult(items: [ChatRoomSettingMediaItem]) -> ChatRoomMediaLoadResult {
        ChatRoomMediaLoadResult(items: items, hasMore: hasMoreAvailable)
    }

    private func makeMediaItem(from entry: ChatRoomMediaIndexEntry) -> ChatRoomSettingMediaItem {
        ChatRoomSettingMediaItem(
            messageID: entry.messageID,
            idx: entry.idx,
            thumbKey: entry.thumbKey,
            originalKey: entry.originalKey,
            thumbURL: entry.thumbURL,
            originalURL: entry.originalURL,
            localThumb: nil,
            sentAt: entry.sentAt,
            isVideo: entry.type == .video
        )
    }
}
