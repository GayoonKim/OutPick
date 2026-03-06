//
//  ChatInitialLoadUseCase.swift
//  OutPick
//
//  Created by Codex on 2/25/26.
//

import Foundation

enum ChatInitialLoadPhase: Equatable {
    case idle
    case checkingNetwork
    case loadingLocal
    case localVisible(isStale: Bool)
    case serverSyncing
    case offlineNoLocal
    case ready
    case failed(message: String)
}

enum ChatInitialLoadRenderCommand {
    case replaceLocal([ChatMessage])
    case appendServer([ChatMessage])
    case reloadDeleted([ChatMessage])
    case showCenteredMessage(String)
    case hideCenteredMessage
}

enum ChatInitialLoadEvent {
    case phaseChanged(ChatInitialLoadPhase)
    case render(ChatInitialLoadRenderCommand)
    case warmMedia(messages: [ChatMessage], maxConcurrent: Int)
    case seedHotUsers([ChatMessage])
    case participantSessionReady(bindRealtime: Bool)
    case completed
}

struct ChatInitialLoadPolicy: Equatable {
    let localRenderLimit: Int
    let serverInitialPageSize: Int
    let mediaPrefetchConcurrency: Int
}

protocol ChatInitialLoadPolicyResolving {
    func policy(for network: NetworkStatus) -> ChatInitialLoadPolicy
}

struct DefaultChatInitialLoadPolicyResolver: ChatInitialLoadPolicyResolving {
    func policy(for network: NetworkStatus) -> ChatInitialLoadPolicy {
        if !network.isOnline {
            return ChatInitialLoadPolicy(
                localRenderLimit: 200,
                serverInitialPageSize: 0,
                mediaPrefetchConcurrency: 1
            )
        }

        if network.isConstrained {
            return ChatInitialLoadPolicy(
                localRenderLimit: 200,
                serverInitialPageSize: 200,
                mediaPrefetchConcurrency: 2
            )
        }

        if network.isExpensive || network.accessClass == .cellular {
            return ChatInitialLoadPolicy(
                localRenderLimit: 200,
                serverInitialPageSize: 300,
                mediaPrefetchConcurrency: 3
            )
        }

        return ChatInitialLoadPolicy(
            localRenderLimit: 200,
            serverInitialPageSize: 500,
            mediaPrefetchConcurrency: 6
        )
    }
}

protocol ChatInitialLoadUseCaseProtocol {
    func execute(
        room: ChatRoom,
        isParticipant: Bool
    ) -> AsyncStream<ChatInitialLoadEvent>
}

final class DefaultChatInitialLoadUseCase: ChatInitialLoadUseCaseProtocol {
    private let messageManager: ChatMessageManaging
    private let networkStatusProvider: NetworkStatusProviding
    private let policyResolver: ChatInitialLoadPolicyResolving

    init(
        messageManager: ChatMessageManaging,
        networkStatusProvider: NetworkStatusProviding,
        policyResolver: ChatInitialLoadPolicyResolving = DefaultChatInitialLoadPolicyResolver()
    ) {
        self.messageManager = messageManager
        self.networkStatusProvider = networkStatusProvider
        self.policyResolver = policyResolver
    }

    func execute(
        room: ChatRoom,
        isParticipant: Bool
    ) -> AsyncStream<ChatInitialLoadEvent> {
        AsyncStream { continuation in
            let task = Task {
                defer { continuation.finish() }

                continuation.yield(.phaseChanged(.checkingNetwork))

                let network = networkStatusProvider.currentStatus
                let policy = policyResolver.policy(for: network)

                do {
                    guard isParticipant else {
                        guard network.isOnline else {
                            continuation.yield(.render(.showCenteredMessage("미리보기를 불러오려면 네트워크 연결을 확인해 주세요.")))
                            continuation.yield(.phaseChanged(.offlineNoLocal))
                            continuation.yield(.completed)
                            return
                        }

                        continuation.yield(.render(.hideCenteredMessage))
                        continuation.yield(.phaseChanged(.serverSyncing))
                        let preview = try await messageManager.fetchInitialServerMessages(room: room, pageSize: 100)
                        if Task.isCancelled { return }

                        continuation.yield(.render(.appendServer(preview)))
                        if !preview.isEmpty {
                            continuation.yield(.warmMedia(messages: preview, maxConcurrent: policy.mediaPrefetchConcurrency))
                        }
                        continuation.yield(.phaseChanged(.ready))
                        continuation.yield(.completed)
                        return
                    }

                    continuation.yield(.phaseChanged(.loadingLocal))
                    let roomID = room.ID ?? ""
                    let localMessages = try await messageManager.loadLocalRecentMessages(
                        roomID: roomID,
                        limit: policy.localRenderLimit
                    )
                    if Task.isCancelled { return }

                    if !localMessages.isEmpty {
                        continuation.yield(.render(.hideCenteredMessage))
                        continuation.yield(.render(.replaceLocal(localMessages)))
                        continuation.yield(.phaseChanged(.localVisible(isStale: true)))
                        continuation.yield(.warmMedia(messages: localMessages, maxConcurrent: policy.mediaPrefetchConcurrency))
                    }

                    guard network.isOnline else {
                        if localMessages.isEmpty {
                            continuation.yield(.render(.showCenteredMessage("주고받은 메시지가 아직 없어요.\n네트워크 연결을 확인해 주세요.")))
                            continuation.yield(.phaseChanged(.offlineNoLocal))
                        } else {
                            continuation.yield(.phaseChanged(.ready))
                        }
                        continuation.yield(.seedHotUsers(localMessages))
                        continuation.yield(.participantSessionReady(bindRealtime: true))
                        continuation.yield(.completed)
                        return
                    }

                    continuation.yield(.render(.hideCenteredMessage))
                    continuation.yield(.phaseChanged(.serverSyncing))

                    let serverMessages = try await messageManager.fetchInitialServerMessages(
                        room: room,
                        pageSize: policy.serverInitialPageSize
                    )
                    if Task.isCancelled { return }

                    if !serverMessages.isEmpty {
                        continuation.yield(.render(.appendServer(serverMessages)))
                        continuation.yield(.warmMedia(messages: serverMessages, maxConcurrent: policy.mediaPrefetchConcurrency))
                    }

                    async let persist: Void = messageManager.persistFetchedServerMessages(serverMessages)
                    let deletedIDs = try await messageManager.syncDeletedStates(localMessages: localMessages, room: room)
                    try await persist
                    if Task.isCancelled { return }

                    if !deletedIDs.isEmpty {
                        let deletedMessages = localMessages
                            .filter { deletedIDs.contains($0.ID) }
                            .map { msg in
                                var copy = msg
                                copy.isDeleted = true
                                return copy
                            }
                        if !deletedMessages.isEmpty {
                            continuation.yield(.render(.reloadDeleted(deletedMessages)))
                        }
                    }

                    continuation.yield(.seedHotUsers(localMessages + serverMessages))
                    continuation.yield(.phaseChanged(.ready))
                    continuation.yield(.participantSessionReady(bindRealtime: true))
                    continuation.yield(.completed)
                } catch {
                    if Task.isCancelled { return }
                    continuation.yield(.phaseChanged(.failed(message: error.localizedDescription)))
                    continuation.yield(.completed)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
