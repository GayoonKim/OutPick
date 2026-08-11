import Foundation

struct ChatVisibleUnreadSummary: Equatable {
    let roomID: String
    let latestSeq: Int64
    let visibleUnreadCount: Int64
    let latestVisibleMessage: ChatMessage?
}

protocol ChatVisibleUnreadUseCaseProtocol {
    func execute(
        room: ChatRoom,
        after lastReadSeq: Int64,
        through latestSeq: Int64,
        currentUserID: String,
        blockedUserIDs: Set<String>
    ) async throws -> ChatVisibleUnreadSummary
}

final class ChatVisibleUnreadUseCase: ChatVisibleUnreadUseCaseProtocol {
    private let messageRepository: any FirebaseMessageRepositoryProtocol
    private let pageSize: Int

    init(
        messageRepository: any FirebaseMessageRepositoryProtocol,
        pageSize: Int = 100
    ) {
        self.messageRepository = messageRepository
        self.pageSize = max(1, pageSize)
    }

    func execute(
        room: ChatRoom,
        after lastReadSeq: Int64,
        through latestSeq: Int64,
        currentUserID: String,
        blockedUserIDs: Set<String>
    ) async throws -> ChatVisibleUnreadSummary {
        guard latestSeq > lastReadSeq else {
            return ChatVisibleUnreadSummary(
                roomID: room.id,
                latestSeq: latestSeq,
                visibleUnreadCount: 0,
                latestVisibleMessage: nil
            )
        }

        var cursor = lastReadSeq
        var visibleUnreadCount: Int64 = 0
        var latestVisibleMessage: ChatMessage?

        while cursor < latestSeq {
            try Task.checkCancellation()
            let page = try await messageRepository.fetchMessagesAfterSeq(
                room: room,
                afterSeq: cursor,
                limit: pageSize
            )
            let ordered = page
                .filter { $0.seq > cursor && $0.seq <= latestSeq }
                .sorted { $0.seq < $1.seq }

            guard let pageLastSeq = ordered.last?.seq else { break }

            for message in ordered where isVisibleUnread(
                message,
                currentUserID: currentUserID,
                blockedUserIDs: blockedUserIDs
            ) {
                visibleUnreadCount += 1
                latestVisibleMessage = message
            }

            guard pageLastSeq > cursor else { break }
            cursor = pageLastSeq
            if page.count < pageSize { break }
        }

        return ChatVisibleUnreadSummary(
            roomID: room.id,
            latestSeq: latestSeq,
            visibleUnreadCount: visibleUnreadCount,
            latestVisibleMessage: latestVisibleMessage
        )
    }

    private func isVisibleUnread(
        _ message: ChatMessage,
        currentUserID: String,
        blockedUserIDs: Set<String>
    ) -> Bool {
        guard message.seq > 0, !message.isDeleted else { return false }
        guard message.senderUID != currentUserID else { return false }
        return !blockedUserIDs.contains(message.senderUID)
    }
}
