//
//  ChatRoomSettingViewModel.swift
//  OutPick
//
//  Created by Codex on 3/7/26.
//

import Foundation
import UIKit
import Combine

@MainActor
final class ChatRoomSettingViewModel {
    struct GalleryItemModel {
        let id: String
        let image: UIImage
        let isVideo: Bool
        let sentAt: Date
        let thumbnailPath: String?
        let originalPath: String?
        let videoPath: String?
    }

    private struct MaterializedMedia {
        let item: ChatRoomSettingMediaItem
        let image: UIImage
    }

    @Published private(set) var roomInfo: ChatRoom
    @Published private(set) var mediaItems: [ChatRoomSettingMediaItem]
    @Published private(set) var localUsers: [LocalUser]

    var participantsHasMore: Bool { participantsHasMoreStorage }
    var participantsIsLoading: Bool { participantsIsLoadingStorage }
    var mediaHasMore: Bool { mediaHasMoreStorage }
    var mediaIsLoading: Bool { mediaIsLoadingStorage }

    private let loadParticipantsUseCase: LoadChatRoomParticipantsUseCaseProtocol
    private let loadMediaUseCase: LoadChatRoomMediaUseCaseProtocol
    private let mediaManager: ChatMediaManaging
    private let avatarImageManager: ChatAvatarImageManaging
    private let networkStatusProvider: NetworkStatusProviding
    private let mediaThumbMaxBytes = 12 * 1024 * 1024
    private let avatarPrefetchMaxBytes = 3 * 1024 * 1024

    private var participantsIsLoadingStorage: Bool
    private var participantsHasMoreStorage: Bool

    private var mediaIsLoadingStorage: Bool = false
    private var mediaHasMoreStorage: Bool = false
    private var galleryItemsByID: [String: GalleryItemModel] = [:]

    init(
        room: ChatRoom,
        initialParticipants: ChatRoomParticipantsLoadResult,
        mediaManager: ChatMediaManaging,
        avatarImageManager: ChatAvatarImageManaging,
        loadParticipantsUseCase: LoadChatRoomParticipantsUseCaseProtocol,
        loadMediaUseCase: LoadChatRoomMediaUseCaseProtocol,
        networkStatusProvider: NetworkStatusProviding
    ) {
        self.roomInfo = room
        self.mediaItems = []
        self.localUsers = initialParticipants.users
        self.participantsIsLoadingStorage = true
        self.participantsHasMoreStorage = initialParticipants.hasMore
        self.mediaManager = mediaManager
        self.avatarImageManager = avatarImageManager
        self.loadParticipantsUseCase = loadParticipantsUseCase
        self.loadMediaUseCase = loadMediaUseCase
        self.networkStatusProvider = networkStatusProvider
    }

    func updateRoomInfo(_ room: ChatRoom) {
        roomInfo = room
    }

    func loadInitialParticipants() async {
        participantsIsLoadingStorage = true
        defer { participantsIsLoadingStorage = false }

        do {
            let room = roomInfo
            let localResult = try loadParticipantsUseCase.loadLocalInitial(room: room)
            participantsHasMoreStorage = localResult.hasMore
            localUsers = localResult.users
            scheduleAvatarPrefetch(for: localResult.users)

            guard networkStatusProvider.currentStatus.isOnline else { return }

            let reconciledResult = try await loadParticipantsUseCase.reconcileInitial(room: room)
            participantsHasMoreStorage = reconciledResult.hasMore
            localUsers = reconciledResult.users
            scheduleAvatarPrefetch(for: reconciledResult.users)
        } catch {
            print("❌ 초기 참여자 로드 실패:", error)
        }
    }

    func loadMoreParticipantsIfNeeded() async {
        guard participantsHasMoreStorage, !participantsIsLoadingStorage else { return }
        participantsIsLoadingStorage = true
        defer { participantsIsLoadingStorage = false }

        do {
            let result = try await loadParticipantsUseCase.loadMore(room: roomInfo)
            participantsHasMoreStorage = result.hasMore

            if !result.users.isEmpty {
                localUsers.append(contentsOf: result.users)
                scheduleAvatarPrefetch(for: result.users)
            }
        } catch {
            print("❌ 참여자 추가 로드 실패:", error)
        }
    }

    func loadInitialMedia() async {
        guard !mediaIsLoadingStorage else { return }
        mediaIsLoadingStorage = true
        defer { mediaIsLoadingStorage = false }

        do {
            let result = try await loadMediaUseCase.loadInitial(room: roomInfo)
            let uniqueItems = Self.uniqueMediaItems(from: result.items)
            mediaItems = uniqueItems
            syncGalleryCache(with: uniqueItems)
            mediaHasMoreStorage = result.hasMore
        } catch {
            mediaHasMoreStorage = false
            print("❌ 초기 미디어 로드 실패:", error)
        }
    }

    func loadMoreMediaIfNeeded() async {
        guard mediaHasMoreStorage, !mediaIsLoadingStorage else { return }
        mediaIsLoadingStorage = true
        defer { mediaIsLoadingStorage = false }

        do {
            let result = try await loadMediaUseCase.loadMore(room: roomInfo)
            mediaHasMoreStorage = result.hasMore

            guard !result.items.isEmpty else { return }

            mediaItems = Self.mergeMediaItems(existing: mediaItems, appending: result.items)
            syncGalleryCache(with: mediaItems)
        } catch {
            print("❌ 미디어 추가 로드 실패:", error)
        }
    }

    func thumbnailImage(for item: ChatRoomSettingMediaItem) async -> UIImage? {
        if let cached = galleryItemsByID[item.id] {
            return cached.image
        }

        guard let materialized = await materializeMediaThumb(for: item) else {
            return nil
        }

        let galleryItem = Self.makeGalleryItem(from: materialized)
        galleryItemsByID[item.id] = galleryItem
        return galleryItem.image
    }

