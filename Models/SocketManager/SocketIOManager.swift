//
//  SocketIOManager.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.

import UIKit
import SocketIO
import Combine

class SocketIOManager {
    static let shared = SocketIOManager()

    // MARK: - Socket Error
    enum SocketError: Error {
        case connectionFailed([Any])
    }
    
    var manager: SocketManager!
    var socket: SocketIOClient!
    
    private var connectWaiters: [() -> Void] = []
    private var hasOnConnectBound = false
    
    // 연결 상태 확인 프로퍼티 추가
    var isConnected: Bool {
        return socket.status == .connected
    }
    
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    // Combine의 PassthroughSubject를 사용하여 이벤트 스트림 생성
    
    // 새로운 참여자 알림을 위한 Publisher 추가
    private let participantSubject = PassthroughSubject<(String, String), Never>() // (roomName, email)
    var participantUpdatePublisher: AnyPublisher<(String, String), Never> {
        return participantSubject.eraseToAnyPublisher()
    }
    
    private var didBindListeners = false
    
    private var joinedRooms = Set<String>()
    private var pendingRooms: Set<String> = []
    
    private var roomSubjects = [String: PassthroughSubject<ChatMessage, Never>]()
    private var subscriberCounts = [String: Int]() // 구독자 ref count
    
    private init() {
        //manager = SocketManager(socketURL: URL(string: "http://127.0.0.1:3000")!, config: [.log(true), .compress])
        manager = SocketManager(socketURL: URL(string: "http://192.168.123.156:3000")!, config: [.log(true), .compress])
        socket = manager.defaultSocket
        
        socket.on(clientEvent: .connect) {data, ack in
            print("Socket Connected")
            
            guard let nickName = LoginManager.shared.currentUserProfile?.nickname else { return }
            self.socket.emit("set username", nickName)
            
            // Join any pending rooms after connecting and setting username
            for roomID in self.pendingRooms {
                self.socket.emit("join room", roomID)
                self.joinedRooms.insert(roomID)
            }
            self.pendingRooms.removeAll()
        }
        
        socket.on(clientEvent: .error) { data, ack in
            print("소켓 에러:", data)
        }
    }
    
    func establishConnection() async throws {
        // 이미 연결된 경우
        if socket.status == .connected {
            print("이미 연결된 상태")
            return
        }
        
        // 연결 중인 경우
        if socket.status == .connecting {
            print("이미 연결 중인 상태")
            try await withCheckedThrowingContinuation { continuation in
                self.connectWaiters.append {
                    continuation.resume()
                }
            }
            return
        }
        
        // 연결 시도
        try await withCheckedThrowingContinuation { continuation in
            self.connectWaiters.append {
                continuation.resume()
            }
            
            if !self.hasOnConnectBound {
                self.hasOnConnectBound = true
                self.socket.on(clientEvent: .connect) { [weak self] _, _ in
                    guard let self else { return }
                    let waiters = self.connectWaiters
                    self.connectWaiters.removeAll()
                    waiters.forEach { $0() }
                }
                
                self.socket.on(clientEvent: .error) { [weak self] data, _ in
                    guard let self else { return }
                    let waiters = self.connectWaiters
                    self.connectWaiters.removeAll()
                    waiters.forEach { _ in
                        continuation.resume(throwing: SocketError.connectionFailed(data))
                    }
                }
            }
            
            print("소켓 연결 시도")
            self.socket.connect()
        }
    }
    
    func closeConnection() {
        socket.disconnect()
    }
    
