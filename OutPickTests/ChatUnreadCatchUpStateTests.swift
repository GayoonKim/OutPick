//
//  ChatUnreadCatchUpStateTests.swift
//  OutPickTests
//
//  Created by Codex on 7/17/26.
//

import Testing
@testable import OutPick

struct ChatUnreadCatchUpStateTests {
    @Test func initialStateNormalizesSeqAndCalculatesUnreadCount() {
        let state = ChatUnreadCatchUpState(
            knownLatestSeq: 10_010,
            readFrontierSeq: 10
        )

        #expect(state.knownLatestSeq == 10_010)
        #expect(state.readFrontierSeq == 10)
        #expect(state.unreadCount == 10_000)
        #expect(state.canBeginLatestJump == false)

        let normalized = ChatUnreadCatchUpState(
            knownLatestSeq: -1,
            readFrontierSeq: -2
        )
        #expect(normalized.knownLatestSeq == 0)
        #expect(normalized.readFrontierSeq == 0)
    }

    @Test func unreadCountPreservesExactValueWithoutVisualCap() {
        let state = ChatUnreadCatchUpState(
            knownLatestSeq: 9_999,
            readFrontierSeq: 0
        )

        #expect(state.unreadCount == 9_999)
    }

    @Test func latestObservationAndFrontierSyncAreMonotonic() {
        var state = ChatUnreadCatchUpState(
            knownLatestSeq: 20,
            readFrontierSeq: 10
        )

        state.observeLatestSeq(15)
        state.observeLatestSeq(25)
        state.syncReadFrontier(8)
        state.syncReadFrontier(22)

        #expect(state.knownLatestSeq == 25)
        #expect(state.readFrontierSeq == 22)
        #expect(state.unreadCount == 3)
    }

