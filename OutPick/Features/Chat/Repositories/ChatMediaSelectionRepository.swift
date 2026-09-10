import Foundation

/// 선택 원본의 소유권을 기록한다. child outbox가 영속화된 뒤에만 parent에서 원본을 소비한다.
actor ChatMediaSelectionRepository {
    private let persistence: ChatOutgoingOutboxPersisting
    private let root: URL

    init(persistence: ChatOutgoingOutboxPersisting, root: URL) {
        self.persistence = persistence
        self.root = root
    }

    func directory(_ id: String) throws -> URL {
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try url.setResourceValues(values)
        return directory
    }

    func save(_ selection: ChatMediaSelection) async throws {
        let json = String(decoding: try JSONEncoder().encode(selection), as: UTF8.self)
        try await persistence.saveOutgoingOutboxRecord(.init(
            messageID: selection.selectionID, roomID: selection.roomID, kind: .images,
            stage: .failed, createdAt: selection.createdAt, updatedAt: Date(),
            localPayloadJSON: json, uploadedPayloadJSON: nil, lastError: nil,
            expiresAt: selection.createdAt.addingTimeInterval(7 * 24 * 60 * 60)
        ))
    }

    func load(_ id: String) async throws -> ChatMediaSelection? {
        guard let record = try await persistence.fetchOutgoingOutboxRecord(messageID: id) else { return nil }
        return ChatMediaSelection.decode(record)
    }

    func restored(roomID: String, senderUID: String, excluding activeIDs: Set<String> = []) async throws -> [ChatMediaSelection] {
        let records = try await persistence.fetchOutgoingOutboxRecords(roomID: roomID)
        var selections: [ChatMediaSelection] = []
        for record in records {
            guard !activeIDs.contains(record.messageID),
                  var selection = ChatMediaSelection.decode(record), selection.senderUID == senderUID else { continue }
            if selection.createdAt.addingTimeInterval(7 * 24 * 60 * 60) < Date() {
                try await remove(selection.selectionID)
                continue
            }
            if let pending = selection.pendingChunk,
               let child = try await persistence.fetchOutgoingOutboxRecord(messageID: pending.messageID),
               child.localPayloadJSON != nil {
                selection.selectionSources.removeAll { pending.indices.contains($0.index) }
                selection.pendingChunk = nil
                try await save(selection)
            }
            if selection.selectionSources.isEmpty {
                try await remove(selection.selectionID)
            } else {
                selections.append(selection)
            }
        }
        return selections.sorted { $0.createdAt < $1.createdAt }
    }

    func childPreserved(_ id: String) async throws -> Bool {
        let record = try await persistence.fetchOutgoingOutboxRecord(messageID: id)
        return record?.localPayloadJSON != nil
    }

    func remove(_ id: String) async throws {
        // 파일 삭제 후 DB 삭제가 실패해도 없어진 원본으로 버블을 복원하지 않는다.
        if var selection = try await load(id) {
            selection.selectionSources = []
            selection.pendingChunk = nil
            try await save(selection)
        }
        let path = root.appendingPathComponent(id, isDirectory: true)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
        try await persistence.deleteOutgoingOutboxRecord(messageID: id)
    }
}
