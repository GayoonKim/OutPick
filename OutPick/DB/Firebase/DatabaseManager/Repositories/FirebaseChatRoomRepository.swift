//
//  FirebaseChatRoomRepository.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import FirebaseFirestore

final class FirebaseChatRoomRepository: FirebaseChatRoomRepositoryProtocol {
    private let db: Firestore
    
    // 채팅방 목록 캐시
    private(set) var topRoomsWithPreviews: [(ChatRoom, [ChatMessage])] = []
    private var previewByRoomID: [String: [ChatMessage]] = [:]
    
    // 페이지네이션 상태
    private var lastFetchedRoomSnapshot: DocumentSnapshot?
    private var lastSearchSnapshot: DocumentSnapshot?
    private var currentSearchKeyword: String = ""
    
    // 작업 관리
    private var removeParticipantTask: Task<Void, Never>?
    
    init(db: Firestore) {
        self.db = db
    }

    static func eligiblePreviewMessages(
        fromNewestFirst messages: [ChatMessage],
        limit: Int
    ) -> [ChatMessage] {
        guard limit > 0 else { return [] }
        return Array(
            messages
                .filter(\.isEligibleForRoomListPreview)
                .prefix(limit)
                .reversed()
        )
    }
    
    deinit {
        removeParticipantTask?.cancel()
    }
    
    func applyLocalRoomUpdate(_ updatedRoom: ChatRoom) {
        guard !updatedRoom.id.isEmpty else { return }
        if let idx = topRoomsWithPreviews.firstIndex(where: { $0.0.id == updatedRoom.id }) {
            let previews = topRoomsWithPreviews[idx].1
            topRoomsWithPreviews[idx] = (updatedRoom, previews)
        }

    }

    func removeLocalRoom(roomID: String) {
        guard !roomID.isEmpty else { return }
        topRoomsWithPreviews.removeAll { $0.0.id == roomID }
        previewByRoomID.removeValue(forKey: roomID)
    }

    func applyLocalIncomingMessagePreview(_ message: ChatMessage) {
        let roomID = message.roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !roomID.isEmpty, message.isEligibleForRoomListPreview else { return }

        let existingPreviews = previewByRoomID[roomID] ?? []
        let withoutDuplicate = existingPreviews.filter { $0.ID != message.ID }
        let nextPreviews = Array((withoutDuplicate + [message]).suffix(3))
        previewByRoomID[roomID] = nextPreviews

        guard let index = topRoomsWithPreviews.firstIndex(where: { $0.0.id == roomID }) else { return }
        var room = topRoomsWithPreviews[index].0
        if message.seq > room.seq {
            room.seq = message.seq
        }
        room.lastMessageAt = message.sentAt ?? Date()
        room.lastMessage = message.previewTextForRoomList
        room.lastMessageSenderUID = message.senderUID

        topRoomsWithPreviews[index] = (room, nextPreviews)
        topRoomsWithPreviews.sort {
            ($0.0.lastMessageAt ?? $0.0.createdAt) > ($1.0.lastMessageAt ?? $1.0.createdAt)
        }
    }
    
    @MainActor
    func fetchTopRoomsPage(after lastSnapshot: DocumentSnapshot? = nil, limit: Int = 30) async throws {
        var query: Query = activeRoomsQuery()
            .order(by: "lastMessageAt", descending: true)
            .limit(to: limit)
        
        if let lastSnapshot {
            query = query.start(afterDocument: lastSnapshot)
        }
        
        let snapshot = try await query.getDocuments()
        
        let rooms: [ChatRoom] = snapshot.documents.compactMap { doc in
            do {
                return try self.createRoom(from: doc)
            } catch {
                print("⚠️ Room decode failed: \(error), id=\(doc.documentID)")
                return nil
            }
        }
        
        // 각 방의 최근 메시지 3개 동시 로드
        let previewsByRoomID: [String: [ChatMessage]] = await withTaskGroup(of: (String, [ChatMessage]).self) { group in
            for r in rooms {
                let rid = r.id
                guard !rid.isEmpty else { continue }
                group.addTask { [weak self] in
                    guard let self = self else { return ("", []) }
                    let msgs = await self.fetchPreviewMessages(roomID: rid, limit: 3)
                    return (rid, msgs)
                }
            }
            
            var acc: [String: [ChatMessage]] = [:]
            for await (rid, msgs) in group {
                guard !rid.isEmpty else { continue }
                acc[rid] = msgs
            }
            return acc
        }
        
        self.previewByRoomID = previewsByRoomID
        self.topRoomsWithPreviews = rooms.map { room in
            let rid = room.id
            let previews = previewsByRoomID[rid] ?? []
            return (room, previews)
        }
        
        self.lastFetchedRoomSnapshot = snapshot.documents.last
    }
    
