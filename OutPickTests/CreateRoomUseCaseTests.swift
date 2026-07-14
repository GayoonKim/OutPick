//
//  CreateRoomUseCaseTests.swift
//  OutPickTests
//
//  Created by Codex on 7/14/26.
//

import Foundation
import Testing
import UIKit
@testable import OutPick

private typealias ChatAttachment = OutPick.Attachment

struct CreateRoomUseCaseTests {
    @MainActor
    @Test func emitsRepositoryReturnedRoomOnlyAfterCreateSucceeds() async throws {
        let repository = CreateRoomRepositoryFake()
        repository.createdRoom = makeCreatedRoom(id: "repository-room-id")
        let useCase = makeUseCase(repository: repository)
        var events: [CreateRoomUseCaseEvent] = []

        try await useCase.execute(roomName: "Room", roomDescription: "Desc", imagePair: nil) {
            events.append($0)
        }

        #expect(repository.inputs.count == 1)
        #expect(repository.inputs.first?.creatorUID == "owner-1")
        #expect(events.count == 2)
        if case let .presentCreatedRoom(room) = events[0] {
            #expect(room.id == "repository-room-id")
        } else {
            Issue.record("첫 이벤트가 생성 방 표시 이벤트가 아닙니다.")
        }
        if case let .roomSaveCompleted(room) = events[1] {
            #expect(room.id == "repository-room-id")
        } else {
            Issue.record("두 번째 이벤트가 저장 완료 이벤트가 아닙니다.")
        }
    }

    @MainActor
    @Test func duplicateNamePreventsCreate() async {
        let repository = CreateRoomRepositoryFake()
        repository.isDuplicate = true
        let useCase = makeUseCase(repository: repository)

        do {
            try await useCase.execute(roomName: "Room", roomDescription: "", imagePair: nil) { _ in }
            Issue.record("중복 방 이름이 성공 처리되었습니다.")
        } catch RoomCreationError.duplicateName {
            #expect(repository.inputs.isEmpty)
        } catch {
            Issue.record("예상하지 못한 오류: \(error)")
        }
    }

    @MainActor
    @Test func createFailureMapsToSaveFailedAndEmitsNoEvent() async {
        let repository = CreateRoomRepositoryFake()
        repository.createError = TestFailure.create
        let useCase = makeUseCase(repository: repository)
        var eventCount = 0

        do {
            try await useCase.execute(roomName: "Room", roomDescription: "", imagePair: nil) { _ in
                eventCount += 1
            }
            Issue.record("Repository 실패가 성공 처리되었습니다.")
        } catch RoomCreationError.saveFailed {
            #expect(eventCount == 0)
        } catch {
            Issue.record("예상하지 못한 오류: \(error)")
        }
    }

    @MainActor
    private func makeUseCase(repository: CreateRoomRepositoryFake) -> CreateRoomUseCase {
        CreateRoomUseCase(
            chatRoomRepository: repository,
            imageStorageRepository: CreateRoomImageStorageFake(),
            roomImageManager: CreateRoomImageManagerFake(),
            currentUserUIDProvider: { "owner-1" }
        )
    }

    private func makeCreatedRoom(id: String) -> ChatRoom {
        ChatRoom(
            id: id,
            roomName: "Room",
            roomDescription: "Desc",
            participants: ["owner-1"],
            creatorUID: "owner-1",
            createdAt: Date(timeIntervalSince1970: 100),
            memberCount: 1
        )
    }
}

private enum TestFailure: Error {
    case create
    case unused
}

private final class CreateRoomRepositoryFake: CreateRoomRepositoryProtocol {
    var isDuplicate = false
    var createdRoom: ChatRoom?
    var createError: Error?
    private(set) var inputs: [CreateChatRoomInput] = []

    func checkRoomNameDuplicate(roomName: String) async throws -> Bool { isDuplicate }

    func createRoom(input: CreateChatRoomInput) async throws -> ChatRoom {
        inputs.append(input)
        if let createError { throw createError }
        return createdRoom ?? ChatRoom(
            id: "room-1",
            roomName: input.roomName,
            roomDescription: input.roomDescription,
            participants: [input.creatorUID],
            creatorUID: input.creatorUID,
            createdAt: input.createdAt,
            memberCount: 1
        )
    }

    func updateRoomMetadataWithImagePaths(
        roomID: String,
        roomName: String,
        roomDescription: String,
        thumbPath: String,
        originalPath: String
    ) async throws {}

    func applyLocalRoomUpdate(_ updatedRoom: ChatRoom) {}
}

private final class CreateRoomImageStorageFake: FirebaseImageStorageRepositoryProtocol {
    func uploadImage(
        sha: String,
        uid: String,
        type: ImageLocation,
        thumbData: Data,
        originalFileURL: URL,
        contentType: String
    ) async throws -> (avatarThumbPath: String, avatarPath: String) { throw TestFailure.unused }

    func uploadPairsToRoomMessage(
        _ pairs: [ProcessedImage],
        roomID: String,
        messageID: String,
        cacheTTLThumbDays: Int,
        cacheTTLOriginalDays: Int,
        cleanupTemp: Bool,
        onProgress: ((Double) -> Void)?
    ) async throws -> [ChatAttachment] { throw TestFailure.unused }

    func fetchImageDataFromStorage(image: String, location: ImageLocation, maxBytes: Int) async throws -> Data { throw TestFailure.unused }
    func fetchImageFromStorage(image: String, location: ImageLocation) async throws -> UIImage { throw TestFailure.unused }
    func fetchImagesFromStorage(from imagePaths: [String], location: ImageLocation, createdDate: Date) async throws -> [UIImage] { throw TestFailure.unused }
    func prefetchImages(paths: [String], location: ImageLocation, createdDate: Date) {}
    func deleteImageFromStorage(path: String) {}
    func setDataFallbackLimitMB(_ mb: Int) {}
}

private final class CreateRoomImageManagerFake: RoomImageManaging {
    func cachedImage(for path: String) async -> UIImage? { nil }
    func loadImage(for path: String, maxBytes: Int) async throws -> UIImage { throw TestFailure.unused }
    func prefetchImages(paths: [String], maxBytes: Int, maxConcurrent: Int) async {}
    func storeImageDataToCache(_ data: Data, for path: String) async throws {}
    func removeCachedImage(for path: String) async {}
}