    func subscribeToMessages(for roomID: String) -> AnyPublisher<ChatMessage, Never> {
        print(#function, "✅✅✅✅✅ 2. subscribeToMessages 호출")
        
        subscriberCounts[roomID, default: 0] += 1

        if roomSubjects[roomID] == nil {
            let subject = PassthroughSubject<ChatMessage, Never>()
            roomSubjects[roomID] = subject

            // 소켓 리스너 등록
            attachSocketListener(for: roomID) { [weak self] message in
                guard let self = self else { return }
                self.roomSubjects[roomID]?.send(message)
            }
        }
        
        print(#function, "✅✅✅✅✅ 3. roomSubjects", roomSubjects[roomID]!)
        return roomSubjects[roomID]!.eraseToAnyPublisher()
    }

    func unsubscribeFromMessages(for roomID: String) {
        guard let count = subscriberCounts[roomID], count > 0 else { return }
        subscriberCounts[roomID] = count - 1

        if subscriberCounts[roomID] == 0 {
            detachSocketListener(for: roomID)
            roomSubjects[roomID]?.send(completion: .finished)
            roomSubjects[roomID] = nil
        }
    }
    
    private func attachSocketListener(for roomID: String, onMessage: @escaping (ChatMessage) -> Void) {
        print(#function, "attachSocketListener 호출")
        socket.on("chat message:\(roomID)") { data, _ in
            guard let dict = data.first as? [String: Any],
                  let message = ChatMessage.from(dict) else {
                return
            }
            onMessage(message)
        }
    }

    private func detachSocketListener(for roomID: String) {
        socket.off("chat message:\(roomID)")
    }
    
    func joinRoom(_ roomID: String) {
        if socket.status == .connected {
            guard joinedRooms.insert(roomID).inserted else {
                print("이미 참여한 방:", roomID); return
            }
            socket.emit("join room", roomID)
        } else {
            // Not connected: queue for joining after connect
            pendingRooms.insert(roomID)
        }
        // listener off/on은 유지해도 됨. emit 자체가 중복되지 않는 게 핵심
    }
    
    func createRoom(_ roomID: String) {
        print("createRoom 호출 - roomID: ", roomID)
        
        guard socket.status == .connected else {
            print("소켓이 연결되지 않음")
            return
        }
        
        // 기존 방 생성 관련 리스너 제거 (중복 방지)
        socket.off("room created")
        socket.off("room error")
        
        socket.emit("create room", roomID)
        
        // 방 생성 성공/실패 모니터링
        socket.on("room created") { data, _ in
            print("방 생성 성공: ", data)
        }
        socket.on("room error") { data, _ in
            print("방 생성 실패: ", data)
        }
    }
    
    func sendMessages(_ room: ChatRoom, _ message: ChatMessage) {
        // 1. Optimistic UI: Publish the message immediately as not failed
        // 2. If not connected, mark as failed and publish (again, so UI can update)
        guard socket.status == .connected else {
            print("소켓이 연결되지 않음")
            var failedMessage = message
            failedMessage.isFailed = true
            DispatchQueue.main.async {
                self.roomSubjects[room.ID ?? ""]?.send(failedMessage)
            }
            return
        }

        let payload = message.toSocketRepresentation()
        print("📤 전송할 소켓 데이터: \(payload)")  // 디버깅용

        socket.emitWithAck("chat message", payload).timingOut(after: 5) { [weak self] ackResponse in
            guard let self = self else { return }

            let ackDict = ackResponse.first as? [String:Any]
            let ok = (ackDict?["ok"] as? Bool) ?? (ackDict?["success"] as? Bool) ?? false
            let duplicate = (ackDict?["duplicate"] as? Bool) ?? false

            if ok || duplicate {
                Task {
                    await FirebaseManager.shared.updateRoomLastMessageAt(roomID: room.ID ?? "", date: message.sentAt)
                }
            } else {
                // Failure: mark the same message as failed and re-publish for UI update
                var failedMessage = message
                failedMessage.isFailed = true
                DispatchQueue.main.async {
                    self.roomSubjects[room.ID ?? ""]?.send(failedMessage)
                }
            }
        }
    }
    
    func sendImages(_ room: ChatRoom, _ images: [UIImage]) {
        if self.socket.status != .connected {
            print("소켓 연결 실패 -> 로컬 실패 처리")
            
            Task { [weak self] in
                guard let self = self else { return }
                await self.processFailedImages(room, images)
            }

            return
        }
        
        Task { [weak self] in
            guard let self = self else { return }
            
            let imageNames = try await FirebaseStorageManager.shared.uploadImagesToStorage(images: images, location: ImageLocation.RoomImage, name: room.roomName)
            var attachments = Array<Attachment?>(repeating: nil, count: imageNames.count)
            
            let imageDataArray = try await withThrowingTaskGroup(of: (Int, [String:Any]?).self) { group in
                for (index, image) in images.enumerated() {
                    group.addTask {
                        guard let imageData = image.jpegData(compressionQuality: 0.5) else {
                            return (index, nil)
                        }
                        
                        return (index, ["fileName": imageNames[index], "fileData": imageData])
                    }
                }
                
                var inOrderResults = Array<[String: Any]?>(repeating: nil, count: images.count)
                for try await (index, result) in group {
                    inOrderResults[index] = result
                    
                    if let result = result {
                        let attachment = Attachment(type: .image, fileName: result["fileName"] as? String, fileData: result["fileData"] as? Data)
                        attachments[index] = attachment
                    }
                }
                
                return inOrderResults.compactMap { $0 }
            }
            
            let finalAttachments = attachments.compactMap { $0 }
//            let images = finalAttachments.compactMap{ $0.toUIImage() }
            let message = ChatMessage(ID: UUID().uuidString, roomID: room.ID ?? "", senderID: LoginManager.shared.getUserEmail, senderNickname: LoginManager.shared.currentUserProfile?.nickname ?? "", msg: "", sentAt: Date(), attachments: finalAttachments, replyPreview: nil)
            
            socket.emitWithAck("send images", ["roomID": message.roomID, "senderID": message.senderID, "senderNickName": message.senderNickname, "sentAt": "\(message.sentAt ?? Date())", "images": imageDataArray]).timingOut(after: 7) { ackResponse in
                
                if let ackDict = ackResponse.first as? [String: Any],
                   let success = ackDict["success"] as? Bool, success {
                    self.roomSubjects[room.ID ?? ""]?.send(message)
                } else {
                    var failedMessage = message
                    failedMessage.isFailed = true
                    self.roomSubjects[room.ID ?? ""]?.send(failedMessage)
                }
            }
        }
    }
    
    
    private func processFailedImages(_ room: ChatRoom, _ images: [UIImage]) async {
        var localAttachments: [Attachment] = []
        do {
            localAttachments = try await withThrowingTaskGroup(of: (Int, Attachment?).self) { group in
                for (index, image) in images.enumerated() {
                    group.addTask {
                        guard let imageData = image.jpegData(compressionQuality: 0.5) else { return (index, nil) }
                        return (index, Attachment(type: .image, fileName: UUID().uuidString, fileData: imageData))
                    }
                }

                var orderedResults = Array<Attachment?>(repeating: nil, count: images.count)
                for try await (index, attachment) in group {
                    orderedResults[index] = attachment
                }
                return orderedResults.compactMap { $0 }
            }
        } catch {
            print("로컬 실패 이미지 처리 중 오류 발생: \(error)")
        }

        let failedMessage = ChatMessage(
            ID: UUID().uuidString,
            roomID: room.ID ?? "",
            senderID: LoginManager.shared.getUserEmail,
            senderNickname: LoginManager.shared.currentUserProfile?.nickname ?? "",
            msg: "",
            sentAt: Date(),
            attachments: localAttachments,
            replyPreview: nil,
            isFailed: true
        )

        self.roomSubjects[room.ID ?? ""]?.send(failedMessage)
    }
    
    func setUserName(_ userName: String) {
        print("setUserName 호출됨: \(userName)")
        socket.emit("set username", userName)
        print("유저 이름 이벤트 emit 완료")
    }

    func notifyNewParticipant(roomID: String, email: String) {
        guard socket.status == .connected else {
            print("소켓이 연결되어 있지 않아 새 참여자 알림 emit 실패")
            return
        }
        
        print("새 참여자 알림 emit - room: \(roomID), email: \(email)")
        socket.emit("new participant joined", roomID, email)
    }
    
    func listenToNewParticipant() {
        socket.off("room participant updated")
        socket.on("room participant updated") { [weak self] data, _ in
            guard let self = self,
                  let dict = data.first as? [String: String],
                  let roomID = dict["roomID"],
                  let email = dict["email"] else {
                print("room participant updated 수신 실패: 데이터 형식 불일치")
                return
            }

            Task { @MainActor in
                do {
                    let profile = try await FirebaseManager.shared.fetchUserProfileFromFirestore(email: email)
                    
                    // GRDB를 통해 로컬 DB에 저장
                    try await GRDBManager.shared.dbPool.write { db in
                        try profile.save(db)
                        try db.execute(
                            sql: "INSERT OR REPLACE INTO roomParticipant (roomID, email) VALUES (?, ?)",
                            arguments: [roomID, email]
                        )
                    }
                    
                    // 새로운 참여자 알림 발행
                    self.participantSubject.send((roomID, email))
                    
                } catch {
                    print("새 참여자 프로필 불러오기/저장 실패: \(error)")
                }
            }
        }
    }
}
