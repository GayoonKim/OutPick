//
//  RoomSearchViewModel.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import Foundation
import Combine

@MainActor
final class RoomSearchViewModel {
    struct State: Equatable {
        var query: String = ""
        var recentSearches: [String] = []
        var searchResults: [ChatRoom] = []
        var isRecentSearchEnabled: Bool = true
        var isLoading: Bool = false
        var isLoadingMore: Bool = false
        var hasMore: Bool = false
        var hasSearched: Bool = false
        var errorMessage: String?
    }

    private enum Keys {
        static let recentSearches = "recentSearches"
        static let isRecentSearchEnabled = "isRecentSearchEnabled"
    }

    private let useCase: RoomSearchUseCaseProtocol
    private let userDefaults: UserDefaults
    private let pageSize: Int
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var searchGeneration: Int = 0

    @Published private(set) var state: State
    var statePublisher: AnyPublisher<State, Never> {
        $state.eraseToAnyPublisher()
    }

    var searchTextDebounce: RunLoop.SchedulerTimeType.Stride = .milliseconds(300)

    init(
        useCase: RoomSearchUseCaseProtocol,
        userDefaults: UserDefaults = .standard,
        pageSize: Int = 30
    ) {
        self.useCase = useCase
        self.userDefaults = userDefaults
        self.pageSize = pageSize
        self.state = State()
    }

    deinit {
        searchTask?.cancel()
        loadMoreTask?.cancel()
    }

    func bindSearchTextPublisher(_ publisher: AnyPublisher<String, Never>) {
        cancellables.removeAll()
        publisher
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .debounce(for: searchTextDebounce, scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                self?.submitSearchText(text)
            }
            .store(in: &cancellables)
    }

    func loadInitialState() {
        state.isRecentSearchEnabled = userDefaults.object(forKey: Keys.isRecentSearchEnabled) as? Bool ?? true
        state.recentSearches = userDefaults.stringArray(forKey: Keys.recentSearches) ?? []
    }

    func setRecentSearchEnabled(_ enabled: Bool) {
        state.isRecentSearchEnabled = enabled
        userDefaults.set(enabled, forKey: Keys.isRecentSearchEnabled)

        if !enabled {
            state.recentSearches = []
            userDefaults.removeObject(forKey: Keys.recentSearches)
        }
    }

    func removeRecentSearch(at index: Int) {
        guard state.recentSearches.indices.contains(index) else { return }
        state.recentSearches.remove(at: index)
        userDefaults.set(state.recentSearches, forKey: Keys.recentSearches)
    }

    func recordRecentSearch(_ keyword: String) {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state.isRecentSearchEnabled, !text.isEmpty else { return }

        if let idx = state.recentSearches.firstIndex(of: text) {
            state.recentSearches.remove(at: idx)
        }
        state.recentSearches.insert(text, at: 0)
        userDefaults.set(state.recentSearches, forKey: Keys.recentSearches)
    }

    func submitSearchText(_ keyword: String) {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            clearSearch()
            return
        }

        searchTask?.cancel()
        loadMoreTask?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration

        state.query = text
        state.isLoading = true
        state.isLoadingMore = false
        state.hasSearched = true
        state.hasMore = false
        state.errorMessage = nil

        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.useCase.searchRooms(
                    keyword: text,
                    limit: self.pageSize,
                    reset: true
                )
                try Task.checkCancellation()
                guard self.searchGeneration == generation else { return }

                self.state.searchResults = self.uniqueRooms(page.rooms)
                self.state.hasMore = page.hasMore
                self.state.isLoading = false
                self.state.errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard self.searchGeneration == generation else { return }
                self.state.searchResults = []
                self.state.hasMore = false
                self.state.isLoading = false
                self.state.errorMessage = "검색에 실패했습니다."
            }
        }
    }

    func loadMore() {
        guard !state.query.isEmpty,
              state.hasMore,
              !state.isLoading,
              !state.isLoadingMore else { return }

        loadMoreTask?.cancel()
        let generation = searchGeneration
        state.isLoadingMore = true
        state.errorMessage = nil

        loadMoreTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.useCase.loadMoreSearchRooms(limit: self.pageSize)
                try Task.checkCancellation()
                guard self.searchGeneration == generation else { return }

                self.state.searchResults = self.uniqueRooms(self.state.searchResults + page.rooms)
                self.state.hasMore = page.hasMore
                self.state.isLoadingMore = false
                self.state.errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard self.searchGeneration == generation else { return }
                self.state.isLoadingMore = false
                self.state.errorMessage = "추가 검색 결과를 불러오지 못했습니다."
            }
        }
    }

    func selectRecentSearch(at index: Int) -> String? {
        guard state.recentSearches.indices.contains(index) else { return nil }
        let text = state.recentSearches[index]
        recordRecentSearch(text)
        return text
    }

    func notifyCurrentState() {
        state = state
    }

    private func clearSearch() {
        searchTask?.cancel()
        loadMoreTask?.cancel()
        searchGeneration &+= 1
        state.query = ""
        state.searchResults = []
        state.isLoading = false
        state.isLoadingMore = false
        state.hasMore = false
        state.hasSearched = false
        state.errorMessage = nil
    }

    private func uniqueRooms(_ rooms: [ChatRoom]) -> [ChatRoom] {
        var seen = Set<String>()
        var unique: [ChatRoom] = []
        unique.reserveCapacity(rooms.count)

        for room in rooms {
            let key = room.id
            if seen.insert(key).inserted {
                unique.append(room)
            }
        }
        return unique
    }
}
