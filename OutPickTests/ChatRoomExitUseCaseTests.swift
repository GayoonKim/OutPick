//
//  ChatRoomExitUseCaseTests.swift
//  OutPickTests
//
//  Created by Codex on 6/18/26.
//

import Foundation
import Testing
@testable import OutPick

struct ChatRoomExitUseCaseTests {
    @Test func leaveOrCloseCleansLocalDataAfterLeftSuccess() async throws {
        let repository = ChatRoomExitRepositoryFake(result: ChatRoomExitResult(roomID: "room-1", mode: .left))
        let cleaner = ChatRoomLocalExitCleanerSpy()
        let useCase = ChatRoomExitUseCase(repository: repository, localCleaner: cleaner)

        let result = try await useCase.leaveOrClose(room: makeRoom(id: "room-1"))

        #expect(result == ChatRoomExitResult(roomID: "room-1", mode: .left))
        #expect(repository.requestedRoomIDs == ["room-1"])
        #expect(cleaner.cleanedRoomIDs == ["room-1"])
    }

    @Test func leaveOrCloseCleansLocalDataAfterClosedSuccess() async throws {
        let repository = ChatRoomExitRepositoryFake(result: ChatRoomExitResult(roomID: "room-1", mode: .closed))
        let cleaner = ChatRoomLocalExitCleanerSpy()
        let useCase = ChatRoomExitUseCase(repository: repository, localCleaner: cleaner)

        let result = try await useCase.leaveOrClose(room: makeRoom(id: "room-1"))

        #expect(result == ChatRoomExitResult(roomID: "room-1", mode: .closed))
        #expect(cleaner.cleanedRoomIDs == ["room-1"])
    }

    @Test func leaveOrCloseSkipsLocalCleanupWhenServerFails() async {
        let repository = ChatRoomExitRepositoryFake(error: ExitTestError.server)
        let cleaner = ChatRoomLocalExitCleanerSpy()
        let useCase = ChatRoomExitUseCase(repository: repository, localCleaner: cleaner)

        do {
            _ = try await useCase.leaveOrClose(room: makeRoom(id: "room-1"))
            Issue.record("Expected server failure")
        } catch {
            #expect(error as? ExitTestError == .server)
        }

        #expect(cleaner.cleanedRoomIDs.isEmpty)
    }

    @Test func leaveOrCloseSucceedsWhenLocalCleanupFails() async throws {
        let repository = ChatRoomExitRepositoryFake(result: ChatRoomExitResult(roomID: "room-1", mode: .left))
        let cleaner = ChatRoomLocalExitCleanerSpy(error: ExitTestError.localCleanup)
        let useCase = ChatRoomExitUseCase(repository: repository, localCleaner: cleaner)

        let result = try await useCase.leaveOrClose(room: makeRoom(id: "room-1"))

        #expect(result == ChatRoomExitResult(roomID: "room-1", mode: .left))
        #expect(cleaner.cleanedRoomIDs == ["room-1"])
    }

    @Test func leaveOrCloseRejectsMissingRoomID() async {
        let repository = ChatRoomExitRepositoryFake(result: ChatRoomExitResult(roomID: "room-1", mode: .left))
        let cleaner = ChatRoomLocalExitCleanerSpy()
        let useCase = ChatRoomExitUseCase(repository: repository, localCleaner: cleaner)

        do {
            _ = try await useCase.leaveOrClose(room: makeRoom(id: "   "))
            Issue.record("Expected missing room ID failure")
        } catch {
            #expect(error as? ChatRoomExitError == .missingRoomID)
        }

        #expect(repository.requestedRoomIDs.isEmpty)
        #expect(cleaner.cleanedRoomIDs.isEmpty)
    }

    private func makeRoom(id: String) -> ChatRoom {
        ChatRoom(
            id: id,
            roomName: "Test Room",
            roomDescription: "Test Description",
            participants: ["me@example.com"],
            creatorUID: "owner@example.com",
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
}

private final class ChatRoomExitRepositoryFake: ChatRoomExitRepositoryProtocol {
    private let result: ChatRoomExitResult?
    private let error: Error?
    private(set) var requestedRoomIDs: [String] = []

    init(result: ChatRoomExitResult? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func leaveOrClose(roomID: String) async throws -> ChatRoomExitResult {
        requestedRoomIDs.append(roomID)
        if let error {
            throw error
        }
        return result ?? ChatRoomExitResult(roomID: roomID, mode: .unknown(nil))
    }
}

private final class ChatRoomLocalExitCleanerSpy: ChatRoomLocalExitCleaning {
    private let error: Error?
    private(set) var cleanedRoomIDs: [String] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func cleanLocalRoomDataAfterExit(roomID: String) async throws {
        cleanedRoomIDs.append(roomID)
        if let error {
            throw error
        }
    }
}

private enum ExitTestError: Error, Equatable {
    case server
    case localCleanup
}
