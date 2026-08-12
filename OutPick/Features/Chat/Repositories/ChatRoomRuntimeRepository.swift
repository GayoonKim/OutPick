//
//  ChatRoomRuntimeRepository.swift
//  OutPick
//
//  Created by Codex on 6/18/26.
//

import Foundation

final class ChatRoomRuntimeSubscription {
    private let stopHandler: () -> Void
    private var isStopped = false

    init(stopHandler: @escaping () -> Void = {}) {
        self.stopHandler = stopHandler
    }

    deinit {
        stop()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        stopHandler()
    }
}

@MainActor
protocol ChatRoomRuntimeRepositoryProtocol {
    func observeRoomClosed(roomID: String, onClosed: @escaping (RealtimeRoomClosureEvent) -> Void) -> ChatRoomRuntimeSubscription
    func observeRoomMembershipRemoved(roomID: String, onRemoved: @escaping (RealtimeRoomMembershipRemovalEvent) -> Void) -> ChatRoomRuntimeSubscription
}

protocol ChatRoomRuntimeSocketObserving {
    func observeRoomClosed(roomID: String) async -> AsyncStream<RealtimeRoomClosureEvent>
    func observeRoomMembershipRemoved(roomID: String) async -> AsyncStream<RealtimeRoomMembershipRemovalEvent>
}

@MainActor
final class SocketChatRoomRuntimeRepository: ChatRoomRuntimeRepositoryProtocol {
    private let socketObserver: ChatRoomRuntimeSocketObserving

    init(socketObserver: ChatRoomRuntimeSocketObserving = RealtimeSocketService.shared) {
        self.socketObserver = socketObserver
    }

    func observeRoomClosed(roomID: String, onClosed: @escaping (RealtimeRoomClosureEvent) -> Void) -> ChatRoomRuntimeSubscription {
        let task = Task { [socketObserver] in
            let stream = await socketObserver.observeRoomClosed(roomID: roomID)
            for await event in stream {
                guard event.roomID == roomID else { continue }
                await MainActor.run {
                    onClosed(event)
                }
            }
        }

        return ChatRoomRuntimeSubscription {
            task.cancel()
        }
    }

    func observeRoomMembershipRemoved(
        roomID: String,
        onRemoved: @escaping (RealtimeRoomMembershipRemovalEvent) -> Void
    ) -> ChatRoomRuntimeSubscription {
        let task = Task { [socketObserver] in
            let stream = await socketObserver.observeRoomMembershipRemoved(roomID: roomID)
            for await event in stream where event.roomID == roomID {
                await MainActor.run { onRemoved(event) }
            }
        }
        return ChatRoomRuntimeSubscription { task.cancel() }
    }
}

extension RealtimeSocketService: ChatRoomRuntimeSocketObserving {}
