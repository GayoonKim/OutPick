//
//  RoomSearchViewModelTests.swift
//  OutPickTests
//
//  Created by Codex on 6/30/26.
//

import Foundation
import Testing
@testable import OutPick

struct RoomSearchViewModelTests {
    @MainActor
    @Test func latestSearchResultWinsWhenQueriesChangeQuickly() async throws {
        let firstRoom = makeRoom(id: "room-a", name: "Alpha")
        let latestRoom = makeRoom(id: "room-ab", name: "Alpha Beta")
        let useCase = RoomSearchUseCaseSpy()
        useCase.searchHandler = { keyword, _, _ in
            if keyword == "a" {
                try await Task.sleep(nanoseconds: 200_000_000)
                return RoomSearchPage(rooms: [firstRoom], hasMore: false)
            }
            return RoomSearchPage(rooms: [latestRoom], hasMore: false)
        }
        let viewModel = RoomSearchViewModel(useCase: useCase)

        viewModel.submitSearchText("a")
        viewModel.submitSearchText("ab")

        try await waitUntil {
            viewModel.state.searchResults.map(\.ID) == ["room-ab"]
        }
        #expect(viewModel.state.query == "ab")
        #expect(viewModel.state.isLoading == false)
        #expect(viewModel.state.errorMessage == nil)
    }

    @MainActor
    @Test func emptyQueryClearsSearchState() async throws {
        let room = makeRoom(id: "room-1", name: "Denim")
        let useCase = RoomSearchUseCaseSpy()
        useCase.searchHandler = { _, _, _ in
            RoomSearchPage(rooms: [room], hasMore: true)
        }
        let viewModel = RoomSearchViewModel(useCase: useCase)

        viewModel.submitSearchText("denim")
        try await waitUntil {
            viewModel.state.searchResults.map(\.ID) == ["room-1"]
        }
        viewModel.submitSearchText(" ")

        #expect(viewModel.state.query == "")
        #expect(viewModel.state.searchResults.isEmpty)
        #expect(viewModel.state.isLoading == false)
        #expect(viewModel.state.isLoadingMore == false)
        #expect(viewModel.state.hasMore == false)
        #expect(viewModel.state.hasSearched == false)
    }

    @MainActor
    @Test func loadMoreDeduplicatesRoomsAndIgnoresConcurrentRequests() async throws {
        let firstRoom = makeRoom(id: "room-1", name: "Minimal")
        let secondRoom = makeRoom(id: "room-2", name: "Street")
        let useCase = RoomSearchUseCaseSpy()
        useCase.searchHandler = { _, _, _ in
            RoomSearchPage(rooms: [firstRoom], hasMore: true)
        }
        useCase.loadMoreHandler = { _ in
            try await Task.sleep(nanoseconds: 100_000_000)
            return RoomSearchPage(rooms: [firstRoom, secondRoom], hasMore: false)
        }
        let viewModel = RoomSearchViewModel(useCase: useCase)

        viewModel.submitSearchText("style")
        try await waitUntil {
            viewModel.state.searchResults.map(\.ID) == ["room-1"]
        }

        viewModel.loadMore()
        viewModel.loadMore()

        try await waitUntil {
            viewModel.state.searchResults.map(\.ID) == ["room-1", "room-2"]
        }
        #expect(useCase.loadMoreRequests.count == 1)
        #expect(viewModel.state.hasMore == false)
        #expect(viewModel.state.isLoadingMore == false)
    }
}

struct ChatRoomSearchIndexTests {
    @MainActor
    @Test func koreanRoomNameMatchesSingleCharacterAndPrefixQueries() {
        let room = makeRoom(id: "hatching-room", name: "해칭룸 룩북 공유방")

        #expect(ChatRoomSearchIndex.queryToken(for: "해")?.field == "roomSearchChars")
        #expect(ChatRoomSearchIndex.queryToken(for: "해")?.token == "해")
        #expect(ChatRoomSearchIndex.queryToken(for: "해칭")?.field == "roomSearchNgrams2")
        #expect(ChatRoomSearchIndex.queryToken(for: "해칭")?.token == "해칭")
        #expect(ChatRoomSearchIndex.contains(room: room, keyword: "해"))
        #expect(ChatRoomSearchIndex.contains(room: room, keyword: "해칭"))
        #expect(ChatRoomSearchIndex.contains(room: room, keyword: "해칭룸"))
    }
}

@MainActor
private func makeRoom(id: String, name: String, description: String = "") -> ChatRoom {
    ChatRoom(
        ID: id,
        roomName: name,
        roomDescription: description,
        participants: [],
        creatorUID: "owner@example.com",
        createdAt: Date(timeIntervalSince1970: 0),
        thumbPath: nil,
        originalPath: nil,
        lastMessageAt: Date(timeIntervalSince1970: 10),
        lastMessage: nil,
        lastMessageSenderUID: nil
    )
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(TimeInterval(timeoutNanoseconds) / 1_000_000_000)
    while !condition() {
        if Date() >= deadline {
            Issue.record("조건을 시간 안에 만족하지 못했습니다.")
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

private final class RoomSearchUseCaseSpy: RoomSearchUseCaseProtocol {
    var searchRequests: [(keyword: String, limit: Int, reset: Bool)] = []
    var loadMoreRequests: [Int] = []

    var searchHandler: (String, Int, Bool) async throws -> RoomSearchPage = { _, _, _ in
        RoomSearchPage(rooms: [], hasMore: false)
    }
    var loadMoreHandler: (Int) async throws -> RoomSearchPage = { _ in
        RoomSearchPage(rooms: [], hasMore: false)
    }

    func searchRooms(keyword: String, limit: Int, reset: Bool) async throws -> RoomSearchPage {
        searchRequests.append((keyword, limit, reset))
        return try await searchHandler(keyword, limit, reset)
    }

    func loadMoreSearchRooms(limit: Int) async throws -> RoomSearchPage {
        loadMoreRequests.append(limit)
        return try await loadMoreHandler(limit)
    }
}
