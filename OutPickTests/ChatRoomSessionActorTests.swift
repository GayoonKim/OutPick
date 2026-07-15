import Foundation
import Testing
@testable import OutPick

struct ChatRoomSessionActorTests {
    @Test func incomingDuplicateIsDeliveredOnceToOneConsumer() async {
        let actor = ChatRoomSessionActor(roomID: "room")
        let consumer = await actor.addConsumer()

        await actor.publishIncoming(makeMessage(id: "same", seq: 1))
        await actor.publishIncoming(makeMessage(id: "same", seq: 1))
        await actor.publishIncoming(makeMessage(id: "next", seq: 2))

        var iterator = consumer.stream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()

        #expect(first?.ID == "same")
        #expect(second?.ID == "next")
        await actor.finishAll()
    }

    @Test func incomingDuplicateIsDeliveredOnceToEveryConsumer() async {
        let actor = ChatRoomSessionActor(roomID: "room")
        let firstConsumer = await actor.addConsumer()
        let secondConsumer = await actor.addConsumer()

        await actor.publishIncoming(makeMessage(id: "same", seq: 1))
        for type in [ChatMessageType.image, .video, .lookbookShare] {
            await actor.publishIncoming(makeMessage(id: "same", seq: 1, type: type))
        }
        await actor.publishIncoming(makeMessage(id: "next", seq: 2))

        var firstIterator = firstConsumer.stream.makeAsyncIterator()
        var secondIterator = secondConsumer.stream.makeAsyncIterator()
        let firstIDs = [
            await firstIterator.next()?.ID,
            await firstIterator.next()?.ID
        ]
        let secondIDs = [
            await secondIterator.next()?.ID,
            await secondIterator.next()?.ID
        ]

        #expect(firstIDs == ["same", "next"])
        #expect(secondIDs == ["same", "next"])
        await actor.finishAll()
    }

    @Test func sameIDWithDifferentSequenceKeepsFirstIncomingEvent() async {
        let actor = ChatRoomSessionActor(roomID: "room")
        let consumer = await actor.addConsumer()

        await actor.publishIncoming(makeMessage(id: "same", seq: 1))
        await actor.publishIncoming(makeMessage(id: "same", seq: 99))
        await actor.publishIncoming(makeMessage(id: "next", seq: 2))

        var iterator = consumer.stream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()

        #expect(first?.ID == "same")
        #expect(first?.seq == 1)
        #expect(second?.ID == "next")
        await actor.finishAll()
    }

    @Test func oldestIDIsAcceptedAgainAfterThreeHundredMessageWindow() async {
        let actor = ChatRoomSessionActor(roomID: "room")
        let consumer = await actor.addConsumer()

        for index in 0...300 {
            await actor.publishIncoming(
                makeMessage(id: "message-\(index)", seq: Int64(index + 1))
            )
        }
        await actor.publishIncoming(makeMessage(id: "message-0", seq: 999))
        await actor.publishIncoming(makeMessage(id: "sentinel", seq: 1_000))

        var iterator = consumer.stream.makeAsyncIterator()
        var received: [ChatMessage] = []
        for _ in 0..<302 {
            if let message = await iterator.next() {
                received.append(message)
            }
        }

        #expect(received.count == 302)
        #expect(received[301].ID == "message-0")
        #expect(received[301].seq == 999)
        await actor.finishAll()
    }

    @Test func recreatedActorDoesNotRetainRecentIncomingIDs() async {
        let firstActor = ChatRoomSessionActor(roomID: "room")
        let firstConsumer = await firstActor.addConsumer()
        await firstActor.publishIncoming(makeMessage(id: "same", seq: 1))
        var firstIterator = firstConsumer.stream.makeAsyncIterator()
        let first = await firstIterator.next()
        #expect(first?.ID == "same")
        await firstActor.finishAll()

        let secondActor = ChatRoomSessionActor(roomID: "room")
        let secondConsumer = await secondActor.addConsumer()
        await secondActor.publishIncoming(makeMessage(id: "same", seq: 1))
        var secondIterator = secondConsumer.stream.makeAsyncIterator()
        let second = await secondIterator.next()

        #expect(second?.ID == "same")
        await secondActor.finishAll()
    }

    @Test func localFailedMessageDoesNotSuppressLaterServerConfirmation() async {
        let actor = ChatRoomSessionActor(roomID: "room")
        let consumer = await actor.addConsumer()
        var failed = makeMessage(id: "retry-id", seq: 0)
        failed.isFailed = true

        await actor.publishLocal(failed)
        await actor.publishIncoming(makeMessage(id: "retry-id", seq: 7))

        var iterator = consumer.stream.makeAsyncIterator()
        let local = await iterator.next()
        let confirmed = await iterator.next()

        #expect(local?.isFailed == true)
        #expect(confirmed?.ID == "retry-id")
        #expect(confirmed?.seq == 7)
        #expect(confirmed?.isFailed == false)
        await actor.finishAll()
    }

    private func makeMessage(
        id: String,
        seq: Int64,
        type: ChatMessageType = .text
    ) -> ChatMessage {
        ChatMessage(
            ID: id,
            seq: seq,
            roomID: "room",
            senderUID: "sender",
            senderEmail: nil,
            senderNickname: "Sender",
            senderAvatarPath: nil,
            messageType: type,
            msg: "message",
            sentAt: Date(timeIntervalSince1970: TimeInterval(seq)),
            attachments: [],
            replyPreview: nil
        )
    }
}
