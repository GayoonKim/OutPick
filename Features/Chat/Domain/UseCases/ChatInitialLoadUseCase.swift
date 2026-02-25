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
        isParticipant: Bool,
        onEvent: @escaping @MainActor (ChatInitialLoadEvent) -> Void
    ) async
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
        isParticipant: Bool,
        onEvent: @escaping @MainActor (ChatInitialLoadEvent) -> Void
    ) async {
        await onEvent(.phaseChanged(.checkingNetwork))

        let network = networkStatusProvider.currentStatus
        let policy = policyResolver.policy(for: network)

        do {
            guard isParticipant else {
                guard network.isOnline else {
                    await onEvent(.render(.showCenteredMessage("미리보기를 불러오려면 네트워크 연결을 확인해 주세요.")))
                    await onEvent(.phaseChanged(.offlineNoLocal))
                    await onEvent(.completed)
                    return
                }

                await onEvent(.render(.hideCenteredMessage))
                await onEvent(.phaseChanged(.serverSyncing))
                let preview = try await messageManager.fetchInitialServerMessages(room: room, pageSize: 100)
                await onEvent(.render(.appendServer(preview)))
                if !preview.isEmpty {
                    await onEvent(.warmMedia(messages: preview, maxConcurrent: policy.mediaPrefetchConcurrency))
                }
                await onEvent(.phaseChanged(.ready))
                await onEvent(.completed)
                return
            }

            await onEvent(.phaseChanged(.loadingLocal))
            let roomID = room.ID ?? ""
            let localMessages = try await messageManager.loadLocalRecentMessages(
                roomID: roomID,
                limit: policy.localRenderLimit
            )

            if !localMessages.isEmpty {
                await onEvent(.render(.hideCenteredMessage))
                await onEvent(.render(.replaceLocal(localMessages)))
                await onEvent(.phaseChanged(.localVisible(isStale: true)))
                await onEvent(.warmMedia(messages: localMessages, maxConcurrent: policy.mediaPrefetchConcurrency))
            }

            guard network.isOnline else {
                if localMessages.isEmpty {
                    await onEvent(.render(.showCenteredMessage("주고받은 메시지가 아직 없어요.\n네트워크 연결을 확인해 주세요.")))
                    await onEvent(.phaseChanged(.offlineNoLocal))
                } else {
                    await onEvent(.phaseChanged(.ready))
                }
                await onEvent(.seedHotUsers(localMessages))
                // Even in the offline branch, bind realtime listeners.
                // `NWPathMonitor` may still be warming up on first screen entry and report `.offline` transiently.
                // Socket subscriptions are safe to attach and will join later when the socket reconnects.
                await onEvent(.participantSessionReady(bindRealtime: true))
                await onEvent(.completed)
                return
            }

            await onEvent(.render(.hideCenteredMessage))
            await onEvent(.phaseChanged(.serverSyncing))

            let serverMessages = try await messageManager.fetchInitialServerMessages(
                room: room,
                pageSize: policy.serverInitialPageSize
            )

            if !serverMessages.isEmpty {
                await onEvent(.render(.appendServer(serverMessages)))
                await onEvent(.warmMedia(messages: serverMessages, maxConcurrent: policy.mediaPrefetchConcurrency))
            }

            async let persist: Void = messageManager.persistFetchedServerMessages(serverMessages)
            let deletedIDs = try await messageManager.syncDeletedStates(localMessages: localMessages, room: room)
            try await persist

            if !deletedIDs.isEmpty {
                let deletedMessages = localMessages
                    .filter { deletedIDs.contains($0.ID) }
                    .map { msg in
                        var copy = msg
                        copy.isDeleted = true
                        return copy
                    }
                if !deletedMessages.isEmpty {
                    await onEvent(.render(.reloadDeleted(deletedMessages)))
                }
            }

            await onEvent(.seedHotUsers(localMessages + serverMessages))
            await onEvent(.phaseChanged(.ready))
            await onEvent(.participantSessionReady(bindRealtime: true))
            await onEvent(.completed)
        } catch {
            await onEvent(.phaseChanged(.failed(message: error.localizedDescription)))
            await onEvent(.completed)
        }
    }
}
