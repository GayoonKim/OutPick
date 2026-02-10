//
//  RoomSearchViewModel.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import Foundation

@MainActor
final class RoomSearchViewModel {
    struct State: Equatable {
        var recentSearches: [String] = []
        var searchResults: [ChatRoom] = []
        var isRecentSearchEnabled: Bool = true
        var errorMessage: String?
    }

    private enum Keys {
        static let recentSearches = "recentSearches"
        static let isRecentSearchEnabled = "isRecentSearchEnabled"
    }

    private let useCase: RoomSearchUseCaseProtocol
    private let userDefaults: UserDefaults

    private(set) var state: State {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?

    init(
        useCase: RoomSearchUseCaseProtocol,
        userDefaults: UserDefaults = .standard
    ) {
        self.useCase = useCase
        self.userDefaults = userDefaults
        self.state = State()
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

    func search(keyword: String, reset: Bool = true) async {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            state.searchResults = []
            state.errorMessage = nil
            return
        }

        do {
            state.searchResults = try await useCase.searchRooms(keyword: text, limit: 30, reset: reset)
            state.errorMessage = nil
        } catch {
            state.errorMessage = "검색에 실패했습니다."
            state.searchResults = []
        }
    }

    func loadMore() async {
        do {
            let more = try await useCase.loadMoreSearchRooms(limit: 30)
            state.searchResults.append(contentsOf: more)
            state.errorMessage = nil
        } catch {
            state.errorMessage = "추가 검색 결과를 불러오지 못했습니다."
        }
    }

    func selectRecentSearch(at index: Int) -> String? {
        guard state.recentSearches.indices.contains(index) else { return nil }
        let text = state.recentSearches[index]
        recordRecentSearch(text)
        return text
    }

    func notifyCurrentState() {
        onStateChanged?(state)
    }
}
