//
//  ChatMessageWindowStore.swift
//  OutPick
//
//  Created by Codex on 6/18/26.
//

import Foundation

enum ChatMessageWindowUpdateType {
    case older
    case newer
    case reload
    case initial
}

enum ChatMessageListItem: Hashable {
    case message(ChatMessage)
    case dateSeparator(Date)
    case readMarker

    var messageID: String? {
        guard case let .message(message) = self else { return nil }
        return message.ID
    }

    var message: ChatMessage? {
        guard case let .message(message) = self else { return nil }
        return message
    }
}

struct ChatMessageReplacement {
    let previous: ChatMessage
    let next: ChatMessage
}

struct ChatMessageWindowMutation {
    let items: [ChatMessageListItem]
    let insertedItems: [ChatMessageListItem]
    let reconfiguredItems: [ChatMessageListItem]
    let replacements: [ChatMessageReplacement]

    var hasSnapshotChanges: Bool {
        !insertedItems.isEmpty || !reconfiguredItems.isEmpty
    }
}

struct ChatMessageWindowStore {
    private(set) var items: [ChatMessageListItem] = []

    private var messagesByID: [String: ChatMessage] = [:]
    private var lastMessageDate: Date?
    private var readBoundarySeq: Int64?
    private let calendar: Calendar
    private let fallbackDate: () -> Date

    init(
        calendar: Calendar = .current,
        fallbackDate: @escaping () -> Date = { Date() }
    ) {
        self.calendar = calendar
        self.fallbackDate = fallbackDate
    }

    var visibleMessages: [ChatMessage] {
        items.compactMap { item in
            guard let message = item.message else { return nil }
            return messagesByID[message.ID] ?? message
        }
    }

    func message(for messageID: String) -> ChatMessage? {
        messagesByID[messageID]
    }

    func messages(where predicate: (ChatMessage) -> Bool) -> [ChatMessage] {
        visibleMessages.filter(predicate)
    }

    func firstMessageID() -> String? {
        items.compactMap(\.messageID).first
    }

    func lastMessageID() -> String? {
        items.compactMap(\.messageID).last
    }

    func item(forMessageID messageID: String) -> ChatMessageListItem? {
        items.first { $0.messageID == messageID }
    }

    func items(forMessageIDs messageIDs: Set<String>) -> [ChatMessageListItem] {
        guard !messageIDs.isEmpty else { return [] }
        return items.filter { item in
            guard let messageID = item.messageID else { return false }
            return messageIDs.contains(messageID)
        }
    }

    mutating func reset(
        messages: [ChatMessage],
        readBoundarySeq: Int64?
    ) -> [ChatMessageListItem] {
        self.items = []
        self.messagesByID = [:]
        self.lastMessageDate = nil
        self.readBoundarySeq = readBoundarySeq

        let builtItems = buildItems(from: deduped(messages))
        self.items = insertingReadMarkerIfNeeded(into: builtItems, readBoundarySeq: readBoundarySeq)
        pruneMessageMapToVisibleItems()
        return items
    }

    mutating func apply(
        messages: [ChatMessage],
        updateType: ChatMessageWindowUpdateType,
        isUserInCurrentRoom: Bool,
        windowSize: Int
    ) -> ChatMessageWindowMutation {
        guard !messages.isEmpty else {
            return makeMutation()
        }

        if updateType == .reload {
            return reload(messages: messages)
        }

        let dedupedMessages = deduped(messages)
        let existingIDs = Set(items.compactMap(\.messageID))
        let existingMessages = dedupedMessages.filter { existingIDs.contains($0.ID) }
        let incomingMessages = dedupedMessages.filter { !existingIDs.contains($0.ID) }

        var replacements: [ChatMessageReplacement] = []
        var reconfiguredIDs = Set<String>()

        for message in existingMessages {
            if let previous = messagesByID[message.ID] {
                replacements.append(ChatMessageReplacement(previous: previous, next: message))
            }
            replaceStoredMessage(message)
            reconfiguredIDs.insert(message.ID)
        }

        guard !incomingMessages.isEmpty else {
            return makeMutation(
                reconfiguredItems: items(forMessageIDs: reconfiguredIDs),
                replacements: replacements
            )
        }

        let sortedMessages = sortBySentAt(incomingMessages)
        var newItems = buildItems(from: sortedMessages)
        if shouldInsertReadMarker(
            updateType: updateType,
            newMessages: sortedMessages,
            isUserInCurrentRoom: isUserInCurrentRoom
        ) {
            insertReadMarker(into: &newItems)
        }

        insert(newItems, updateType: updateType)
        applyVirtualization(updateType: updateType, windowSize: windowSize)

        return makeMutation(
            insertedItems: newItems,
            reconfiguredItems: items(forMessageIDs: reconfiguredIDs),
            replacements: replacements
        )
    }

    mutating func reload(messages: [ChatMessage]) -> ChatMessageWindowMutation {
        let dedupedMessages = deduped(messages)
        let existingIDs = Set(items.compactMap(\.messageID))
        var targetIDs = Set<String>()

        for message in dedupedMessages where existingIDs.contains(message.ID) {
            replaceStoredMessage(message)
            targetIDs.insert(message.ID)
        }

        return makeMutation(reconfiguredItems: items(forMessageIDs: targetIDs))
    }

    mutating func updateMessage(
        id messageID: String,
        mutate: (inout ChatMessage) -> Void
    ) -> ChatMessage? {
        guard var message = messagesByID[messageID] else { return nil }
        mutate(&message)
        replaceStoredMessage(message)
        return message
    }

