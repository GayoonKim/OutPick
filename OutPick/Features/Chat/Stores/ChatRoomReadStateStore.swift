//
//  ChatRoomReadStateStore.swift
//  OutPick
//
//  Created by Codex on 6/18/26.
//

import Foundation

struct ChatRoomReadSnapshot: Equatable {
    let roomID: String
    var latestSeq: Int64?
    var lastReadSeq: Int64?
    var lastMessageSenderID: String?

    func unreadCount(currentUserID: String) -> Int64? {
        guard let latestSeq, let lastReadSeq else { return nil }

        var unread = max(Int64(0), latestSeq - lastReadSeq)
        if unread > 0,
           let lastMessageSenderID,
           !lastMessageSenderID.isEmpty,
           lastMessageSenderID == currentUserID {
            unread = max(Int64(0), unread - 1)
        }
        return unread
    }
}

struct ChatRoomReadStateChange: Equatable {
    let roomID: String
    let snapshot: ChatRoomReadSnapshot
}

@MainActor
final class ChatRoomReadStateStore {
    private var snapshots: [String: ChatRoomReadSnapshot] = [:]
    private var continuations: [UUID: (roomIDs: Set<String>?, continuation: AsyncStream<ChatRoomReadStateChange>.Continuation)] = [:]

    func snapshot(for roomID: String) -> ChatRoomReadSnapshot? {
        snapshots[roomID]
    }

    func readStateChangeStream(for roomIDs: Set<String>? = nil) -> AsyncStream<ChatRoomReadStateChange> {
        if let roomIDs, roomIDs.isEmpty {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        return AsyncStream { [weak self] continuation in
            guard let self else { return }
            let continuationID = UUID()
            continuations[continuationID] = (roomIDs, continuation)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.continuations.removeValue(forKey: continuationID)
                }
            }
        }
    }

    @discardableResult
    func seed(_ snapshot: ChatRoomReadSnapshot) -> ChatRoomReadSnapshot {
        guard !snapshot.roomID.isEmpty else { return snapshot }
        return update(roomID: snapshot.roomID) { current in
            current.latestSeq = snapshot.latestSeq
            current.lastReadSeq = snapshot.lastReadSeq
            current.lastMessageSenderID = snapshot.lastMessageSenderID
        }
    }

    @discardableResult
    func seedLatest(
        roomID: String,
        latestSeq: Int64?,
        lastMessageSenderID: String?
    ) -> ChatRoomReadSnapshot? {
        guard !roomID.isEmpty else { return nil }
        return update(roomID: roomID) { current in
            if let latestSeq, latestSeq > 0 {
                if let existing = current.latestSeq, existing > latestSeq {
                    return
                }
                current.latestSeq = latestSeq
                current.lastMessageSenderID = lastMessageSenderID
            } else if current.latestSeq == nil {
                current.lastMessageSenderID = lastMessageSenderID
            }
        }
    }

    @discardableResult
    func markReadFlushed(roomID: String, lastReadSeq: Int64) -> ChatRoomReadSnapshot? {
        guard !roomID.isEmpty, lastReadSeq > 0 else { return nil }
        return update(roomID: roomID) { current in
            if let existing = current.lastReadSeq, existing >= lastReadSeq {
                return
            }
            current.lastReadSeq = lastReadSeq
        }
    }

    func remove(roomID: String) {
        snapshots.removeValue(forKey: roomID)
    }

    func clear() {
        snapshots.removeAll()
    }

    private func update(
        roomID: String,
        mutate: (inout ChatRoomReadSnapshot) -> Void
    ) -> ChatRoomReadSnapshot {
        var snapshot = snapshots[roomID] ?? ChatRoomReadSnapshot(
            roomID: roomID,
            latestSeq: nil,
            lastReadSeq: nil,
            lastMessageSenderID: nil
        )
        let previous = snapshot
        mutate(&snapshot)
        snapshots[roomID] = snapshot

        if snapshot != previous {
            notify(ChatRoomReadStateChange(roomID: roomID, snapshot: snapshot))
        }
        return snapshot
    }

    private func notify(_ change: ChatRoomReadStateChange) {
        for entry in continuations.values {
            if let roomIDs = entry.roomIDs, !roomIDs.contains(change.roomID) {
                continue
            }
            entry.continuation.yield(change)
        }
    }
}