    private func fetchPreviewMessages(roomID: String, limit: Int) async -> [ChatMessage] {
        guard limit > 0 else { return [] }
        let messagesRef = db.collection("Rooms").document(roomID).collection("Messages")
        
        func decode(_ snap: QuerySnapshot) -> [ChatMessage] {
            let arr: [ChatMessage] = snap.documents.compactMap { doc in
                var dict = doc.data()
                if dict["ID"] == nil { dict["ID"] = doc.documentID }
                if let msg = ChatMessage.from(dict) { return msg }
                do { return try doc.data(as: ChatMessage.self) }
                catch {
                    print("⚠️ preview decode failed: \(error), docID: \(doc.documentID)")
                    return nil
                }
            }
            return arr
        }
        
        func fetchEligibleMessages(orderBy field: String) async throws -> (
            messages: [ChatMessage],
            foundDocuments: Bool
        ) {
            var collected: [ChatMessage] = []
            var cursor: DocumentSnapshot?
            var scannedCount = 0
            var foundDocuments = false
            let maximumScanCount = max(30, limit * 10)

            while collected.count < limit, scannedCount < maximumScanCount {
                var query: Query = messagesRef
                    .order(by: field, descending: true)
                    .limit(to: min(limit, maximumScanCount - scannedCount))
                if let cursor {
                    query = query.start(afterDocument: cursor)
                }

                let snapshot = try await query.getDocuments()
                guard !snapshot.documents.isEmpty else { break }

                foundDocuments = true
                scannedCount += snapshot.documents.count
                cursor = snapshot.documents.last
                collected.append(contentsOf: decode(snapshot).filter(\.isEligibleForRoomListPreview))

                if snapshot.documents.count < limit { break }
            }

            return (
                Self.eligiblePreviewMessages(fromNewestFirst: collected, limit: limit),
                foundDocuments
            )
        }

        // 1) seq 기반 시도
        do {
            let result = try await fetchEligibleMessages(orderBy: "seq")
            if result.foundDocuments { return result.messages }
        } catch {
            // 계속 폴백 시도
        }
        
        // 2) sentAt 기반 폴백
        do {
            return try await fetchEligibleMessages(orderBy: "sentAt").messages
        } catch {
            print("⚠️ _fetchPreviewMessages fallback failed (roomID=\(roomID)): \(error)")
            return []
        }
    }
    
    @MainActor
    func updateRoomLastMessage(roomID: String, date: Date? = nil, msg: String, senderUID: String? = nil) async {
        guard !roomID.isEmpty else {
            print("❌ updateRoomLastMessageAt: roomID is empty")
            return
        }
        
        do {
            let ref = db.collection("Rooms").document(roomID)
            var updateData: [String: Any] = [:]
            
            updateData["lastMessage"] = msg
            if let senderUID, !senderUID.isEmpty {
                updateData["lastMessageSenderUID"] = senderUID
            }
            if let date = date {
                updateData["lastMessageAt"] = Timestamp(date: date)
            } else {
                updateData["lastMessageAt"] = FieldValue.serverTimestamp()
            }
            updateData["updatedAt"] = FieldValue.serverTimestamp()
            
            try await ref.updateData(updateData)
            print("✅ lastMessageAt 업데이트 성공 → \(roomID)")
        } catch {
            print("🔥 lastMessageAt 업데이트 실패: \(error)")
        }
    }

