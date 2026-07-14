import SocketIO
import Testing
@testable import OutPick

struct RealtimeSocketListenerBinderTests {
    @Test func firstBindRegistersExpectedEventSurfaceOnce() {
        let listener = SocketEventListenerSpy()
        let binder = RealtimeSocketListenerBinder()

        let didBind = binder.bind(to: listener, callbacks: .spy())

        #expect(didBind)
        #expect(binder.isBound)
        #expect(listener.clientEvents == [.connect, .error, .disconnect])
        #expect(listener.namedEvents == [
            RealtimeSocketListenerBinder.serverConnectReadyEvent,
            RealtimeSocketListenerBinder.chatMessageEvent,
            RealtimeSocketListenerBinder.imagesReceivedEvent,
            RealtimeSocketListenerBinder.videoReceivedEvent,
            RealtimeSocketListenerBinder.roomClosedEvent
        ])
    }

    @Test func secondBindDoesNotRegisterDuplicateHandlers() {
        let listener = SocketEventListenerSpy()
        let binder = RealtimeSocketListenerBinder()
        let callbacks = RealtimeSocketListenerCallbacks.spy()

        #expect(binder.bind(to: listener, callbacks: callbacks))
        #expect(!binder.bind(to: listener, callbacks: callbacks))
        #expect(listener.clientEvents.count == 3)
        #expect(listener.namedEvents.count == 5)
    }

    @Test func repeatedConnectCallbackDoesNotChangeRegistrationCount() {
        let listener = SocketEventListenerSpy()
        let callbacks = ListenerCallbackSpy()
        let binder = RealtimeSocketListenerBinder()
        binder.bind(to: listener, callbacks: callbacks.callbacks)

        listener.emit(clientEvent: .connect, data: ["/"])
        listener.emit(clientEvent: .connect, data: ["/"])

        #expect(callbacks.connectedPayloads.count == 2)
        #expect(listener.clientEvents.count == 3)
        #expect(listener.namedEvents.count == 5)
    }

    @Test func newBinderRegistersAnIndependentSocketSurface() {
        let firstListener = SocketEventListenerSpy()
        let secondListener = SocketEventListenerSpy()

        RealtimeSocketListenerBinder().bind(to: firstListener, callbacks: .spy())
        RealtimeSocketListenerBinder().bind(to: secondListener, callbacks: .spy())

        #expect(firstListener.clientEvents.count == 3)
        #expect(firstListener.namedEvents.count == 5)
        #expect(secondListener.clientEvents.count == 3)
        #expect(secondListener.namedEvents.count == 5)
    }

    @Test func namedEventsForwardPayloadsToTheirActorBridgeCallbacks() {
        let listener = SocketEventListenerSpy()
        let callbacks = ListenerCallbackSpy()
        RealtimeSocketListenerBinder().bind(to: listener, callbacks: callbacks.callbacks)

        listener.emit(namedEvent: RealtimeSocketListenerBinder.serverConnectReadyEvent, data: ["ready"])
        listener.emit(namedEvent: RealtimeSocketListenerBinder.chatMessageEvent, data: ["chat"])
        listener.emit(namedEvent: RealtimeSocketListenerBinder.imagesReceivedEvent, data: ["images"])
        listener.emit(namedEvent: RealtimeSocketListenerBinder.videoReceivedEvent, data: ["video"])
        listener.emit(namedEvent: RealtimeSocketListenerBinder.roomClosedEvent, data: ["closed"])

        #expect(callbacks.serverReadyPayloads.count == 1)
        #expect(callbacks.chatPayloads.count == 1)
        #expect(callbacks.imagePayloads.count == 1)
        #expect(callbacks.videoPayloads.count == 1)
        #expect(callbacks.roomClosedPayloads.count == 1)
    }
}

private final class SocketEventListenerSpy: RealtimeSocketEventListening {
    private(set) var clientEvents: [SocketClientEvent] = []
    private(set) var namedEvents: [String] = []
    private var clientCallbacks: [SocketClientEvent: ([Any]) -> Void] = [:]
    private var namedCallbacks: [String: ([Any]) -> Void] = [:]

    func on(clientEvent event: SocketClientEvent, callback: @escaping ([Any]) -> Void) {
        clientEvents.append(event)
        clientCallbacks[event] = callback
    }

    func on(_ event: String, callback: @escaping ([Any]) -> Void) {
        namedEvents.append(event)
        namedCallbacks[event] = callback
    }

    func emit(clientEvent: SocketClientEvent, data: [Any]) {
        clientCallbacks[clientEvent]?(data)
    }

    func emit(namedEvent: String, data: [Any]) {
        namedCallbacks[namedEvent]?(data)
    }
}

private final class ListenerCallbackSpy {
    private(set) var connectedPayloads: [[Any]] = []
    private(set) var serverReadyPayloads: [[Any]] = []
    private(set) var chatPayloads: [[Any]] = []
    private(set) var imagePayloads: [[Any]] = []
    private(set) var videoPayloads: [[Any]] = []
    private(set) var roomClosedPayloads: [[Any]] = []

    lazy var callbacks = RealtimeSocketListenerCallbacks(
        connected: { [weak self] in self?.connectedPayloads.append($0) },
        error: { _ in },
        disconnected: { _ in },
        serverConnectReady: { [weak self] in self?.serverReadyPayloads.append($0) },
        chatMessage: { [weak self] in self?.chatPayloads.append($0) },
        imagesReceived: { [weak self] in self?.imagePayloads.append($0) },
        videoReceived: { [weak self] in self?.videoPayloads.append($0) },
        roomClosed: { [weak self] in self?.roomClosedPayloads.append($0) }
    )
}

private extension RealtimeSocketListenerCallbacks {
    static func spy() -> Self {
        Self(
            connected: { _ in },
            error: { _ in },
            disconnected: { _ in },
            serverConnectReady: { _ in },
            chatMessage: { _ in },
            imagesReceived: { _ in },
            videoReceived: { _ in },
            roomClosed: { _ in }
        )
    }
}
