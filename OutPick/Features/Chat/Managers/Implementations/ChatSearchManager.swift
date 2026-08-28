//
//  ChatSearchManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation

final class ChatSearchManager: ChatSearchManaging {
    private let messageSearch: ChatMessageSearching
    private let messageRepository: FirebaseMessageRepositoryProtocol
    private let networkStatusProvider: NetworkStatusProviding
    private let deletionSanitizer: ChatDeletionMessageSanitizing?
    private let currentAccountID: @Sendable () -> String
    
    init(
        messageSearch: ChatMessageSearching,
        messageRepository: FirebaseMessageRepositoryProtocol = FirebaseRepositoryProvider.shared.messageRepository,
        networkStatusProvider: NetworkStatusProviding? = nil,
        deletionSanitizer: ChatDeletionMessageSanitizing? = nil,
        currentAccountID: @escaping @Sendable () -> String = { LoginManager.shared.canonicalUserID }
    ) {
        self.messageSearch = messageSearch
        self.messageRepository = messageRepository
        self.deletionSanitizer = deletionSanitizer
        self.currentAccountID = currentAccountID

        if let networkStatusProvider {
            self.networkStatusProvider = networkStatusProvider
        } else {
            let provider = NWPathNetworkStatusProvider()
            provider.startMonitoring()
            self.networkStatusProvider = provider
        }
    }
    
    func searchMessages(roomID: String, keyword: String) async throws -> ChatMessageSearchResult {
        if networkStatusProvider.currentStatus.isOnline {
            do {
                let server = try await messageRepository.searchMessagesInRoom(roomID: roomID, keyword: keyword)
                let sanitizedMessages = try await sanitize(
                    server.hits.map(\.message),
                    roomID: roomID
                )
                let hits: [ChatMessageSearchHit] = zip(server.hits, sanitizedMessages).compactMap { pair in
                    let (hit, message) = pair
                    guard !message.isDeleted else { return nil }
                    return ChatMessageSearchHit(message: message, snippet: hit.snippet)
                }
                return ChatMessageSearchResult(
                    keyword: keyword,
                    totalCount: hits.count,
                    hits: hits,
                    source: .serverIndex,
                    isAuthoritative: true
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let localHits = try await loadLocalHits(roomID: roomID, keyword: keyword)
                return ChatMessageSearchResult(
                    keyword: keyword,
                    totalCount: localHits.count,
                    hits: localHits,
                    source: .localFallbackAfterServerFailure,
                    isAuthoritative: false
                )
            }
        }

        let localHits = try await loadLocalHits(roomID: roomID, keyword: keyword)
        return ChatMessageSearchResult(
            keyword: keyword,
            totalCount: localHits.count,
            hits: localHits,
            source: .localOffline,
            isAuthoritative: false
        )
    }

    private func loadLocalHits(roomID: String, keyword: String) async throws -> [ChatMessageSearchHit] {
        let messages = try await messageSearch.fetchMessages(in: roomID, containing: keyword)
        return messages.map { message in
            ChatMessageSearchHit(message: message, snippet: message.msg)
        }
    }

    private func sanitize(_ messages: [ChatMessage], roomID: String) async throws -> [ChatMessage] {
        guard let deletionSanitizer else { return messages }
        return try await deletionSanitizer.sanitize(
            messages,
            accountID: currentAccountID(),
            roomID: roomID
        )
    }
    
    func applyHighlight(messageIDs: Set<String>) -> Set<String> {
        return messageIDs
    }
    
    func clearHighlight() -> Set<String> {
        return []
    }
}