    func updateRoomMetadata(
        roomID: String,
        roomName: String,
        roomDescription: String
    ) async throws {
        let searchIndex = Self.searchIndexData(roomName: roomName, roomDescription: roomDescription)
        try await updateRoomDocument(
            roomID: roomID,
            data: [
                "roomName": roomName,
                "roomDescription": roomDescription,
                "updatedAt": FieldValue.serverTimestamp()
            ].merging(searchIndex) { _, new in new }
        )
    }

    func updateRoomMetadataWithImagePaths(
        roomID: String,
        roomName: String,
        roomDescription: String,
        thumbPath: String,
        originalPath: String
    ) async throws {
        let searchIndex = Self.searchIndexData(roomName: roomName, roomDescription: roomDescription)
        try await updateRoomDocument(
            roomID: roomID,
            data: [
                "thumbPath": thumbPath,
                "originalPath": originalPath,
                "roomName": roomName,
                "roomDescription": roomDescription,
                "updatedAt": FieldValue.serverTimestamp()
            ].merging(searchIndex) { _, new in new }
        )
    }

    func removeRoomImagePathsAndUpdateMetadata(
        roomID: String,
        roomName: String,
        roomDescription: String
    ) async throws {
        let searchIndex = Self.searchIndexData(roomName: roomName, roomDescription: roomDescription)
        try await updateRoomDocument(
            roomID: roomID,
            data: [
                "thumbPath": FieldValue.delete(),
                "originalPath": FieldValue.delete(),
                "roomName": roomName,
                "roomDescription": roomDescription,
                "updatedAt": FieldValue.serverTimestamp()
            ].merging(searchIndex) { _, new in new }
        )
    }
    
    func createRoom(input: CreateChatRoomInput) async throws -> ChatRoom {
        let creatorUID = input.creatorUID.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomName = input.roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !roomName.isEmpty,
              !creatorUID.isEmpty,
              !creatorUID.contains("/") else {
            throw FirebaseError.FailedToFetchRoom
        }

        let roomID = db.collection("Rooms").document().documentID
        let roomRef = db.collection("Rooms").document(roomID)
        let memberRef = roomRef.collection("members").document(creatorUID)
        let joinedRoomRef = db.collection("users")
            .document(creatorUID)
            .collection("joinedRooms")
            .document(roomID)
        let room = ChatRoom(
            id: roomID,
            roomName: input.roomName,
            roomDescription: input.roomDescription,
            participants: [creatorUID],
            ownerUID: creatorUID,
            createdAt: input.createdAt,
            lastMessageAt: input.createdAt,
            memberCount: 1
        )

        do {
            _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                transaction.setData(
                    ChatRoomFirestoreMapper.creationData(from: room),
                    forDocument: roomRef
                )
                transaction.setData([
                    "userID": creatorUID,
                    "role": "owner",
                    "joinedAt": FieldValue.serverTimestamp(),
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: memberRef)
                transaction.setData([
                    "roomID": roomID,
                    "role": "owner",
                    "joinedAt": FieldValue.serverTimestamp(),
                    "isClosed": false,
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: joinedRoomRef)
                return nil
            })

            return room
        } catch {
            print("🔥 createRoom 실패: \(error)")
            throw error
        }
    }
    
    func fetchRoomsWithIDs(byIDs ids: [String]) async throws -> [ChatRoom] {
        guard !ids.isEmpty else { return [] }
        var result: [ChatRoom] = []
        var start = 0
        
        while start < ids.count {
            let end = min(start + 10, ids.count)
            let chunk = Array(ids[start..<end])
            start = end
            
            let snap = try await activeRoomsQuery()
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            
            let rooms = snap.documents.compactMap { doc -> ChatRoom? in
                do {
                    return try self.createRoom(from: doc)
                } catch {
                    print("⚠️ fetchRoomsWithIDs decode failed:", error, "docID:", doc.documentID)
                    return nil
                }
            }
            result.append(contentsOf: rooms)
        }
        
        return result
    }
    