    func buildGalleryItems() async -> [GalleryItemModel] {
        let items = mediaItems
        let missingItems = items.filter { galleryItemsByID[$0.id] == nil }

        if !missingItems.isEmpty {
            let materialized = await materializeMediaThumbs(for: missingItems)
            for media in materialized {
                galleryItemsByID[media.item.id] = Self.makeGalleryItem(from: media)
            }
        }

        return items.compactMap { galleryItemsByID[$0.id] }
    }

    private func materializeMediaThumbs(for items: [ChatRoomSettingMediaItem]) async -> [MaterializedMedia] {
        guard !items.isEmpty else { return [] }

        return await withTaskGroup(of: (Int, MaterializedMedia?).self, returning: [MaterializedMedia].self) { group in
            for (index, item) in items.enumerated() {
                group.addTask { [weak self] in
                    guard let self else { return (index, nil) }
                    let materialized = await self.materializeMediaThumb(for: item)
                    return (index, materialized)
                }
            }

            var ordered = Array<MaterializedMedia?>(repeating: nil, count: items.count)
            for await (index, materialized) in group {
                ordered[index] = materialized
            }
            return ordered.compactMap { $0 }
        }
    }

    private func materializeMediaThumb(for item: ChatRoomSettingMediaItem) async -> MaterializedMedia? {
        for path in item.previewPaths {
            if let image = await mediaManager.cachedImage(for: path) {
                let composed = item.isVideo ? Self.drawPlayBadge(on: image) : image
                return MaterializedMedia(item: item, image: composed)
            }
        }

        for path in item.previewPaths {
            do {
                let image = try await mediaManager.loadImage(for: path, maxBytes: mediaThumbMaxBytes)
                let composed = item.isVideo ? Self.drawPlayBadge(on: image) : image
                return MaterializedMedia(item: item, image: composed)
            } catch {
                continue
            }
        }

        return nil
    }

    private func syncGalleryCache(with items: [ChatRoomSettingMediaItem]) {
        let validIDs = Set(items.map(\.id))
        galleryItemsByID = galleryItemsByID.filter { validIDs.contains($0.key) }
    }

    private func scheduleAvatarPrefetch(for users: [LocalUser]) {
        guard !users.isEmpty else { return }

        Task(priority: .utility) { [weak self] in
            await self?.prefetchProfileAvatars(for: users, topCount: users.count)
        }
    }

    private func prefetchProfileAvatars(for users: [LocalUser], topCount: Int = 50) async {
        guard !users.isEmpty else { return }

        let sorted = users.sorted {
            $0.nickname.localizedCaseInsensitiveCompare($1.nickname) == .orderedAscending
        }
        let slice = sorted.prefix(min(topCount, sorted.count))
        let paths = Array(Set(slice.compactMap(\.profileImagePath).filter { !$0.isEmpty }))
        guard !paths.isEmpty else { return }

        await avatarImageManager.prefetchAvatars(
            paths: paths,
            maxBytes: avatarPrefetchMaxBytes,
            maxConcurrent: 4
        )
    }

    private static func makeGalleryItem(from media: MaterializedMedia) -> GalleryItemModel {
        return GalleryItemModel(
            id: media.item.id,
            image: media.image,
            isVideo: media.item.isVideo,
            sentAt: media.item.sentAt,
            thumbnailPath: media.item.thumbnailPath,
            originalPath: media.item.originalPath,
            videoPath: media.item.videoPath
        )
    }

    private static func mergeMediaItems(
        existing: [ChatRoomSettingMediaItem],
        appending incoming: [ChatRoomSettingMediaItem]
    ) -> [ChatRoomSettingMediaItem] {
        uniqueMediaItems(from: existing + incoming)
    }

    private static func uniqueMediaItems(from items: [ChatRoomSettingMediaItem]) -> [ChatRoomSettingMediaItem] {
        var knownIDs = Set<String>()
        var knownContentKeys = Set<String>()

        return items.filter { item in
            guard knownIDs.insert(item.id).inserted else { return false }

            let dedupeKeys = item.dedupeKeys
            if !dedupeKeys.isEmpty {
                guard knownContentKeys.isDisjoint(with: dedupeKeys) else { return false }
                knownContentKeys.formUnion(dedupeKeys)
            }

            return true
        }
    }

    private static func drawPlayBadge(on image: UIImage) -> UIImage {
        let scale = image.scale
        let size = image.size
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        image.draw(in: CGRect(origin: .zero, size: size))

        let minSide = min(size.width, size.height)
        let circleDiameter = minSide * 0.28
        let circleRect = CGRect(
            x: (size.width - circleDiameter) / 2,
            y: (size.height - circleDiameter) / 2,
            width: circleDiameter,
            height: circleDiameter
        )

        let circlePath = UIBezierPath(ovalIn: circleRect)
        UIColor.black.withAlphaComponent(0.35).setFill()
        circlePath.fill()

        let triSide = circleDiameter * 0.5
        let triHeight = triSide * sqrt(3) / 2
        let center = CGPoint(x: circleRect.midX, y: circleRect.midY)
        let triPath = UIBezierPath()
        triPath.move(to: CGPoint(x: center.x - triSide * 0.25, y: center.y - triHeight / 2))
        triPath.addLine(to: CGPoint(x: center.x - triSide * 0.25, y: center.y + triHeight / 2))
        triPath.addLine(to: CGPoint(x: center.x + triSide * 0.5, y: center.y))
        triPath.close()
        UIColor.white.withAlphaComponent(0.9).setFill()
        triPath.fill()

        let composed = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return composed ?? image
    }
}
