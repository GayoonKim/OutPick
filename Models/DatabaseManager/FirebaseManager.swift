//
//  FirestoreManager.swift
//  OutPick
//
//  Created by 김가윤 on 10/10/24.
//

import Foundation
import FirebaseFirestore
import FirebaseStorage
import Alamofire
import Kingfisher
import Combine

class FirebaseManager {
    
    private init() {}
    
    // FirestoreManager의 싱글톤 인스턴스
    static let shared = FirebaseManager()
    
    // Firestore 인스턴스
    let db = Firestore.firestore()
    // Storage 인스턴스
    let storage = Storage.storage()
    
    let joinedRoomStore = JoinedRoomsStore()
    
    // Users/{email} 프로필 스냅샷 리스너 캐시
    private var userProfileListeners: [String: ListenerRegistration] = [:]
    // Users/{email} 프로필 변경 스트림(Combine)
    private var userProfileSubjects: [String: PassthroughSubject<UserProfile, Error>] = [:]
    
    // 채팅방 목록
    private(set) var topRoomsWithPreviews: [(ChatRoom, [ChatMessage])] = []
    private var previewByRoomID: [String: [ChatMessage]] = [:]
    private var lastRoomIDsListened: Set<String> = []

    private var add_room_participant_task: Task<Void, Never>? = nil
    private var remove_participant_task: Task<Void, Never>? = nil

    deinit {
        add_room_participant_task?.cancel()
        remove_participant_task?.cancel()
    }

    private var lastFetchedMessageSnapshot: DocumentSnapshot?
    private var lastFetchedRoomSnapshot: DocumentSnapshot?

