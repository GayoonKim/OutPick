import Foundation
import SocketIO

protocol RealtimeSocketEventListening: AnyObject {
    func on(clientEvent event: SocketClientEvent, callback: @escaping ([Any]) -> Void)
    func on(_ event: String, callback: @escaping ([Any]) -> Void)
}

final class SocketIOEventListenerAdapter: RealtimeSocketEventListening {
    private let socket: SocketIOClient

    init(socket: SocketIOClient) {
        self.socket = socket
    }

    func on(clientEvent event: SocketClientEvent, callback: @escaping ([Any]) -> Void) {
        socket.on(clientEvent: event) { data, _ in
            callback(data)
        }
    }

    func on(_ event: String, callback: @escaping ([Any]) -> Void) {
        socket.on(event) { data, _ in
            callback(data)
        }
    }
}

struct RealtimeSocketListenerCallbacks {
    let connected: ([Any]) -> Void
    let error: ([Any]) -> Void
    let disconnected: ([Any]) -> Void
    let serverConnectReady: ([Any]) -> Void
    let chatMessage: ([Any]) -> Void
    let imagesReceived: ([Any]) -> Void
    let videoReceived: ([Any]) -> Void
    let roomClosed: ([Any]) -> Void
}

final class RealtimeSocketListenerBinder {
    static let serverConnectReadyEvent = "server:connect:ready"
    static let chatMessageEvent = "chat message"
    static let imagesReceivedEvent = "receiveImages"
    static let videoReceivedEvent = "receiveVideo"
    static let roomClosedEvent = "room:closed"

    private(set) var isBound = false

    @discardableResult
    func bind(
        to listener: RealtimeSocketEventListening,
        callbacks: RealtimeSocketListenerCallbacks
    ) -> Bool {
        guard !isBound else { return false }
        isBound = true

        listener.on(clientEvent: .connect, callback: callbacks.connected)
        listener.on(clientEvent: .error, callback: callbacks.error)
        listener.on(clientEvent: .disconnect, callback: callbacks.disconnected)
        listener.on(Self.serverConnectReadyEvent, callback: callbacks.serverConnectReady)
        listener.on(Self.chatMessageEvent, callback: callbacks.chatMessage)
        listener.on(Self.imagesReceivedEvent, callback: callbacks.imagesReceived)
        listener.on(Self.videoReceivedEvent, callback: callbacks.videoReceived)
        listener.on(Self.roomClosedEvent, callback: callbacks.roomClosed)
        return true
    }
}
