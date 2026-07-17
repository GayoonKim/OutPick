import Foundation
import SocketIO
import Testing
@testable import OutPick

struct RealtimeSocketListenerBinderTests {
    @Test func roomNotFoundJoinAckIsRecognizedAsAuthoritativeClosure() {
        #expect(
            RealtimeRoomJoinAckMapper.isRoomNotFound([
                ["ok": false, "message": "room_not_found"]
            ])
        )
        #expect(
            RealtimeRoomJoinAckMapper.isRoomNotFound([
                ["ok": false, "error": " room_not_found "]
            ])
        )
        #expect(
            !RealtimeRoomJoinAckMapper.isRoomNotFound([
                ["ok": false, "message": "not_joined"]
            ])
        )
        #expect(!RealtimeRoomJoinAckMapper.isRoomNotFound(["NO ACK"]))
    }

    @Test func authoritativeClosureIsReplayedUntilSameRoomIsCreatedAgain() {
        var state = RealtimeAuthoritativeRoomClosureState()

        #expect(!state.isClosed("room"))
        state.markClosed("room")
        #expect(state.isClosed("room"))
        #expect(!state.isClosed("other"))

        state.markCreated("room")
        #expect(!state.isClosed("room"))
    }

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

    @Test func messageIngressQueuePreservesMixedEventEnqueueOrder() async {
        let queue = RealtimeSocketMessageIngressQueue()

        #expect(queue.enqueue(data: ["text-1"], event: "chat message"))
        #expect(queue.enqueue(data: ["image-2"], event: "receiveImages"))
        #expect(queue.enqueue(data: ["video-3"], event: "receiveVideo"))
        queue.finish()

        var received: [(event: String, payload: String)] = []
        for await event in queue.stream {
            received.append((event.event, event.data.first as? String ?? ""))
        }

        #expect(received.map(\.event) == [
            "chat message",
            "receiveImages",
            "receiveVideo"
        ])
        #expect(received.map(\.payload) == ["text-1", "image-2", "video-3"])
    }

    @Test func finishedMessageIngressQueueRejectsLaterEvents() {
        let queue = RealtimeSocketMessageIngressQueue()

        queue.finish()

        #expect(!queue.enqueue(data: ["late"], event: "chat message"))
    }

    @Test func commonAdmissionDeduplicatesPerRoomAndBypassesLocalSequence() {
        var state = RealtimeSocketAdmissionState()
        let firstRoomMessage = makeAdmissionMessage(id: "same", seq: 1, roomID: "room-a")
        let secondRoomMessage = makeAdmissionMessage(id: "same", seq: 1, roomID: "room-b")
        let localMessage = makeAdmissionMessage(id: "same", seq: 0, roomID: "room-a")

        let firstAdmission = state.admit(firstRoomMessage)
        let duplicateAdmission = state.admit(firstRoomMessage)
        let otherRoomAdmission = state.admit(secondRoomMessage)
        let firstLocalAdmission = state.admit(localMessage)
        let secondLocalAdmission = state.admit(localMessage)

        #expect(firstAdmission)
        #expect(!duplicateAdmission)
        #expect(otherRoomAdmission)
        #expect(firstLocalAdmission)
        #expect(secondLocalAdmission)
    }

    @Test func commonAdmissionEvictsOldestIDAfterThreeHundredMessages() {
        var state = RealtimeSocketAdmissionState()

        for index in 0...300 {
            let admitted = state.admit(
                makeAdmissionMessage(
                    id: "message-\(index)",
                    seq: Int64(index + 1),
                    roomID: "room"
                )
            )
            #expect(admitted)
        }

        let evictedIDAdmission = state.admit(
            makeAdmissionMessage(id: "message-0", seq: 999, roomID: "room")
        )
        #expect(evictedIDAdmission)
    }

    @Test func commonAdmissionRoomRemovalAndResetClearRecentIDs() {
        var state = RealtimeSocketAdmissionState()
        let roomA = makeAdmissionMessage(id: "same", seq: 1, roomID: "room-a")
        let roomB = makeAdmissionMessage(id: "same", seq: 1, roomID: "room-b")

        let firstRoomAAdmission = state.admit(roomA)
        let firstRoomBAdmission = state.admit(roomB)
        #expect(firstRoomAAdmission)
        #expect(firstRoomBAdmission)
        state.removeRoom("room-a")
        let roomAAdmissionAfterRemoval = state.admit(roomA)
        let roomBDuplicateAdmission = state.admit(roomB)
        #expect(roomAAdmissionAfterRemoval)
        #expect(!roomBDuplicateAdmission)

        state.reset()
        let roomAAdmissionAfterReset = state.admit(roomA)
        let roomBAdmissionAfterReset = state.admit(roomB)
        #expect(roomAAdmissionAfterReset)
        #expect(roomBAdmissionAfterReset)
    }

    @Test func routingPromotionCarriesBackgroundHighWatermark() {
        var state = RealtimeRoomRoutingState()
        state.recordBackgroundAcceptance(roomID: "room", seq: 103)

        let lease = state.promote(roomID: "room", baselineSeq: 100)

        #expect(lease.baselineSeq == 100)
        #expect(lease.promotionHighWatermark == 103)
        #expect(state.route(for: "room") == .visible(lease))
        #expect(state.route(for: "other") == .background)
    }

    @Test func staleLeaseEndCannotClearNewVisibleRoute() {
        var state = RealtimeRoomRoutingState()
        let oldLease = state.promote(roomID: "room-a", baselineSeq: 10)
        let currentLease = state.promote(roomID: "room-b", baselineSeq: 20)

        let didEndStaleLease = state.end(oldLease, strictLastReleasedSeq: 15)
        #expect(!didEndStaleLease)
        #expect(state.route(for: "room-b") == .visible(currentLease))
        #expect(state.backgroundHighWatermark(for: "room-a") == 0)

        let didEndCurrentLease = state.end(currentLease, strictLastReleasedSeq: 25)
        #expect(didEndCurrentLease)
        #expect(state.route(for: "room-b") == .background)
        #expect(state.backgroundHighWatermark(for: "room-b") == 25)
    }

    @Test func negativeReleaseSequenceCannotEndVisibleLease() {
        var state = RealtimeRoomRoutingState()
        let lease = state.promote(roomID: "room", baselineSeq: 10)

        let didEndLease = state.end(lease, strictLastReleasedSeq: -1)
        #expect(!didEndLease)
        #expect(state.route(for: "room") == .visible(lease))
    }
}

private func makeAdmissionMessage(
    id: String,
    seq: Int64,
    roomID: String
) -> ChatMessage {
    ChatMessage(
        ID: id,
        seq: seq,
        roomID: roomID,
        senderUID: "sender",
        senderEmail: nil,
        senderNickname: "Sender",
        senderAvatarPath: nil,
        messageType: .text,
        msg: "message",
        sentAt: Date(timeIntervalSince1970: TimeInterval(max(0, seq))),
        attachments: [],
        replyPreview: nil
    )
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
