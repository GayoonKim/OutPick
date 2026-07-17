import Foundation
import SocketIO

struct RealtimeSocketMessageIngressEvent: @unchecked Sendable {
    let data: [Any]
    let event: String
}

/// Socket.IO의 동기 callback 순서를 하나의 비동기 consumer에 그대로 전달한다.
final class RealtimeSocketMessageIngressQueue: @unchecked Sendable {
    let stream: AsyncStream<RealtimeSocketMessageIngressEvent>

    private let continuation: AsyncStream<RealtimeSocketMessageIngressEvent>.Continuation
    private let lock = NSLock()
    private var isFinished = false

    init() {
        var resolvedContinuation: AsyncStream<RealtimeSocketMessageIngressEvent>.Continuation!
        stream = AsyncStream(bufferingPolicy: .unbounded) { continuation in
            resolvedContinuation = continuation
        }
        continuation = resolvedContinuation
    }

    @discardableResult
    func enqueue(data: [Any], event: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return false }
        continuation.yield(
            RealtimeSocketMessageIngressEvent(data: data, event: event)
        )
        return true
    }

    func finish() {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        continuation.finish()
        lock.unlock()
    }
}

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