    func searchRooms(keyword: String, limit: Int = 30, reset: Bool = true) async throws -> RoomSearchPage {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty else {
            lastSearchSnapshot = nil
            currentSearchKeyword = ""
            return RoomSearchPage(rooms: [], hasMore: false)
        }
        guard let tokenQuery = ChatRoomSearchIndex.queryToken(for: trimmedKeyword) else {
            lastSearchSnapshot = nil
            currentSearchKeyword = ""
            return RoomSearchPage(rooms: [], hasMore: false)
        }
        
        if reset {
            lastSearchSnapshot = nil
            currentSearchKeyword = trimmedKeyword
        }
        
        var indexedQuery: Query = activeRoomsQuery()
            .whereField(tokenQuery.field, arrayContains: tokenQuery.token)
            .order(by: "lastMessageAt", descending: true)
            .limit(to: limit)

        if let last = lastSearchSnapshot {
            indexedQuery = indexedQuery.start(afterDocument: last)
        }
        
        let indexedSnapshot = try await indexedQuery.getDocuments()
        lastSearchSnapshot = indexedSnapshot.documents.last
        
        let rooms = indexedSnapshot.documents.compactMap { doc -> ChatRoom? in
            try? createRoom(from: doc)
        }
        .filter { ChatRoomSearchIndex.contains(room: $0, keyword: trimmedKeyword) }

        return RoomSearchPage(
            rooms: rooms,
            hasMore: indexedSnapshot.documents.count == limit
        )
    }
    
    func loadMoreSearchRooms(limit: Int = 30) async throws -> RoomSearchPage {
        guard !currentSearchKeyword.isEmpty else {
            return RoomSearchPage(rooms: [], hasMore: false)
        }
        return try await searchRooms(keyword: currentSearchKeyword, limit: limit, reset: false)
    }

