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

@MainActor
protocol ChatRoomRuntimeSocketObserving {
    func observeRoomClosed(roomID: String, onClosed: @escaping (String) -> Void) -> ChatRoomRuntimeSubscription
}

@MainActor
final class SocketChatRoomRuntimeRepository: ChatRoomRuntimeRepositoryProtocol {
    private let socketObserver: ChatRoomRuntimeSocketObserving

    init(socketObserver: ChatRoomRuntimeSocketObserving = SocketIOManager.shared) {
        self.socketObserver = socketObserver
    }

    func observeRoomClosed(roomID: String, onClosed: @escaping (String) -> Void) -> ChatRoomRuntimeSubscription {
        socketObserver.observeRoomClosed(roomID: roomID, onClosed: onClosed)
    }
}

extension SocketIOManager: ChatRoomRuntimeSocketObserving {
    func observeRoomClosed(roomID: String, onClosed: @escaping (String) -> Void) -> ChatRoomRuntimeSubscription {
        guard let socket else { return ChatRoomRuntimeSubscription() }

        let listenerID = socket.on("room:closed") { data, _ in
            guard
                let dict = data.first as? [String: Any],
                let closedRoomID = dict["roomID"] as? String,
                closedRoomID == roomID
            else { return }

            onClosed(closedRoomID)
        }

        return ChatRoomRuntimeSubscription { [weak socket] in
            Task { @MainActor in
                socket?.off(id: listenerID)
            }
        }
    }
}
