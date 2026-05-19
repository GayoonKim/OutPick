//
//  ChatSearchManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation

final class ChatSearchManager: ChatSearchManaging {
    private let grdbManager: GRDBManager
    private let messageRepository: FirebaseMessageRepositoryProtocol
    private let networkStatusProvider: NetworkStatusProviding
    
    init(
        grdbManager: GRDBManager = .shared,
        messageRepository: FirebaseMessageRepositoryProtocol = FirebaseRepositoryProvider.shared.messageRepository,
        networkStatusProvider: NetworkStatusProviding? = nil
    ) {
        self.grdbManager = grdbManager
        self.messageRepository = messageRepository

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
                return ChatMessageSearchResult(
                    keyword: keyword,
                    totalCount: server.totalCount,
                    hits: server.hits,
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
        let messages = try await grdbManager.fetchMessages(in: roomID, containing: keyword)
        return messages.map { message in
            ChatMessageSearchHit(message: message, snippet: message.msg)
        }
    }
    
    func applyHighlight(messageIDs: Set<String>) -> Set<String> {
        return messageIDs
    }
    
    func clearHighlight() -> Set<String> {
        return []
    }
}