    func fetchJoinedRoomList(userUID: String) async throws -> [JoinedRoomListItem] {
        let normalizedUID = userUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUID.isEmpty else { return [] }

        let projectionSnapshot = try await db.collection("users")
            .document(normalizedUID)
            .collection("joinedRooms")
            .getDocuments()

        let projections = projectionSnapshot.documents.compactMap { doc in
            JoinedRoomProjection(documentID: doc.documentID, data: doc.data())
        }
        guard !projections.isEmpty else { return [] }

        let roomIDs = projections.map(\.roomID)
        var rooms = try await fetchRoomsWithIDs(byIDs: roomIDs)
        let activeRoomIDs = Set(rooms.map(\.id))
        for roomID in roomIDs where !activeRoomIDs.contains(roomID) {
            do {
                let snapshot = try await db.collection("Rooms").document(roomID).getDocument()
                guard snapshot.exists,
                      snapshot.data()?["isClosed"] as? Bool == true,
                      let room = try? createRoom(from: snapshot),
                      !(room.closureType == .closedByOwner && room.ownerUID == normalizedUID) else {
                    continue
                }
                rooms.append(room)
            } catch {
                // 만료 cleanup과 목록 조회가 경합하면 이미 사라진 tombstone은 건너뛴다.
                continue
            }
        }
        let roomByID = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })

        return projections.compactMap { projection in
            guard let room = roomByID[projection.roomID] else { return nil }
            return JoinedRoomListItem(room: room, projection: projection)
        }
        .sorted { lhs, rhs in
            (lhs.room.lastMessageAt ?? lhs.room.createdAt) > (rhs.room.lastMessageAt ?? rhs.room.createdAt)
        }
    }

    func fetchRoomMembersPage(roomID: String, limit: Int, afterUserID: String?) async throws -> RoomMemberPage {
        let trimmedRoomID = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRoomID.isEmpty, !trimmedRoomID.contains("/"), limit > 0 else {
            throw FirebaseError.FailedToFetchRoom
        }

        var query: Query = db.collection("Rooms")
            .document(trimmedRoomID)
            .collection("members")
            .order(by: FieldPath.documentID())
            .limit(to: limit)

        if let afterUserID {
            let cursorUserID = afterUserID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cursorUserID.isEmpty, !cursorUserID.contains("/") {
                query = query.start(after: [cursorUserID])
            }
        }

        let snapshot = try await query.getDocuments()

        let members = snapshot.documents.compactMap(Self.roomMemberSummary)

        return RoomMemberPage(
            members: members,
            nextCursorUserID: snapshot.documents.last?.documentID,
            hasMore: snapshot.documents.count == limit
        )
    }

    func fetchPinnedRoomMembers(
        roomID: String,
        currentUserID: String,
        ownerUID: String
    ) async throws -> [RoomMemberSummary] {
        let trimmedRoomID = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentUID = currentUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        let ownerID = ownerUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRoomID.isEmpty, !trimmedRoomID.contains("/") else {
            throw FirebaseError.FailedToFetchRoom
        }
        let members = db.collection("Rooms").document(trimmedRoomID).collection("members")
        async let moderatorsSnapshot = members.whereField("role", isEqualTo: ChatRoomMemberRole.moderator.rawValue)
            .limit(to: 4)
            .getDocuments()
        async let currentSnapshot = currentUID.isEmpty || currentUID.contains("/")
            ? nil
            : members.document(currentUID).getDocument()
        async let ownerSnapshot = ownerID.isEmpty || ownerID.contains("/") || ownerID == currentUID
            ? nil
            : members.document(ownerID).getDocument()

        var summaries = try await moderatorsSnapshot.documents.compactMap(Self.roomMemberSummary)
        if let current = try await currentSnapshot,
           var summary = Self.roomMemberSummary(current) {
            if summary.userID == ownerID {
                summary = RoomMemberSummary(
                    userID: summary.userID,
                    role: .owner,
                    moderatorSince: nil
                )
            }
            summaries.append(summary)
        }
        if let owner = try await ownerSnapshot,
           let summary = Self.roomMemberSummary(owner) {
            summaries.append(RoomMemberSummary(
                userID: summary.userID,
                role: .owner,
                moderatorSince: nil
            ))
        }
        var seen = Set<String>()
        return summaries.filter { seen.insert($0.userID).inserted }
    }

    private static func roomMemberSummary(_ document: DocumentSnapshot) -> RoomMemberSummary? {
        let data = document.data() ?? [:]
        let rawUserID = (data["userID"] as? String) ?? document.documentID
        let userID = rawUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userID.isEmpty, !userID.contains("/") else {
            return nil
        }
        let role: ChatRoomMemberRole
        if let rawRole = data["role"] as? String {
            guard let decodedRole = ChatRoomMemberRole(rawValue: rawRole) else { return nil }
            role = decodedRole
        } else {
            // 역할 마이그레이션 전 기존 방도 참여자 목록을 계속 표시한다.
            role = .member
        }
        return RoomMemberSummary(
            userID: userID,
            role: role,
            moderatorSince: (data["moderatorSince"] as? Timestamp)?.dateValue()
        )
    }

    @MainActor
    func updateRoomInfo(room: ChatRoom, newImagePath: String, roomName: String, roomDescription: String) async throws {
        guard !room.id.isEmpty else {
            throw FirebaseError.FailedToFetchRoom
        }
        
        var updateData = Self.searchIndexData(roomName: roomName, roomDescription: roomDescription)
        updateData["roomImagePath"] = newImagePath
        updateData["roomName"] = roomName
        updateData["roomDescription"] = roomDescription
        updateData["updatedAt"] = FieldValue.serverTimestamp()
        
        try await db.collection("Rooms").document(room.id).updateData(updateData)
    }

    private func updateRoomDocument(roomID: String, data: [String: Any]) async throws {
        guard !roomID.isEmpty else {
            throw FirebaseError.FailedToFetchRoom
        }

        try await db.collection("Rooms").document(roomID).updateData(data)
    }
    
    func checkRoomName(roomName: String, completion: @escaping (Bool, Error?) -> Void) {
        activeRoomsQuery()
            .whereField("roomName", isEqualTo: roomName)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(false, error)
                    return
                }

                if let snapshot = snapshot, snapshot.isEmpty {
                    completion(false, nil)
                } else {
                    completion(true, nil)
                }
            }
    }

    func checkRoomNameDuplicate(roomName: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            checkRoomName(roomName: roomName) { isDuplicate, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: isDuplicate)
            }
        }
    }

    private func activeRoomsQuery() -> Query {
        db.collection("Rooms")
            .whereField("isClosed", isEqualTo: false)
            .whereField("lifecycleStatus", isEqualTo: "active")
    }
    
    func addRoomParticipantReturningRoom(roomID: String) async throws -> ChatRoom {
        guard !roomID.isEmpty else {
            throw FirebaseError.FailedToFetchRoom
        }
        let canonicalUserID = LoginManager.shared.canonicalUserID
        let roomRef = db.collection("Rooms").document(roomID)
        
        _ = try await db.runTransaction { (transaction, errorPointer) -> Any? in
            do {
                let roomSnap = try transaction.getDocument(roomRef)
                let roomData = roomSnap.data() ?? [:]
                let creatorUID = (roomData["creatorUID"] as? String) ?? ""
                let isClosed = roomData["isClosed"] as? Bool ?? false
                let currentMemberCount = max(0, Self.toInt64(roomData["memberCount"]) ?? 0)
                let role = creatorUID == canonicalUserID ? "owner" : "member"
                let memberRef = roomRef.collection("members").document(canonicalUserID)
                let joinedRoomRef = try self.currentUserJoinedRoomRef(roomID: roomID)
                let joinedRoomSnap = try transaction.getDocument(joinedRoomRef)

                transaction.setData([
                    "userID": canonicalUserID,
                    "role": role,
                    "joinedAt": FieldValue.serverTimestamp(),
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: memberRef)
                transaction.setData([
                    "memberCount": currentMemberCount + 1,
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: roomRef, merge: true)
                if joinedRoomSnap.exists == false {
                    transaction.setData([
                        "roomID": roomID,
                        "role": role,
                        "joinedAt": FieldValue.serverTimestamp(),
                        "isClosed": isClosed,
                        "updatedAt": FieldValue.serverTimestamp()
                    ], forDocument: joinedRoomRef)
                }
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        
        let snap = try await roomRef.getDocument(source: .server)
        guard snap.exists else {
            throw FirebaseError.FailedToFetchRoom
        }
        do {
            let updated = try self.createRoom(from: snap)
            return updated
        } catch {
            print("❌ addRoomParticipantReturningRoom decode error:", error)
            throw FirebaseError.FailedToParseRoomData
        }
    }
    
    func removeParticipant(room: ChatRoom) {
        removeParticipantTask?.cancel()
        removeParticipantTask = Task {
            do {
                let roomID = room.id
                guard !roomID.isEmpty else {
                    print("⚠️ removeParticipant: roomID 없음")
                    return
                }
                let canonicalUserID = LoginManager.shared.canonicalUserID
                let roomRef = db.collection("Rooms").document(roomID)
                let memberRef = roomRef.collection("members").document(canonicalUserID)
                let joinedRoomRef = try currentUserJoinedRoomRef(roomID: roomID)
                let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                    do {
                        let roomSnap = try transaction.getDocument(roomRef)
                        let roomData = roomSnap.data() ?? [:]
                        let currentMemberCount = max(0, Self.toInt64(roomData["memberCount"]) ?? 0)
                        let memberSnap = try transaction.getDocument(memberRef)
                        transaction.deleteDocument(memberRef)
                        transaction.deleteDocument(joinedRoomRef)
                        if memberSnap.exists {
                            transaction.setData([
                                "memberCount": max(0, currentMemberCount - 1),
                                "updatedAt": FieldValue.serverTimestamp()
                            ], forDocument: roomRef, merge: true)
                        }
                        return nil
                    } catch {
                        errorPointer?.pointee = error as NSError
                        return nil
                    }
                })
                
                if let thumbPath = room.thumbPath {
                    KingFisherCacheManager.shared.removeImage(forKey: thumbPath)
                }
                if let originalpath = room.originalPath {
                    KingFisherCacheManager.shared.removeImage(forKey: originalpath)
                }
                
                print("참여중인 방 강제 삭제 성공")
                removeParticipantTask = nil
            } catch {
                print("방 참여자 강제 삭제 트랜젝션 실패: \(error)")
            }
        }
    }
    
    func fetchLatestSeq(for roomID: String) async throws -> Int64 {
        let roomRef = db.collection("Rooms").document(roomID)
        let roomSnap = try await roomRef.getDocument()
        let roomData = roomSnap.data()
        if let agg = Self.toInt64(roomData?["seq"]), agg > 0 {
            return agg
        }
        if let agg = Self.toInt64(roomData?["lastMessageSeq"]), agg > 0 {
            return agg
        }

        let upperMessages = try await roomRef.collection("Messages")
            .order(by: "seq", descending: true)
            .limit(to: 1)
            .getDocuments()
        if let latest = Self.toInt64(upperMessages.documents.first?.data()["seq"]), latest > 0 {
            return latest
        }

        let lowerMessages = try await roomRef.collection("messages")
            .order(by: "seq", descending: true)
            .limit(to: 1)
            .getDocuments()
        return Self.toInt64(lowerMessages.documents.first?.data()["seq"]) ?? 0
    }
    
    // MARK: - Private Helpers
    private func createRoom(from document: DocumentSnapshot) throws -> ChatRoom {
        do {
            let dto = try document.data(as: ChatRoomFirestoreDTO.self)
            return try ChatRoomFirestoreMapper.map(dto: dto, documentID: document.documentID)
        } catch {
            print("채팅방 디코딩 실패: \(error), docID: \(document.documentID)")
            throw FirebaseError.FailedToParseRoomData
        }
    }

    private static func toInt64(_ raw: Any?) -> Int64? {
        if let number = raw as? NSNumber { return number.int64Value }
        if let value = raw as? Int64 { return value }
        if let value = raw as? Int { return Int64(value) }
        if let value = raw as? UInt64 {
            return value > UInt64(Int64.max) ? Int64.max : Int64(value)
        }
        if let value = raw as? String, let parsed = Int64(value) { return parsed }
        if let value = raw as? Double { return Int64(value) }
        return nil
    }

    private static func searchIndexData(roomName: String, roomDescription: String) -> [String: Any] {
        let searchIndex = ChatRoomSearchIndex.buildIndexedFields(
            roomName: roomName,
            roomDescription: roomDescription
        )
        return [
            "roomSearchNormalized": searchIndex.normalizedText,
            "roomSearchChars": searchIndex.searchChars,
            "roomSearchNgrams2": searchIndex.searchNgrams2,
            "roomSearchIndexVersion": searchIndex.version
        ]
    }

    private func currentUserProfileRef() throws -> DocumentReference {
        let userDocumentID = LoginManager.shared.canonicalUserID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userDocumentID.isEmpty else {
            throw FirebaseError.FailedToFetchProfile
        }
        return db.collection("users").document(userDocumentID)
    }

    private func currentUserJoinedRoomRef(roomID: String) throws -> DocumentReference {
        let trimmedRoomID = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRoomID.isEmpty else {
            throw FirebaseError.FailedToFetchRoom
        }
        return try currentUserProfileRef().collection("joinedRooms").document(trimmedRoomID)
    }
}
