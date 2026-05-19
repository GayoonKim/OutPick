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
    case replaceWindow(ChatInitialWindow)
    case reloadDeleted([ChatMessage])
    case showCenteredMessage(String)
    case hideCenteredMessage
}

enum ChatInitialLoadEvent {
    case phaseChanged(ChatInitialLoadPhase)
    case render(ChatInitialLoadRenderCommand)
    case warmMedia(messages: [ChatMessage], maxConcurrent: Int)
    case participantSessionReady(ChatInitialSessionState, bindRealtime: Bool)
    case completed
}

protocol ChatInitialLoadPolicyResolving {
    func policy(for network: NetworkStatus) -> ChatInitialLoadPolicy
}

struct DefaultChatInitialLoadPolicyResolver: ChatInitialLoadPolicyResolving {
    func policy(for network: NetworkStatus) -> ChatInitialLoadPolicy {
        if !network.isOnline {
            return ChatInitialLoadPolicy(
                latestTailSize: 80,
                unreadAfterSize: 80,
                unreadBeforeContextSize: 20,
                mediaPrefetchConcurrency: 1
            )
        }

        if network.isConstrained {
            return ChatInitialLoadPolicy(
                latestTailSize: 60,
                unreadAfterSize: 60,
                unreadBeforeContextSize: 15,
                mediaPrefetchConcurrency: 2
            )
        }

        if network.isExpensive || network.accessClass == .cellular {
            return ChatInitialLoadPolicy(
                latestTailSize: 60,
                unreadAfterSize: 60,
                unreadBeforeContextSize: 15,
                mediaPrefetchConcurrency: 3
            )
        }

        return ChatInitialLoadPolicy(
            latestTailSize: 80,
            unreadAfterSize: 80,
            unreadBeforeContextSize: 20,
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
    private let userProfileRepository: UserProfileRepositoryProtocol
    private let chatRoomRepository: FirebaseChatRoomRepositoryProtocol
    private let networkStatusProvider: NetworkStatusProviding
    private let policyResolver: ChatInitialLoadPolicyResolving

    init(
        messageManager: ChatMessageManaging,
        userProfileRepository: UserProfileRepositoryProtocol,
        chatRoomRepository: FirebaseChatRoomRepositoryProtocol,
        networkStatusProvider: NetworkStatusProviding,
        policyResolver: ChatInitialLoadPolicyResolving = DefaultChatInitialLoadPolicyResolver()
    ) {
        self.messageManager = messageManager
        self.userProfileRepository = userProfileRepository
        self.chatRoomRepository = chatRoomRepository
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
                let roomID = room.ID ?? ""

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
                        let latestSeq = max(Int64(room.seq), try await resolvedLatestSeq(roomID: roomID))
                        let preview = try await messageManager.fetchServerInitialWindow(
                            room: room,
                            mode: .latestTail(latestSeq: latestSeq),
                            policy: policy
                        )
                        if Task.isCancelled { return }

                        continuation.yield(.render(.replaceWindow(preview)))
                        if !preview.messages.isEmpty {
                            continuation.yield(.warmMedia(messages: preview.messages, maxConcurrent: policy.mediaPrefetchConcurrency))
                        }
                        continuation.yield(.phaseChanged(.ready))
                        continuation.yield(.completed)
                        return
                    }

                    let latestSeq = max(Int64(room.seq), try await resolvedLatestSeq(roomID: roomID))
                    let lastReadSeq = try await resolvedLastReadSeq(roomID: roomID)
                    let mode = makeOpenMode(lastReadSeq: lastReadSeq, latestSeq: latestSeq)

                    continuation.yield(.phaseChanged(.loadingLocal))
                    let localWindow = try await messageManager.loadLocalInitialWindow(
                        roomID: roomID,
                        mode: mode,
                        policy: policy
                    )
                    if Task.isCancelled { return }

                    if !localWindow.messages.isEmpty {
                        continuation.yield(.render(.hideCenteredMessage))
                        continuation.yield(.render(.replaceWindow(localWindow)))
                        continuation.yield(.phaseChanged(.localVisible(isStale: true)))
                        continuation.yield(.warmMedia(messages: localWindow.messages, maxConcurrent: policy.mediaPrefetchConcurrency))
                    }

                    guard network.isOnline else {
                        if localWindow.messages.isEmpty {
                            continuation.yield(.render(.showCenteredMessage("주고받은 메시지가 아직 없어요.\n네트워크 연결을 확인해 주세요.")))
                            continuation.yield(.phaseChanged(.offlineNoLocal))
                        } else {
                            continuation.yield(.phaseChanged(.ready))
                        }
                        continuation.yield(.participantSessionReady(ChatInitialSessionState(window: localWindow), bindRealtime: false))
                        continuation.yield(.completed)
                        return
                    }

                    continuation.yield(.render(.hideCenteredMessage))
                    continuation.yield(.phaseChanged(.serverSyncing))

                    let serverWindow = try await messageManager.fetchServerInitialWindow(
                        room: room,
                        mode: mode,
                        policy: policy
                    )
                    if Task.isCancelled { return }

                    continuation.yield(.render(.replaceWindow(serverWindow)))
                    if !serverWindow.messages.isEmpty {
                        continuation.yield(.warmMedia(messages: serverWindow.messages, maxConcurrent: policy.mediaPrefetchConcurrency))
                    }

                    try await messageManager.persistFetchedServerMessages(serverWindow.messages)
                    let deletedIDs = try await messageManager.syncDeletedStates(localMessages: serverWindow.messages, room: room)
                    if Task.isCancelled { return }

                    if !deletedIDs.isEmpty {
                        let deletedMessages = serverWindow.messages
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

                    continuation.yield(.phaseChanged(.ready))
                    continuation.yield(.participantSessionReady(ChatInitialSessionState(window: serverWindow), bindRealtime: true))
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

    private func resolvedLastReadSeq(roomID: String) async throws -> Int64 {
        guard !roomID.isEmpty else { return 0 }
        return try await userProfileRepository.fetchLastReadSeq(for: roomID)
    }

    private func resolvedLatestSeq(roomID: String) async throws -> Int64 {
        guard !roomID.isEmpty else { return 0 }
        return try await chatRoomRepository.fetchLatestSeq(for: roomID)
    }

    private func makeOpenMode(lastReadSeq: Int64, latestSeq: Int64) -> ChatInitialOpenMode {
        if latestSeq > lastReadSeq {
            return .unreadAnchor(lastReadSeq: lastReadSeq, latestSeq: latestSeq)
        }
        return .latestTail(latestSeq: latestSeq)
    }
}