    @Test func latestJumpFreezesTargetWhileNewMessagesArrive() throws {
        var state = ChatUnreadCatchUpState(
            knownLatestSeq: 10_010,
            readFrontierSeq: 10,
            latestPreview: .generic(targetSeq: 10_010, text: "현재 realtime")
        )

        let optionalRequest = state.beginLatestJump()
        let request = try #require(optionalRequest)
        state.observeLatestSeq(10_013)
        let approvedTarget = state.completeLatestJump(
            generation: request.generation,
            didDisplayTarget: true
        )

        #expect(request.targetSeq == 10_010)
        #expect(approvedTarget == 10_010)
        #expect(state.knownLatestSeq == 10_013)
        #expect(state.readFrontierSeq == 10)
        #expect(state.isJumpLoading == false)

        state.syncReadFrontier(try #require(approvedTarget))
        #expect(state.unreadCount == 3)
    }

    @Test func failedDisplayDoesNotApproveTargetAndAllowsRetry() throws {
        var state = ChatUnreadCatchUpState(
            knownLatestSeq: 100,
            readFrontierSeq: 10,
            latestPreview: .generic(targetSeq: 100, text: "현재 realtime")
        )

        let optionalFirst = state.beginLatestJump()
        let first = try #require(optionalFirst)
        let approved = state.completeLatestJump(
            generation: first.generation,
            didDisplayTarget: false
        )
        let optionalRetry = state.beginLatestJump()
        let retry = try #require(optionalRetry)

        #expect(approved == nil)
        #expect(state.readFrontierSeq == 10)
        #expect(retry.targetSeq == 100)
        #expect(retry.generation != first.generation)
    }

    @Test func staleCompletionAndFailureCannotClearCurrentJump() throws {
        var state = ChatUnreadCatchUpState(
            knownLatestSeq: 100,
            readFrontierSeq: 10,
            latestPreview: .generic(targetSeq: 100, text: "현재 realtime")
        )

        let optionalFirst = state.beginLatestJump()
        let first = try #require(optionalFirst)
        state.cancelLatestJump()
        let optionalSecond = state.beginLatestJump()
        let second = try #require(optionalSecond)

        let staleCompletion = state.completeLatestJump(
            generation: first.generation,
            didDisplayTarget: true
        )
        let staleFailure = state.failLatestJump(generation: first.generation)

        #expect(staleCompletion == nil)
        #expect(staleFailure == false)
        #expect(state.isJumpLoading)
        #expect(state.jumpTargetSeq == second.targetSeq)
        let currentFailure = state.failLatestJump(generation: second.generation)
        #expect(currentFailure)
        #expect(state.isJumpLoading == false)
    }

    @Test func duplicateBeginIsRejectedWhileJumpIsLoading() throws {
        var state = ChatUnreadCatchUpState(
            knownLatestSeq: 100,
            readFrontierSeq: 10,
            latestPreview: .generic(targetSeq: 100, text: "현재 realtime")
        )

        let optionalRequest = state.beginLatestJump()
        _ = try #require(optionalRequest)
        let duplicateRequest = state.beginLatestJump()

        #expect(duplicateRequest == nil)
    }

    @Test func noUnreadDoesNotCreateJumpRequest() {
        var state = ChatUnreadCatchUpState(
            knownLatestSeq: 100,
            readFrontierSeq: 100
        )

        let request = state.beginLatestJump()

        #expect(state.canBeginLatestJump == false)
        #expect(request == nil)
    }

    @Test func knownUnreadWithoutRealtimePreviewDoesNotCreateJumpRequest() {
        var state = ChatUnreadCatchUpState(
            knownLatestSeq: 100,
            readFrontierSeq: 10
        )

        let request = state.beginLatestJump()

        #expect(state.unreadCount == 90)
        #expect(state.canBeginLatestJump == false)
        #expect(request == nil)
    }

    @Test func tenThousandLatestEventsOnlyAdvanceScalarWatermark() {
        var state = ChatUnreadCatchUpState()

        for seq in Int64(1)...Int64(10_000) {
            state.observeLatestSeq(seq)
        }

        #expect(state.knownLatestSeq == 10_000)
        #expect(state.unreadCount == 10_000)
        #expect(state.jumpTargetSeq == nil)
        #expect(state.isJumpLoading == false)
    }

    @Test func latestMessagePreviewKeepsOnlyNewestSummaryAndFrozenRequestTarget() throws {
        var state = ChatUnreadCatchUpState(
            knownLatestSeq: 10,
            readFrontierSeq: 0,
            latestPreview: .generic(targetSeq: 10, text: "기존 메시지")
        )

        let optionalRequest = state.beginLatestJump()
        let request = try #require(optionalRequest)
        state.observeLatestMessage(makeMessage(seq: 11, text: "새 메시지"))

        #expect(request.targetSeq == 10)
        #expect(state.knownLatestSeq == 11)
        #expect(state.latestPreview?.targetSeq == 11)
        #expect(state.latestPreview?.senderName == "sender")
        #expect(state.latestPreview?.text == "새 메시지")
        #expect(state.latestPreview?.kind == .text)
        #expect(state.jumpPreview?.targetSeq == 10)
        #expect(state.jumpPreview?.text == "기존 메시지")
        #expect(state.presentedPreview?.targetSeq == 10)

        _ = state.completeLatestJump(
            generation: request.generation,
            didDisplayTarget: true
        )

        #expect(state.jumpPreview == nil)
        #expect(state.presentedPreview?.targetSeq == 11)
    }

    @Test func mismatchedInitialPreviewIsDiscarded() {
        let state = ChatUnreadCatchUpState(
            knownLatestSeq: 20,
            readFrontierSeq: 10,
            latestPreview: .generic(targetSeq: 19, text: "오래된 summary")
        )

        #expect(state.latestPreview == nil)
    }

    @Test func staleAutoDismissDoesNotHideNewerRealtimePreview() throws {
        var state = ChatUnreadCatchUpState(
            knownLatestSeq: 10,
            readFrontierSeq: 0
        )
        state.observeLatestMessage(makeMessage(seq: 11, text: "첫 메시지"))
        state.observeLatestMessage(makeMessage(seq: 12, text: "두 번째 메시지"))

        let dismissedStalePreview = state.dismissRealtimePreview(targetSeq: 11)
        #expect(dismissedStalePreview == false)
        #expect(state.latestPreview?.targetSeq == 12)
        let dismissedCurrentPreview = state.dismissRealtimePreview(targetSeq: 12)
        #expect(dismissedCurrentPreview)
        #expect(state.latestPreview == nil)
        #expect(state.knownLatestSeq == 12)
        #expect(state.unreadCount == 12)
    }

    private func makeMessage(seq: Int64, text: String) -> ChatMessage {
        ChatMessage(
            ID: "message-\(seq)",
            seq: seq,
            roomID: "room-1",
            senderUID: "sender-uid",
            senderEmail: nil,
            senderNickname: "sender",
            senderAvatarPath: nil,
            msg: text,
            sentAt: nil,
            attachments: [],
            replyPreview: nil
        )
    }
}
