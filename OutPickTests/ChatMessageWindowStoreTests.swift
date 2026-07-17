//
//  ChatMessageWindowStoreTests.swift
//  OutPickTests
//
//  Created by Codex on 6/18/26.
//

import Foundation
import Testing
@testable import OutPick

struct ChatMessageWindowStoreTests {
    @Test func resetBuildsDateSeparatorsAndReadMarker() throws {
        var store = makeStore()
        let firstDay = Date(timeIntervalSince1970: 100)
        let secondDay = Date(timeIntervalSince1970: 86_500)
        let messages = [
            makeMessage(id: "m1", seq: 1, sentAt: firstDay),
            makeMessage(id: "m2", seq: 2, sentAt: secondDay),
            makeMessage(id: "m3", seq: 3, sentAt: secondDay.addingTimeInterval(60))
        ]

        let items = store.reset(messages: messages, readBoundarySeq: 1)

        #expect(messageIDs(in: items) == ["m1", "m2", "m3"])
        #expect(items.filter(isDateSeparator).count == 2)
        let readMarkerIndex = try #require(items.firstIndex(where: isReadMarker))
        let secondMessageIndex = try #require(items.firstIndex(where: { $0.messageID == "m2" }))
        #expect(readMarkerIndex < secondMessageIndex)
    }

    @Test func applyDedupesIncomingMessagesAndReconfiguresExistingMessage() throws {
        var store = makeStore()
        let sentAt = Date(timeIntervalSince1970: 100)
        _ = store.reset(
            messages: [makeMessage(id: "m1", seq: 1, text: "old", sentAt: sentAt)],
            readBoundarySeq: nil
        )

        let mutation = store.apply(
            messages: [
                makeMessage(id: "m1", seq: 1, text: "new", sentAt: sentAt),
                makeMessage(id: "m2", seq: 2, text: "two", sentAt: sentAt.addingTimeInterval(60)),
                makeMessage(id: "m2", seq: 2, text: "duplicate", sentAt: sentAt.addingTimeInterval(120))
            ],
            updateType: .newer,
            isUserInCurrentRoom: true,
            windowSize: 300
        )

        #expect(messageIDs(in: mutation.items) == ["m1", "m2"])
        #expect(mutation.reconfiguredItems.map(\.messageID) == ["m1"])
        #expect(mutation.insertedItems.compactMap(\.messageID) == ["m2"])
        #expect(mutation.replacements.map { $0.previous.ID } == ["m1"])
        #expect(store.message(for: "m1")?.msg == "new")
    }

    @Test func applyReordersRetriedFailedMessageAfterServerConfirmation() {
        var store = makeStore()
        let sentAt = Date(timeIntervalSince1970: 100)
        var firstFailed = makeMessage(id: "failed-1", seq: 0, sentAt: sentAt.addingTimeInterval(1))
        firstFailed.isFailed = true
        var secondFailed = makeMessage(id: "failed-2", seq: 0, sentAt: sentAt.addingTimeInterval(2))
        secondFailed.isFailed = true
        _ = store.reset(
            messages: [
                makeMessage(id: "m1", seq: 1, sentAt: sentAt),
                firstFailed,
                secondFailed
            ],
            readBoundarySeq: nil
        )

        let confirmed = makeMessage(id: "failed-2", seq: 2, sentAt: sentAt.addingTimeInterval(2))

        let mutation = store.apply(
            messages: [confirmed],
            updateType: .newer,
            isUserInCurrentRoom: true,
            windowSize: 300
        )

        #expect(messageIDs(in: mutation.items) == ["m1", "failed-2", "failed-1"])
        #expect(mutation.shouldReloadSnapshot == true)
        #expect(mutation.reconfiguredItems.map(\.messageID) == ["failed-2"])
        #expect(store.lastMessageID() == "failed-1")
    }