    //MARK: 프로필 설정 관련 기능들
    /// Users/{email} 문서에 스냅샷 리스너를 걸고, subject로 이벤트를 발행합니다.
    func listenToUserProfile(email: String) {
        if let _ = userProfileListeners[email] { return }

        // subject 없으면 생성
        let subject: PassthroughSubject<UserProfile, Error>
        if let s = userProfileSubjects[email] {
            subject = s
        } else {
            let s = PassthroughSubject<UserProfile, Error>()
            userProfileSubjects[email] = s
            subject = s
        }

        let docRef = db.collection("Users").document(email)
        let listener = docRef.addSnapshotListener { snapshot, error in
            if let error = error {
                subject.send(completion: .failure(error))
                return
            }

            guard let snapshot = snapshot, snapshot.exists else {
                let err = NSError(domain: "FirebaseManager",
                                  code: 404,
                                  userInfo: [NSLocalizedDescriptionKey: "UserProfile 문서가 존재하지 않습니다."])
                subject.send(completion: .failure(err))
                return
            }

            do {
                let profile = try snapshot.data(as: UserProfile.self)

                // ✅ 1) 내 프로필이면 LoginManager만 갱신하고 subject로는 전파하지 않음
                let myEmail = LoginManager.shared.getUserEmail  // 네 프로젝트에서 쓰는 “내 이메일” getter
                if profile.email == myEmail || email == myEmail {
                    // LoginManager currentUserProfile 갱신
                    // (MainActor 보장하려면 아래처럼)
                    Task { @MainActor in
                        LoginManager.shared.setCurrentUserProfile(profile)
                    }
                    return
                }

                // ✅ 2) 타인 프로필이면 subject로 전파
                subject.send(profile)

            } catch {
                subject.send(completion: .failure(error))
            }
        }

        userProfileListeners[email] = listener
        
        print(#function, "프로필 실시간 리스너 설정 갱신", userProfileListeners)
    }
    
    func userProfilePublisher(email: String) -> AnyPublisher<UserProfile, Error> {

        // 1) subject 없으면 생성/캐시
        let subject: PassthroughSubject<UserProfile, Error>
        if let s = userProfileSubjects[email] {
            subject = s
        } else {
            let s = PassthroughSubject<UserProfile, Error>()
            userProfileSubjects[email] = s
            subject = s
        }

        // 2) 리스너 없으면 시작
        if userProfileListeners[email] == nil {
            listenToUserProfile(email: email)
        }

        // 3) 외부에는 Publisher로만 노출
        return subject.eraseToAnyPublisher()
    }

    /// Users/{email} 프로필 스냅샷 리스너 해제
    func stopListenUserProfile(email: String) {
        if let listener = userProfileListeners[email] {
            listener.remove()
            userProfileListeners.removeValue(forKey: email)
        }

        if let subject = userProfileSubjects[email] {
            subject.send(completion: .finished)
            userProfileSubjects.removeValue(forKey: email)
        }
    }
    
    // Firebase Firestore에 UserProfile 객체 저장
    func saveUserProfileToFirestore(email: String) async throws {
        do {
            var profileData = LoginManager.shared.currentUserProfile?.toDict() ?? [:]
            profileData["createdAt"] = FieldValue.serverTimestamp()
            try await db.collection("Users").document(email).setData(profileData)

        } catch {
            throw FirebaseError.FailedToSaveProfile
        }
    }
    
//     Firebase Firestore에서 UserProfile 불러오기
    func fetchUserProfileFromFirestore(email: String) async throws -> UserProfile {
        print("fetchUserProfileFromFirestore 호출")

        // 단일 Users 컬렉션에서 문서 ID = email 로 직접 조회
        let docRef = db.collection("Users").document(email)
        let snapshot = try await docRef.getDocument()
        guard let data = snapshot.data() else {
            throw FirebaseError.FailedToFetchProfile
        }

        // 수동 매핑 (필드명이 스키마와 일치한다고 가정)
        return UserProfile(
            email: data["email"] as? String ?? email,
            nickname: data["nickname"] as? String,
            gender: data["gender"] as? String,
            birthdate: data["birthdate"] as? String,
            thumbPath: data["thumbPath"] as? String,
            originalPath: data["originalPath"] as? String,
            joinedRooms: data["joinedRooms"] as? [String]
        )
    }
    
    func fetchUserProfiles(emails: [String]) async throws -> [UserProfile] {
        return try await withThrowingTaskGroup(of: UserProfile?.self) { group in
            for email in emails {
                group.addTask {
                    do {
                        
                        let profile = try await self.fetchUserProfileFromFirestore(email: email)
                        return profile
                        
                    } catch {
                        
                        print("\(email) 사용자 프로필 불러오기 실패: \(error)")
                        return nil
                        
                    }
                }
            }
            
            var profiles = [UserProfile]()
            for try await result in group {
                if let profile = result {
                    profiles.append(profile)
                }
            }
            
            return profiles
        }
    }

    // 프로필 닉네임 중복 검사
    func checkDuplicate(strToCompare: String, fieldToCompare: String, collectionName: String) async throws -> Bool{
        do {
            let query = db.collection(collectionName).whereField(fieldToCompare, isEqualTo: strToCompare)
            let snapshot = try await query.getDocuments()
            
            return !snapshot.isEmpty
        } catch {
            throw FirebaseError.Duplicate
        }
    }
    
    // MARK: - User room state (lastReadSeq)
    /// Users/{uid}/roomStates/{roomID}.lastReadSeq 를 업데이트합니다.
    /// - Parameters:
    ///   - roomID: 방 문서 ID
    ///   - userID: 사용자 uid(이메일 키를 사용 중이면 해당 값)
    ///   - lastReadSeq: 사용자가 마지막으로 읽은 시퀀스(단조 증가)
    public func updateLastReadSeq(roomID: String, userID: String, lastReadSeq: Int64) async throws {
        let db = Firestore.firestore()
        let ref = db.collection("Users").document(userID)
            .collection("roomStates").document(roomID)
        try await ref.setData([
            "lastReadSeq": lastReadSeq,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    //MARK: 채팅 방 관련 기능들
    func leaveRoom(roomID: String) async throws {
        let userEmail = LoginManager.shared.getUserEmail

        // 1) Users/{me}.joinedRooms 에서 제거
        try await db.collection("Users").document(userEmail).updateData([
            "joinedRooms": FieldValue.arrayRemove([roomID])
        ])

        // 2) Users/{me}/roomStates/{roomID} 정리
        try? await db.collection("Users")
            .document(userEmail)
            .collection("roomStates")
            .document(roomID)
            .delete()

        // 3) Rooms/{roomID}.participants 에서 내 이메일 제거
        //    서버/클라우드 함수로 위임해도 됨 (추측입니다)
        try? await db.collection("Rooms")
            .document(roomID)
            .updateData([
                "participantIDs": FieldValue.arrayRemove([userEmail])
            ])
    }
    
    /// 방 참여/탈퇴 등으로 방 메타가 바뀌었을 때, 캐시를 최신 Room으로 교체
    func applyLocalRoomUpdate(_ updatedRoom: ChatRoom) {
        // 1) 튜플에서 같은 ID를 가진 방 찾기
        guard let rid = updatedRoom.ID, !rid.isEmpty else { return }
        if let idx = topRoomsWithPreviews.firstIndex(where: { $0.0.ID == rid }) {
            // 2) 미리보기 메시지는 그대로 두고, 방만 최신 객체로 교체
            let previews = topRoomsWithPreviews[idx].1
            topRoomsWithPreviews[idx] = (updatedRoom, previews)
        } else {
            // Top 30 범위 밖이었을 수도 있음: 필요시 앞쪽에 삽입하거나 무시
            // (정책에 맞게 선택 – 추측입니다)
        }
    }
    
    // 사용자 roomStates/{roomID}에서 lastReadSeq를 읽음
    func fetchLastReadSeq(for roomID: String) async throws -> Int64 {
        // 컬렉션 경로/필드 이름은 실제 프로젝트 스키마에 맞게 조정하세요.
        let email = LoginManager.shared.getUserEmail
        let docRef = Firestore.firestore()
            .collection("Users").document(email)
            .collection("roomStates").document(roomID)

        let snap = try await docRef.getDocument()
        let lastRead = snap.data()?["lastReadSeq"] as? Int64 ?? 0
        return lastRead
    }

    // Rooms/{roomID}의 집계 필드 또는 messages 서브컬렉션에서 최신 seq를 가져옴
    func fetchLatestSeq(for roomID: String) async throws -> Int64 {
        let roomRef = Firestore.firestore().collection("Rooms").document(roomID)
        let roomSnap = try await roomRef.getDocument()
        if let agg = roomSnap.data()?["lastMessageSeq"] as? Int64 {
            return agg
        }
        // 집계 필드가 없다면 서브컬렉션에서 최신 메시지로 대체
        let messagesRef = roomRef.collection("messages")
        let querySnap = try await messagesRef
            .order(by: "seq", descending: true)
            .limit(to: 1)
            .getDocuments()
        let latest = querySnap.documents.first?.data()["seq"] as? Int64 ?? 0
        return latest
    }
    
@MainActor
func fetchTopRoomsPage(after lastSnapshot: DocumentSnapshot? = nil, limit:Int = 30) async throws {
    var query: Query = db.collection("Rooms").order(by: "lastMessageAt", descending: true).limit(to: limit)
    
    if let lastSnapshot {
        query = query.start(afterDocument: lastSnapshot)
    }
    
    // 1) Top rooms 페이지 스냅샷
    let snapshot = try await query.getDocuments()
    
    // 2) 디코딩
    let rooms: [ChatRoom] = snapshot.documents.compactMap { doc in
        do {
            return try self.createRoom(from: doc)
        } catch {
            print("⚠️ Room decode failed: \(error), id=\(doc.documentID)")
            return nil
        }
    }
    
    // 3) 각 방의 최근 메시지 3개(미리보기) 동시 로드
    //    - 우선 seq 기반(desc)으로 시도 후 실패 시 sentAt(desc) 폴백
    //    - 표시용으로는 오름차순(과거→최신) 정렬을 반환
    let previewsByRoomID: [String: [ChatMessage]] = await withTaskGroup(of: (String, [ChatMessage]).self) { group in
        for r in rooms {
            guard let rid = r.ID, !rid.isEmpty else { continue }
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
    
    // 4) 상태 업데이트 (topRooms + topRoomsWithPreviews 동시 유지)
    self.previewByRoomID = previewsByRoomID
//    self.topRooms = rooms
    self.topRoomsWithPreviews = rooms.map { room in
        let rid = room.ID ?? ""
        let previews = previewsByRoomID[rid] ?? []
        return (room, previews)
    }
    
    self.lastFetchedRoomSnapshot = snapshot.documents.last
}

    /// 방 미리보기용으로 최근 메시지 N개를 가져옵니다.
    /// 우선 seq(desc) 기반, 실패 또는 비어있으면 sentAt(desc)로 폴백합니다.
    /// 화면 표시를 위해 반환은 오름차순(과거→최신)으로 정렬합니다.
    private func fetchPreviewMessages(roomID: String, limit: Int = 3) async -> [ChatMessage] {
        let messagesRef = db.collection("Rooms").document(roomID).collection("Messages")
        
        // 내부 디코더(관대 파서 우선)
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
        
        // 1) seq 기반 시도
        do {
            let snap = try await messagesRef
                .order(by: "seq", descending: true)
                .limit(to: limit)
                .getDocuments()
            let arr = decode(snap)
            if !arr.isEmpty { return arr.reversed() } // 오름차순 변환
        } catch {
            // 계속 폴백 시도
        }
        
        // 2) sentAt 기반 폴백
        do {
            let snap = try await messagesRef
                .order(by: "sentAt", descending: true)
                .limit(to: limit)
                .getDocuments()
            let arr = decode(snap)
            return arr.reversed() // 오름차순 변환
        } catch {
            print("⚠️ _fetchPreviewMessages fallback failed (roomID=\(roomID)): \(error)")
            return []
        }
    }

    @MainActor
    func updateRoomLastMessage(roomID: String, date: Date? = nil, msg: String) async {
        guard !roomID.isEmpty else {
            print("❌ updateRoomLastMessageAt: roomID is empty")
            return
        }
        
        do {
            let ref = db.collection("Rooms").document(roomID)
            var updateData: [String: Any] = [:]
            
            updateData["lastMessage"] = msg
            if let date = date {
                updateData["lastMessageAt"] = Timestamp(date: date)
            } else {
                updateData["lastMessageAt"] = FieldValue.serverTimestamp()
            }
            
            try await ref.updateData(updateData)
            print("✅ lastMessageAt 업데이트 성공 → \(roomID)")
        } catch {
            print("🔥 lastMessageAt 업데이트 실패: \(error)")
        }
    }
    
    func editRoom(room: ChatRoom,
                    pickedImage: UIImage?,
                    imageData: MediaManager.ImagePair?,
                    isRemoved: Bool,
                    newName: String,
                  newDesc: String) async throws -> ChatRoom {
        
        // 1) 현재 상태 읽기 / 이전 경로 확보
        let roomRef = db.collection("Rooms").document(room.ID ?? "")
        let oldThumb = room.thumbPath
        let oldOriginal = room.originalPath
        
        var uploadedThumb: String? = nil
        var uploadedOriginal: String? = nil
        
        // 1) 분기 처리: 삭제 / 업로드(pair 우선) / 업로드(UIImage 폴백) / 텍스트만
        if isRemoved {
            // Firestore: 이미지 경로 제거 + 텍스트 갱신
            try await roomRef.updateData([
                "thumbPath": FieldValue.delete(),
                "originalPath": FieldValue.delete(),
                "roomName": newName,
                "roomDescription": newDesc
            ])
            // 성공 후 이전 파일 삭제 (best-effort)
            Task.detached {
                if let t = oldThumb { FirebaseStorageManager.shared.deleteImageFromStorage(path: t) }
                if let o = oldOriginal { FirebaseStorageManager.shared.deleteImageFromStorage(path: o) }
            }
        } else if let pair = imageData {
            // 선택 영역 로직 반영: 미리 준비된 썸네일/원본으로 업로드
            let (newThumb, newOriginal) = try await FirebaseStorageManager.shared.uploadAndSave(
                sha: pair.fileBaseName,
                uid: room.ID ?? "",
                type: .RoomImage,
                thumbData: pair.thumbData,
                originalFileURL: pair.originalFileURL
            )
            uploadedThumb = newThumb; uploadedOriginal = newOriginal
        }  else {
            // 텍스트만 변경
            try await roomRef.updateData([
                "roomName": newName,
                "roomDescription": newDesc
            ])
        }
        
        // 3) 최신 방 데이터
        var updated = room
        updated.roomName = newName
        updated.roomDescription = newDesc
        if isRemoved {
            updated.thumbPath = nil
            updated.originalPath = nil
        } else if let ut = uploadedThumb, let uo = uploadedOriginal {
            updated.thumbPath = ut
            updated.originalPath = uo
        }
        
        return updated
    }
    
    // 특정 방 문서 불러오기
    func getRoomDoc(room: ChatRoom) async throws -> DocumentSnapshot? {
        let roomRef = db.collection("Rooms").document(room.ID ?? "")
        let room_snapshot = try await roomRef.getDocument()
        
        guard room_snapshot.exists else {
            print("방 문서 불러오기 실패")
            return nil
        }
        
        return room_snapshot

    }

    // 방 정보 저장
    func saveRoomInfoToFirestore(room: ChatRoom) async throws {
        // 1) 방 ID 유효성 확인
        guard let roomID = room.ID, !roomID.isEmpty else {
            print("❌ saveRoomInfoToFirestore: room.ID is nil/empty")
            throw FirebaseError.FailedToFetchRoom
        }

        let roomRef = db.collection("Rooms").document(roomID)

        do {
            // 2) Firestore 트랜잭션으로 방 문서 생성 (실패 시 조기 종료)
            _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                transaction.setData(room.toDictionary(), forDocument: roomRef)
                return nil
            })

            // 3) 방 참여자 업데이트 (생성자 자신)
            try await FirebaseManager.shared.add_room_participant(room: room)

            // 4) Socket.IO: Firestore 성공 후 방 생성/참여 요청 (roomName 대신 roomID 사용 권장)
            //    서버가 별도의 create가 필요 없다면 join만으로도 충분합니다.
            SocketIOManager.shared.createRoom(roomID)
            SocketIOManager.shared.joinRoom(roomID)
            
//            await upsertRooms([room])

            print("✅ saveRoomInfoToFirestore: Firestore 저장 및 Socket.IO create/join 완료 (roomID=\(roomID))")
        } catch {
            print("🔥 saveRoomInfoToFirestore 실패: \(error)")
            throw error
        }
    }

    func fetchRoomsWithIDs(byIDs ids: [String]) async throws -> [ChatRoom] {
        guard !ids.isEmpty else { return [] }
        var result: [ChatRoom] = []
        var start = 0
        
        while start < ids.count {
            let end = min(start + 10, ids.count)  // Firestore 'in' 제한 10개
            let chunk = Array(ids[start..<end])
            start = end
            
            let snap = try await Firestore.firestore()
                .collection("Rooms")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            
            let rooms = snap.documents.compactMap { doc -> ChatRoom? in
                try? doc.data(as: ChatRoom.self)
            }
            result.append(contentsOf: rooms)
        }
        
        return result
    }
    
    // MARK: - Firestore 방 검색 관련
        private var lastSearchSnapshot: DocumentSnapshot?
        private var currentSearchKeyword: String = ""
    /// Firestore 채팅방 이름 prefix 검색 (roomName) + 페이지네이션 지원
    /// - Parameters:
    ///   - keyword: 검색어(빈 문자열 불가)
    ///   - limit: 페이지당 최대 개수 (기본 30)
    ///   - reset: true면 페이지네이션 초기화(새 검색), false면 이어서(다음 페이지)
    /// - Returns: 검색된 ChatRoom 배열
    func searchRooms(keyword: String, limit: Int = 30, reset: Bool = true) async throws -> [ChatRoom] {
        guard !keyword.isEmpty else { return [] }
        
        if reset {
            lastSearchSnapshot = nil
            currentSearchKeyword = keyword
        }
        
        var query: Query = db.collection("Rooms")
            .order(by: "lastMessageAt", descending: true)
            .limit(to: limit)
        
        // Firestore은 부분 문자열 검색을 지원하지 않으므로 prefix 기반으로 처리
        // 예: roomName >= keyword && roomName < keyword + "\u{f8ff}"
        query = query
            .whereField("roomName", isGreaterThanOrEqualTo: keyword)
            .whereField("roomName", isLessThanOrEqualTo: keyword + "\u{f8ff}")
        
        if let last = lastSearchSnapshot {
            query = query.start(afterDocument: last)
        }
        
        let snap = try await query.getDocuments()
        lastSearchSnapshot = snap.documents.last
        
        let rooms = snap.documents.compactMap { doc -> ChatRoom? in
            try? doc.data(as: ChatRoom.self)
        }
        return rooms
    }
    
    /// Firestore Room Search - 다음 페이지 불러오기 (이전 검색어 기준)
    func loadMoreSearchRooms(limit: Int = 30) async throws -> [ChatRoom] {
        guard !currentSearchKeyword.isEmpty else { return [] }
        return try await searchRooms(keyword: currentSearchKeyword, limit: limit, reset: false)
    }
    
    // MARK: - Room doc 스냅샷 리스너
    private var roomDocListeners: [String: ListenerRegistration] = [:]
    // Batched listeners for up to 10 room docs per listener (using 'in' query)
    private var batchedRoomDocListeners: [String: ListenerRegistration] = [:]
    private let roomChangeSubject = PassthroughSubject<ChatRoom, Never>()
    var roomChangePublisher: AnyPublisher<ChatRoom, Never> {
        return roomChangeSubject.eraseToAnyPublisher()
    }
    
    @MainActor
    func startListenRoomDoc(roomID: String) {
        // ⬇️ batched 리스너가 같은 집합을 관리 중이면 per-doc 리스너는 스킵
        if lastRoomIDsListened.contains(roomID) {
            print(#function, "skip per-doc listener (managed by batched):", roomID)
            return
        }
        if roomDocListeners[roomID] != nil { return } // already listening

        let ref = db.collection("Rooms").document(roomID)
        let l = ref.addSnapshotListener { [weak self] snap, err in
            guard let self = self else { return }
            if let err = err {
                print("❌ Room listener error:", err)
                return
            }
            guard let snap = snap, snap.exists else { return }
            do {
                let room = try self.createRoom(from: snap)
                // ⬇️ 메인 액터에서 store 갱신 + 퍼블리시 (UI 일관성 보장)
                Task { @MainActor in
                    if let id = room.ID, !id.isEmpty {
                        /*self.roomStore[id] = room */     // 마지막 메시지/시간 등 값 자체를 교체
                        self.roomChangeSubject.send(room)
                    }
                }
            } catch {
                print("❌ Room decode error:", error)
            }
        }
        roomDocListeners[roomID] = l
    }

    @MainActor
    func startListenRoomDocs(roomIDs: [String]) {
        let ids = Array(Set(roomIDs)).filter { !$0.isEmpty }
        let newSet = Set(ids)
        guard !newSet.isEmpty else {
            stopListenAllRoomDocs()
            return
        }
        
        // 같은 집합이면 재생성 안 함 → 끊김 방지
        if newSet == lastRoomIDsListened { return }
        lastRoomIDsListened = newSet
        
        // Remove previous batched listeners entirely and recreate (simpler & safe)
        for (_, l) in batchedRoomDocListeners { l.remove() }
        batchedRoomDocListeners.removeAll()
        // Keep legacy per-doc listeners for backward compatibility
        for (_, l) in roomDocListeners { l.remove() }
        roomDocListeners.removeAll()

        // Chunk size 10 due to Firestore 'in' query limit
        let chunkSize = 10
        var index = 0
        while index < ids.count {
            let end = min(index + chunkSize, ids.count)
            let chunk = Array(ids[index..<end])
            index = end

            // Use a stable key for this chunk
            let key = chunk.sorted().joined(separator: ",")

            let q = db.collection("Rooms")
                .whereField(FieldPath.documentID(), in: chunk)

            let l = q.addSnapshotListener { [weak self] snap, err in
                guard let self = self else { return }
                if let err = err {
                    print("❌ Batched room docs listener error:", err)
                    return
                }
                guard let snap = snap else { return }

                Task { @MainActor in
                    for change in snap.documentChanges {
                        do {
                            let room = try self.createRoom(from: change.document)
                            if let id = room.ID, !id.isEmpty {
//                                self.roomStore[id] = room
                                self.roomChangeSubject.send(room)
                            }
                        } catch {
                            print("⚠️ Batched decode failed:", error, "docID:", change.document.documentID)
                        }
                    }
                }
            }

            batchedRoomDocListeners[key] = l
            print(#function, "Added listener for chunk:", l)
        }
    }

    @MainActor
    func stopListenAllRoomDocs() {
        for (_, listener) in roomDocListeners {
            listener.remove()
        }
        roomDocListeners.removeAll()

        for (_, listener) in batchedRoomDocListeners {
            listener.remove()
        }
        batchedRoomDocListeners.removeAll()
    }
    
    @MainActor
    func updateRoomInfo(room: ChatRoom, newImagePath: String, roomName: String, roomDescription: String) async throws {
        guard let roomDoc = try await getRoomDoc(room: room) else {
            throw FirebaseError.FailedToFetchRoom
        }
        
        var updateData: [String: Any] = [:]
        updateData["roomImagePath"] = newImagePath
        updateData["roomName"] = roomName
        updateData["roomDescription"] = roomDescription
        
        try await roomDoc.reference.updateData(updateData)
    }
    
    // 방 이름 중복 검사
    func checkRoomName(roomName: String, completion: @escaping (Bool, Error?) -> Void) {
        db.collection("Rooms").whereField("roomName", isEqualTo: roomName).getDocuments { snapshot, error in
            if let error = error {
                completion(false, error)
                return
            }
            
            if let snapshot = snapshot, snapshot.isEmpty {
                completion(false, nil) // 중복 x
            } else {
                completion(true, nil) // 중복 o
            }
        }
    }

    private func updateTopRoomsPreviews(room: ChatRoom, messages: [ChatMessage], allRooms: [ChatRoom]) {
        var current = topRoomsWithPreviews
        current.removeAll { $0.0.ID == room.ID }
        current.append((room, messages.sorted { $0.sentAt ?? Date() < $1.sentAt ?? Date() }))
        topRoomsWithPreviews = allRooms.compactMap{ r in
            let msgs = current.first(where: { $0.0.ID == r.ID })?.1 ?? []
            return (r, msgs)
        }
    }
    
    private func handleMessageSnapshot(_ snapshot: QuerySnapshot?, error: Error?, room: ChatRoom, allRooms: [ChatRoom]) {
        guard let snapshot = snapshot else {
            print("HotRoom 메시지 불러오기 실패: \(error?.localizedDescription ?? "알 수 없는 에러")")
            return
        }

        let messages: [ChatMessage] = snapshot.documents.compactMap { doc in
            var dict = doc.data()
            // 일부 문서에 ID 필드가 없을 수도 있으니 보정
            if dict["ID"] == nil { dict["ID"] = doc.documentID }
            if let msg = ChatMessage.from(dict) {
                return msg
            }
            // 최후의 수단으로 FirestoreSwift 디코더 시도 (디버깅 로그 유지)
            do {
                return try doc.data(as: ChatMessage.self)
            } catch {
                print("⚠️ 디코딩 실패(관대파서/코더 모두 실패): \(error), docID: \(doc.documentID), data=\(dict)")
                return nil
            }
        }

        DispatchQueue.main.async {
            self.updateTopRoomsPreviews(room: room, messages: messages, allRooms: allRooms)
        }
    }

    private func createRoom(from document: DocumentSnapshot) throws -> ChatRoom {
        do {
            return try document.data(as: ChatRoom.self)
        } catch {
            print("채팅방 디코딩 실패: \(error), docID: \(document.documentID)")
            throw FirebaseError.FailedToParseRoomData
        }
    }

    func remove_participant(room: ChatRoom) {
        remove_participant_task?.cancel()
        remove_participant_task = Task {
            do {
                let userRef = db.collection("Users").document(LoginManager.shared.getUserEmail)
                let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                    transaction.updateData(["joinedRooms": FieldValue.arrayRemove([room.roomName])], forDocument: userRef)
                    return nil
                })
                
                if let thumbPath = room.thumbPath {
                    KingFisherCacheManager.shared.removeImage(forKey: thumbPath)
                }
                if let originalpath = room.originalPath {
                    KingFisherCacheManager.shared.removeImage(forKey: originalpath)
                }
                
                print("참여중인 방 강제 삭제 성공")
                remove_participant_task = nil
            } catch {
                print("방 참여자 강제 삭제 트랜젝션 실패: \(error)")
            }
        }
    }
    
    // 방 참여자 업데이트
    func add_room_participant(room: ChatRoom) async throws {
        add_room_participant_task?.cancel()
        add_room_participant_task = Task {
            do {
                guard let room_doc = try await getRoomDoc(room: room) else { return }
                let userRef = db.collection("Users").document(LoginManager.shared.getUserEmail)
                
                let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                    transaction.updateData(["joinedRooms": FieldValue.arrayUnion([room.ID ?? ""])], forDocument: userRef)
                    transaction.updateData(["participantIDs": FieldValue.arrayUnion([LoginManager.shared.getUserEmail])], forDocument: room_doc.reference)
                    return nil
                })
                
                print(#function, "참여자 업데이트 성공")
                add_room_participant_task = nil
            } catch {
                print(#function, "방 참여자 업데이트 트랜젝션 실패: \(error)")
            }
        }
    }

    /// 방 참여자를 트랜잭션으로 추가하고, 서버 강제 조회로 최신 Room 문서를 반환합니다.
    func add_room_participant_returningRoom(roomID: String) async throws -> ChatRoom {
        guard !roomID.isEmpty else {
            throw FirebaseError.FailedToFetchRoom
        }
        let email = LoginManager.shared.getUserEmail
        let userRef = db.collection("Users").document(email)
        let roomRef = db.collection("Rooms").document(roomID)

        // 1) 트랜잭션: Users.joinedRooms, Rooms.participantIDs 동시 갱신
        _ = try await db.runTransaction { (transaction, errorPointer) -> Any? in
            transaction.updateData(["joinedRooms": FieldValue.arrayUnion([roomID])], forDocument: userRef)
            transaction.updateData(["participantIDs": FieldValue.arrayUnion([email])], forDocument: roomRef)
            return nil
        }

        // 2) 서버 강제 조회로 최신 Room 문서를 받아 디코드
        let snap = try await roomRef.getDocument(source: .server)
        guard snap.exists else {
            throw FirebaseError.FailedToFetchRoom
        }
        do {
            let updated = try self.createRoom(from: snap)
            return updated
        } catch {
            print("❌ add_room_participant_returningRoom decode error:", error)
            throw FirebaseError.FailedToParseRoomData
        }
    }
    

    //MARK: 공지(Announcement) 관련 기능
    @MainActor
    func setActiveAnnouncement(roomID: String,
                               messageID: String?,
                               payload: AnnouncementPayload?) async throws {
        guard !roomID.isEmpty else { throw FirebaseError.FailedToFetchRoom }
        var update: [String: Any] = [:]

        if let messageID = messageID {
            update["activeAnnouncementID"] = messageID
        } else {
            update["activeAnnouncementID"] = FieldValue.delete()
        }

        if let payload = payload {
            update["activeAnnouncement"] = payload.toDictionary()
            update["announcementUpdatedAt"] = Timestamp(date: payload.createdAt)
        } else {
            update["activeAnnouncement"] = FieldValue.delete()
            update["announcementUpdatedAt"] = FieldValue.serverTimestamp()
        }

        let ref = db.collection("Rooms").document(roomID)
        try await ref.updateData(update)
    }

    /// 방 객체 기반의 오버로드
    @MainActor
    func setActiveAnnouncement(room: ChatRoom,
                               messageID: String?,
                               payload: AnnouncementPayload?) async throws {
        guard let roomID = room.ID else { throw FirebaseError.FailedToFetchRoom }
        try await setActiveAnnouncement(roomID: roomID, messageID: messageID, payload: payload)
    }

    /// 텍스트/작성자만 받아 간편하게 현재 공지를 설정합니다. (히스토리 메시지 연결 없음)
    @MainActor
    func setActiveAnnouncement(room: ChatRoom,
                               text: String,
                               authorID: String) async throws {
        let payload = AnnouncementPayload(text: text, authorID: authorID, createdAt: Date())
        try await setActiveAnnouncement(room: room, messageID: nil, payload: payload)
    }

    /// 현재 공지를 제거합니다.
    @MainActor
    func clearActiveAnnouncement(roomID: String) async throws {
        try await setActiveAnnouncement(roomID: roomID, messageID: nil, payload: nil)
    }

    /// 현재 공지를 제거합니다. (room 오버로드)
    @MainActor
    func clearActiveAnnouncement(room: ChatRoom) async throws {
        guard let roomID = room.ID else { throw FirebaseError.FailedToFetchRoom }
        try await clearActiveAnnouncement(roomID: roomID)
    }

    //MARK: 메시지 관련 기능
    func saveMessage(_ message: ChatMessage, _ room: ChatRoom) async throws /*-> String*/ {
        do {
            let roomDoc = try await getRoomDoc(room: room)
            let messageRef = roomDoc?.reference.collection("Messages").document(message.ID) // 자동 ID 생성

            try await messageRef?.setData(message.toDict())
            
            print("메시지 저장 성공 => \(message)")
        } catch {
            print("메시지 전송 및 저장 실패")
        }
    }

    /// 특정 방에서 isDeleted = true 상태만 감지하는 리스너
    func listenToDeletedMessages(roomID: String,
                                 onDeleted: @escaping (String) -> Void) -> ListenerRegistration {
        return db.collection("Rooms")
            .document(roomID)
            .collection("Messages")
            .whereField("isDeleted", isEqualTo: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ listenToDeletedMessages 오류: \(error)")
                    return
                }
                guard let snapshot = snapshot else { return }
                
                for change in snapshot.documentChanges {
                    if change.type == .added || change.type == .modified {
                        let doc = change.document
                        let mid = (doc.get("ID") as? String) ?? doc.documentID
                        onDeleted(mid)
                        print("🗑 삭제 감지된 메시지: messageID=\(mid), docID=\(doc.documentID)")
                    }
                }
            }
    }

    // 특정 메시지의 isDeleted 상태를 true로 업데이트
    func updateMessageIsDeleted(roomID: String, messageID: String) async throws {
        guard !roomID.isEmpty, !messageID.isEmpty else {
            throw FirebaseError.FailedToFetchRoom
        }
        do {
            let query = db.collection("Rooms")
                .document(roomID)
                .collection("Messages")
                .whereField("ID", isEqualTo: messageID)
                .limit(to: 10)
            let snapshot = try await query.getDocuments()
            guard snapshot.isEmpty == false else {
                print("⚠️ 메시지 문서를 찾을 수 없음 (roomID=\(roomID), messageID=\(messageID))")
                throw FirebaseError.FailedToFetchRoom
            }
            for doc in snapshot.documents {
                try await doc.reference.updateData(["isDeleted": true])
                print("✅ 메시지 삭제 업데이트 성공: docID=\(doc.documentID), messageID=\(messageID)")
            }
        } catch {
            print("🔥 메시지 삭제 업데이트 실패: \(error)")
            throw error
        }
    }

    func fetchDeletionStates(roomID: String, messageIDs: [String]) async throws -> [String: Bool] {
        guard !roomID.isEmpty else { throw FirebaseError.FailedToFetchRoom }
        guard !messageIDs.isEmpty else { return [:] }

        var result: [String: Bool] = [:]
        // Firestore `in` 쿼리는 한 번에 전달할 수 있는 값 개수에 제한이 있으니 보수적으로 10개씩 청크 처리
        let chunkSize = 10
        var start = 0
        while start < messageIDs.count {
            let end = min(start + chunkSize, messageIDs.count)
            let chunk = Array(messageIDs[start..<end])
            start = end

            let snap = try await db.collection("Rooms")
                .document(roomID)
                .collection("Messages")
                .whereField("ID", in: chunk)
                .getDocuments()

            for doc in snap.documents {
                let mid = (doc.get("ID") as? String) ?? doc.documentID
                let isDel = (doc.get("isDeleted") as? Bool) ?? false
                result[mid] = isDel
            }
        }
        return result
    }

    // NOTE: 메시지 페이징은 이제 `seq` 기반으로 동작합니다.
    // - 정렬: seq ASC (필수)
    // - 마이그레이션 호환: anchor에 seq가 없으면 sentAt로 폴백
    // Firestore 인덱스: 단일 필드 `seq`는 기본 인덱스가 있으나, 콘솔에서 에러가 나면 안내에 따라 생성하세요.
    // Firestore에서 메시지 페이징(신규 페이지) — seq 오름차순 기준, 스냅샷 커서로 연속성 보장
    // NOTE: 첫 호출 전에(또는 reset 직후) 연속 앵커를 설정하려면, 호출측에서 lastFetchedMessageSnapshot을
    //       적절한 문서 스냅샷으로 세팅해두는 것을 권장합니다(예: lastRead 앵커).
    func fetchMessagesPaged(for room: ChatRoom, pageSize: Int = 50, reset: Bool = false) async throws -> [ChatMessage] {
        // 1) 방 ID 확인
        guard let roomID = room.ID else {
            print("❌ fetchMessagesPaged: room.ID is nil")
            return []
        }

        // 2) 컬렉션 및 정렬: seq ASC (결정적 순서)
        let collection = db
            .collection("Rooms")
            .document(roomID)
            .collection("Messages")

        if reset { lastFetchedMessageSnapshot = nil }

        var query: Query = collection
            .order(by: "seq", descending: false)
            .limit(to: pageSize)

        // 3) 스냅샷 커서 페이지네이션
        if let lastSnapshot = lastFetchedMessageSnapshot {
            query = query.start(afterDocument: lastSnapshot)
        }

        // 4) 실행
        let snapshot = try await query.getDocuments()
        lastFetchedMessageSnapshot = snapshot.documents.last

        // 5) 디코딩
        let messages: [ChatMessage] = snapshot.documents.compactMap { doc in
            var dict = doc.data()
            if dict["ID"] == nil { dict["ID"] = doc.documentID }
            if let msg = ChatMessage.from(dict) { return msg }
            do { return try doc.data(as: ChatMessage.self) } catch {
                print("⚠️ 디코딩 실패(관대파서/코더 모두 실패): \(error), docID: \(doc.documentID), data=\(dict)")
                return nil
            }
        }
        return messages
    }

    /// 기준 메시지 이전의 과거 메시지를 limit개 가져오기 (seq 기반, sentAt 폴백)
    func fetchOlderMessages(for room: ChatRoom, before messageID: String, limit: Int = 100) async throws -> [ChatMessage] {
        guard let roomID = room.ID else { return [] }

        let anchorDoc = try await db
            .collection("Rooms").document(roomID)
            .collection("Messages").document(messageID)
            .getDocument()
        guard anchorDoc.exists, let anchorData = anchorDoc.data() else { return [] }

        // 우선 seq 기반으로 시도 (없으면 sentAt로 폴백)
        if let anySeq = anchorData["seq"] {
            let anchorSeq: Int64
            if let num = anySeq as? NSNumber { anchorSeq = num.int64Value }
            else if let i = anySeq as? Int { anchorSeq = Int64(i) }
            else if let l = anySeq as? Int64 { anchorSeq = l }
            else { anchorSeq = 0 }

            let snapshot = try await db
                .collection("Rooms").document(roomID)
                .collection("Messages")
                .whereField("seq", isLessThan: anchorSeq)
                .order(by: "seq", descending: true)
                .limit(to: limit)
                .getDocuments()

            let messages: [ChatMessage] = snapshot.documents.compactMap { doc in
                var dict = doc.data(); if dict["ID"] == nil { dict["ID"] = doc.documentID }
                if let msg = ChatMessage.from(dict) { return msg }
                do { return try doc.data(as: ChatMessage.self) } catch { print("⚠️ 디코딩 실패: \(error), docID: \(doc.documentID), data=\(dict)"); return nil }
            }
            return messages.reversed() // 과거→최신(오름차순)
        }

        // ⚠️ fallback: anchor에 seq가 없을 때 기존 sentAt 경로
        let anchorSentAt = (anchorData["sentAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
        let snapshot = try await db
            .collection("Rooms").document(roomID)
            .collection("Messages")
            .whereField("sentAt", isLessThan: Timestamp(date: anchorSentAt))
            .order(by: "sentAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        let messages: [ChatMessage] = snapshot.documents.compactMap { doc in
            var dict = doc.data(); if dict["ID"] == nil { dict["ID"] = doc.documentID }
            if let msg = ChatMessage.from(dict) { return msg }
            do { return try doc.data(as: ChatMessage.self) } catch { print("⚠️ 디코딩 실패: \(error), docID: \(doc.documentID), data=\(dict)"); return nil }
        }
        return messages.reversed()
    }
    
    /// 특정 메시지 이후의 최신 메시지를 limit개 가져오기 (seq 기반, sentAt 폴백)
    func fetchMessagesAfter(room: ChatRoom, after messageID: String, limit: Int = 100) async throws -> [ChatMessage] {
        guard let roomID = room.ID else { return [] }

        let anchorDoc = try await db
            .collection("Rooms").document(roomID)
            .collection("Messages").document(messageID)
            .getDocument()
        guard anchorDoc.exists, let anchorData = anchorDoc.data() else { return [] }

        if let anySeq = anchorData["seq"] {
            let anchorSeq: Int64
            if let num = anySeq as? NSNumber { anchorSeq = num.int64Value }
            else if let i = anySeq as? Int { anchorSeq = Int64(i) }
            else if let l = anySeq as? Int64 { anchorSeq = l }
            else { anchorSeq = 0 }

            let snapshot = try await db
                .collection("Rooms").document(roomID)
                .collection("Messages")
                .whereField("seq", isGreaterThan: anchorSeq)
                .order(by: "seq", descending: false)
                .limit(to: limit)
                .getDocuments()

            let messages: [ChatMessage] = snapshot.documents.compactMap { doc in
                var dict = doc.data(); if dict["ID"] == nil { dict["ID"] = doc.documentID }
                if let msg = ChatMessage.from(dict) { return msg }
                do { return try doc.data(as: ChatMessage.self) } catch { print("⚠️ 디코딩 실패: \(error), docID: \(doc.documentID), data=\(dict)"); return nil }
            }
            return messages
        }

        // ⚠️ fallback: anchor에 seq가 없을 때 기존 sentAt 경로
        let anchorSentAt = (anchorData["sentAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
        let snapshot = try await db
            .collection("Rooms").document(roomID)
            .collection("Messages")
            .whereField("sentAt", isGreaterThan: Timestamp(date: anchorSentAt))
            .order(by: "sentAt", descending: false)
            .limit(to: limit)
            .getDocuments()

        let messages: [ChatMessage] = snapshot.documents.compactMap { doc in
            var dict = doc.data(); if dict["ID"] == nil { dict["ID"] = doc.documentID }
            if let msg = ChatMessage.from(dict) { return msg }
            do { return try doc.data(as: ChatMessage.self) } catch { print("⚠️ 디코딩 실패: \(error), docID: \(doc.documentID), data=\(dict)"); return nil }
        }
        return messages
    }
}

extension UIImage {
    func resized(withMaxWidth maxWidth: CGFloat) -> UIImage {
        let aspectRatio = size.height / size.width
        let newSize = CGSize(width: min(maxWidth, size.width), height: min(maxWidth, size.width) * aspectRatio)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

extension Notification.Name {
    static let chatRoomsUpdated = Notification.Name("chatRoomsUpdated")
}
