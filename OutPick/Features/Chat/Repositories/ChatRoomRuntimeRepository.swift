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
    func observeRoomClosed(roomID: String, onClosed: @escaping (String) -> Void) -> ChatRoomRuntimeSubscription
}

protocol ChatRoomRuntimeSocketObserving {
    func observeRoomClosed(roomID: String) async -> AsyncStream<String>
}

@MainActor
final class SocketChatRoomRuntimeRepository: ChatRoomRuntimeRepositoryProtocol {
    private let socketObserver: ChatRoomRuntimeSocketObserving

    init(socketObserver: ChatRoomRuntimeSocketObserving = RealtimeSocketService.shared) {
        self.socketObserver = socketObserver
    }

    func observeRoomClosed(roomID: String, onClosed: @escaping (String) -> Void) -> ChatRoomRuntimeSubscription {
        let task = Task { [socketObserver] in
            let stream = await socketObserver.observeRoomClosed(roomID: roomID)
            for await closedRoomID in stream {
                guard closedRoomID == roomID else { continue }
                await MainActor.run {
                    onClosed(closedRoomID)
                }
            }
        }

        return ChatRoomRuntimeSubscription {
            task.cancel()
        }
    }
}

extension RealtimeSocketService: ChatRoomRuntimeSocketObserving {}