    @Test func applyNewerInsertsReadMarkerWhenUnreadBoundaryIsCrossed() throws {
        var store = makeStore()
        let sentAt = Date(timeIntervalSince1970: 100)
        _ = store.reset(
            messages: [makeMessage(id: "m1", seq: 1, sentAt: sentAt)],
            readBoundarySeq: 1
        )

        let mutation = store.apply(
            messages: [makeMessage(id: "m2", seq: 2, sentAt: sentAt.addingTimeInterval(60))],
            updateType: .newer,
            isUserInCurrentRoom: false,
            windowSize: 300
        )

        let readMarkerIndex = try #require(mutation.items.firstIndex(where: isReadMarker))
        let secondMessageIndex = try #require(mutation.items.firstIndex(where: { $0.messageID == "m2" }))
        #expect(readMarkerIndex < secondMessageIndex)
    }

    @Test func applyNewerVirtualizesOldestItemsAndPrunesMessageMap() {
        var store = makeStore()
        let sentAt = Date(timeIntervalSince1970: 100)
        _ = store.reset(
            messages: [
                makeMessage(id: "m1", seq: 1, sentAt: sentAt),
                makeMessage(id: "m2", seq: 2, sentAt: sentAt.addingTimeInterval(1)),
                makeMessage(id: "m3", seq: 3, sentAt: sentAt.addingTimeInterval(2))
            ],
            readBoundarySeq: nil
        )

        let mutation = store.apply(
            messages: [
                makeMessage(id: "m4", seq: 4, sentAt: sentAt.addingTimeInterval(3)),
                makeMessage(id: "m5", seq: 5, sentAt: sentAt.addingTimeInterval(4)),
                makeMessage(id: "m6", seq: 6, sentAt: sentAt.addingTimeInterval(5))
            ],
            updateType: .newer,
            isUserInCurrentRoom: true,
            windowSize: 5
        )

        #expect(messageIDs(in: mutation.items) == ["m2", "m3", "m4", "m5", "m6"])
        #expect(store.message(for: "m1") == nil)
        #expect(store.firstMessageID() == "m2")
        #expect(store.lastMessageID() == "m6")
    }

    @Test func applyOlderSameDayPageKeepsDateSeparatorIdentityUnique() {
        var store = makeStore()
        let day = Date(timeIntervalSince1970: 100)
        _ = store.reset(
            messages: [
                makeMessage(id: "m3", seq: 3, sentAt: day.addingTimeInterval(120)),
                makeMessage(id: "m4", seq: 4, sentAt: day.addingTimeInterval(180))
            ],
            readBoundarySeq: nil
        )

        let mutation = store.apply(
            messages: [
                makeMessage(id: "m1", seq: 1, sentAt: day),
                makeMessage(id: "m2", seq: 2, sentAt: day.addingTimeInterval(60))
            ],
            updateType: .older,
            isUserInCurrentRoom: true,
            windowSize: 300
        )

        #expect(messageIDs(in: mutation.items) == ["m1", "m2", "m3", "m4"])
        #expect(mutation.items.filter(isDateSeparator).count == 1)
        #expect(Set(mutation.items).count == mutation.items.count)
    }

    @Test func applyOlderCrossDayPageBuildsOneSeparatorPerDay() {
        var store = makeStore()
        let firstDay = Date(timeIntervalSince1970: 100)
        let secondDay = firstDay.addingTimeInterval(86_400)
        _ = store.reset(
            messages: [
                makeMessage(id: "m3", seq: 3, sentAt: secondDay),
                makeMessage(id: "m4", seq: 4, sentAt: secondDay.addingTimeInterval(60))
            ],
            readBoundarySeq: nil
        )

        let mutation = store.apply(
            messages: [
                makeMessage(id: "m1", seq: 1, sentAt: firstDay),
                makeMessage(id: "m2", seq: 2, sentAt: secondDay.addingTimeInterval(-60))
            ],
            updateType: .older,
            isUserInCurrentRoom: true,
            windowSize: 300
        )

        #expect(messageIDs(in: mutation.items) == ["m1", "m2", "m3", "m4"])
        #expect(mutation.items.filter(isDateSeparator).count == 2)
        #expect(Set(mutation.items).count == mutation.items.count)
    }