    mutating func updateMessages(
        where predicate: (ChatMessage) -> Bool,
        mutate: (inout ChatMessage) -> Void
    ) -> [ChatMessage] {
        let targetIDs = visibleMessages
            .filter(predicate)
            .map(\.ID)

        var updated: [ChatMessage] = []
        for messageID in targetIDs {
            guard var message = messagesByID[messageID] else { continue }
            mutate(&message)
            replaceStoredMessage(message)
            updated.append(message)
        }
        return updated
    }

    mutating func removeReadMarker() -> Bool {
        let originalCount = items.count
        items.removeAll {
            if case .readMarker = $0 { return true }
            return false
        }
        return originalCount != items.count
    }

    private func makeMutation(
        insertedItems: [ChatMessageListItem] = [],
        reconfiguredItems: [ChatMessageListItem] = [],
        replacements: [ChatMessageReplacement] = []
    ) -> ChatMessageWindowMutation {
        ChatMessageWindowMutation(
            items: items,
            insertedItems: insertedItems,
            reconfiguredItems: reconfiguredItems,
            replacements: replacements
        )
    }

    private mutating func buildItems(from messages: [ChatMessage]) -> [ChatMessageListItem] {
        var builtItems: [ChatMessageListItem] = []
        for message in messages {
            messagesByID[message.ID] = message
            let messageDate = day(for: message)
            if lastMessageDate == nil || lastMessageDate != messageDate {
                builtItems.append(.dateSeparator(messageDate))
                lastMessageDate = messageDate
            }
            builtItems.append(.message(message))
        }
        return builtItems
    }

    private mutating func replaceStoredMessage(_ message: ChatMessage) {
        messagesByID[message.ID] = message
        guard let index = items.firstIndex(where: { $0.messageID == message.ID }) else { return }
        items[index] = .message(message)
    }

    private func deduped(_ messages: [ChatMessage]) -> [ChatMessage] {
        var seen = Set<String>()
        var result: [ChatMessage] = []
        result.reserveCapacity(messages.count)
        for message in messages where seen.insert(message.ID).inserted {
            result.append(message)
        }
        return result
    }

    private func sortBySentAt(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.sorted { lhs, rhs in
            (lhs.sentAt ?? fallbackDate()) < (rhs.sentAt ?? fallbackDate())
        }
    }

    private func day(for message: ChatMessage) -> Date {
        calendar.startOfDay(for: message.sentAt ?? fallbackDate())
    }

    private func day(for separatorDate: Date) -> Date {
        calendar.startOfDay(for: separatorDate)
    }

    private func insertingReadMarkerIfNeeded(
        into items: [ChatMessageListItem],
        readBoundarySeq: Int64?
    ) -> [ChatMessageListItem] {
        guard let readBoundarySeq else { return items }
        guard !items.contains(where: isReadMarker) else { return items }
        guard let insertIndex = items.firstIndex(where: { item in
            guard case let .message(message) = item else { return false }
            return message.seq > readBoundarySeq
        }) else {
            return items
        }

        var updated = items
        updated.insert(.readMarker, at: insertIndex)
        return updated
    }

    private func shouldInsertReadMarker(
        updateType: ChatMessageWindowUpdateType,
        newMessages: [ChatMessage],
        isUserInCurrentRoom: Bool
    ) -> Bool {
        guard updateType == .newer,
              !items.contains(where: isReadMarker),
              let readBoundarySeq,
              !isUserInCurrentRoom,
              let firstMessage = newMessages.first else {
            return false
        }
        return firstMessage.seq > readBoundarySeq
    }

    private func insertReadMarker(into newItems: inout [ChatMessageListItem]) {
        guard let firstMessageIndex = newItems.firstIndex(where: { item in
            if case .message = item { return true }
            return false
        }) else {
            return
        }
        newItems.insert(.readMarker, at: firstMessageIndex)
    }

    private mutating func insert(
        _ newItems: [ChatMessageListItem],
        updateType: ChatMessageWindowUpdateType
    ) {
        switch updateType {
        case .older:
            items.insert(contentsOf: newItems, at: 0)
        case .newer, .reload, .initial:
            items.append(contentsOf: newItems)
        }
    }

    private mutating func applyVirtualization(
        updateType: ChatMessageWindowUpdateType,
        windowSize: Int
    ) {
        guard items.count > windowSize else {
            removeOrphanDateSeparators()
            pruneMessageMapToVisibleItems()
            return
        }

        let removeCount = items.count - windowSize
        switch updateType {
        case .older:
            items.removeLast(removeCount)
        case .newer:
            items.removeFirst(removeCount)
        case .reload, .initial:
            break
        }

        removeOrphanDateSeparators()
        pruneMessageMapToVisibleItems()
    }

    private mutating func removeOrphanDateSeparators() {
        let calendar = self.calendar
        let fallbackDate = self.fallbackDate
        let presentMessageDates = Set(
            items.compactMap { item -> Date? in
                guard case let .message(message) = item else { return nil }
                return calendar.startOfDay(for: message.sentAt ?? fallbackDate())
            }
        )

        items.removeAll { item in
            guard case let .dateSeparator(date) = item else { return false }
            return !presentMessageDates.contains(calendar.startOfDay(for: date))
        }
    }

    private mutating func pruneMessageMapToVisibleItems() {
        let visibleIDs = Set(items.compactMap(\.messageID))
        messagesByID = messagesByID.filter { visibleIDs.contains($0.key) }
    }

    private func isReadMarker(_ item: ChatMessageListItem) -> Bool {
        if case .readMarker = item { return true }
        return false
    }
}