    @Test func applyNewerSameDayPageKeepsDateSeparatorIdentityUnique() {
        var store = makeStore()
        let day = Date(timeIntervalSince1970: 100)
        _ = store.reset(
            messages: [makeMessage(id: "m1", seq: 1, sentAt: day)],
            readBoundarySeq: nil
        )

        let mutation = store.apply(
            messages: [makeMessage(id: "m2", seq: 2, sentAt: day.addingTimeInterval(60))],
            updateType: .newer,
            isUserInCurrentRoom: true,
            windowSize: 300
        )

        #expect(messageIDs(in: mutation.items) == ["m1", "m2"])
        #expect(mutation.items.filter(isDateSeparator).count == 1)
        #expect(Set(mutation.items).count == mutation.items.count)
    }

    @Test func reloadUpdatesVisibleMessageAndReturnsReconfiguredItem() {
        var store = makeStore()
        let sentAt = Date(timeIntervalSince1970: 100)
        _ = store.reset(
            messages: [makeMessage(id: "m1", seq: 1, sentAt: sentAt)],
            readBoundarySeq: nil
        )
        var deleted = makeMessage(id: "m1", seq: 1, sentAt: sentAt)
        deleted.isDeleted = true

        let mutation = store.reload(messages: [deleted])

        #expect(mutation.reconfiguredItems.map(\.messageID) == ["m1"])
        #expect(store.message(for: "m1")?.isDeleted == true)
    }

    @Test func highestContiguousSeqStopsAtFirstGap() {
        var store = makeStore()
        let sentAt = Date(timeIntervalSince1970: 100)
        _ = store.reset(
            messages: [
                makeMessage(id: "m11", seq: 11, sentAt: sentAt),
                makeMessage(id: "m12", seq: 12, sentAt: sentAt.addingTimeInterval(1)),
                makeMessage(id: "m14", seq: 14, sentAt: sentAt.addingTimeInterval(2))
            ],
            readBoundarySeq: 10
        )

        #expect(store.highestContiguousSeq(after: 10) == 12)
        #expect(store.highestContiguousSeq(after: 12) == 12)
    }

    @Test func latestWindowReplacementKeepsOnlyUnresolvedFailedLocalMessages() {
        var store = makeStore()
        let sentAt = Date(timeIntervalSince1970: 100)
        var unresolved = makeMessage(id: "failed", seq: 0, sentAt: sentAt)
        unresolved.isFailed = true
        var serverConfirmed = makeMessage(id: "m80", seq: 0, sentAt: sentAt)
        serverConfirmed.isFailed = true

        let window = ChatLatestMessageWindow(
            targetSeq: 80,
            messages: [makeMessage(id: "m80", seq: 80, sentAt: sentAt)]
        )
        let items = store.replaceWithLatestWindow(
            window,
            preservingFailedMessages: [unresolved, serverConfirmed]
        )

        #expect(messageIDs(in: items) == ["m80", "failed"])
        #expect(store.message(for: "m80")?.isFailed == false)
        #expect(store.message(for: "failed")?.isFailed == true)
    }

    private func makeStore() -> ChatMessageWindowStore {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return ChatMessageWindowStore(
            calendar: calendar,
            fallbackDate: { Date(timeIntervalSince1970: 0) }
        )
    }

    private func makeMessage(
        id: String,
        seq: Int64,
        text: String = "message",
        sentAt: Date
    ) -> ChatMessage {
        ChatMessage(
            ID: id,
            seq: seq,
            roomID: "room-1",
            senderUID: "sender@example.com",
            senderEmail: nil,
            senderNickname: "보낸 사람",
            senderAvatarPath: nil,
            msg: text,
            sentAt: sentAt,
            attachments: [],
            replyPreview: nil
        )
    }

    private func messageIDs(in items: [ChatMessageListItem]) -> [String] {
        items.compactMap(\.messageID)
    }

    private func isDateSeparator(_ item: ChatMessageListItem) -> Bool {
        if case .dateSeparator = item { return true }
        return false
    }

    private func isReadMarker(_ item: ChatMessageListItem) -> Bool {
        if case .readMarker = item { return true }
        return false
    }
}
