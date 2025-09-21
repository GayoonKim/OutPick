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
    private let messageSubject = PassthroughSubject<ChatMessage, Never>()
    var receivedMessagePublisher: AnyPublisher<ChatMessage, Never> {
        return messageSubject.eraseToAnyPublisher()
    }
    
    // 새로운 참여자 알림을 위한 Publisher 추가
    private let participantSubject = PassthroughSubject<(String, String), Never>() // (roomName, email)
    var participantUpdatePublisher: AnyPublisher<(String, String), Never> {
        return participantSubject.eraseToAnyPublisher()
    }
    
    private var didBindListeners = false
    
    private var joinedRooms = Set<String>()
    
    private init() {
        //manager = SocketManager(socketURL: URL(string: "http://127.0.0.1:3000")!, config: [.log(true), .compress])
        manager = SocketManager(socketURL: URL(string: "http://192.168.123.141:3000")!, config: [.log(true), .compress])
        socket = manager.defaultSocket
        
        socket.on(clientEvent: .connect) {data, ack in
            print("Socket Connected")
            
            guard let nickName = LoginManager.shared.currentUserProfile?.nickname else { return }
            self.socket.emit("set username", nickName)
        }
        
        socket.on(clientEvent: .error) { data, ack in
            print("소켓 에러:", data)
        }
    }
    
    func establishConnection(completion: @escaping () -> Void) {
        // 이미 연결된 경우
        if socket.status == .connected {
            print("이미 연결된 상태")
            completion()
            return
        }
        
        // 연결 중인 경우
        if socket.status == .connecting {
            print("이미 연결 중인 상태")
            return
        }
        
        connectWaiters.append(completion)

        if !hasOnConnectBound {
            hasOnConnectBound = true
            socket.on(clientEvent: .connect) { [weak self] _, _ in
                guard let self else { return }
                let waiters = self.connectWaiters
                self.connectWaiters.removeAll()
                waiters.forEach { $0() }   // 딱 한 번만 비움
            }
        }

        print("소켓 연결 시도")
        socket.connect()
    }
    
    func closeConnection() {
        socket.disconnect()
    }

    func bindAllListenersIfNeeded() {
        if didBindListeners { return }
        didBindListeners = true
        listenToChatMessage()
//        listenToNewParticipant()
        listenToErrors()
    }

    func joinRoom(_ roomID: String) {
        guard socket.status == .connected else { print("소켓 미연결"); return }
        guard joinedRooms.insert(roomID).inserted else {
            print("이미 참여한 방:", roomID); return
        }
        socket.emit("join room", roomID)
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
        //        Task { try await FirebaseManager.shared.saveMessage(message, room) }
        guard socket.status == .connected else {
            print("소켓이 연결되지 않음")
            var failedMessage = message
            failedMessage.isFailed = true
            
            DispatchQueue.main.async {
                self.messageSubject.send(failedMessage)
            }
            
            return
        }
        
        let payload = message.toSocketRepresentation()
        print("📤 전송할 소켓 데이터: \(payload)")  // 디버깅용
        
//        socket.emitWithAck("chat message", payload).timingOut(after: 5) { ackResponse in
//            if let ackDict = ackResponse.first as? [String:Any],
//               let success = ackDict["success"] as? Bool, success {
//
//                Task {
//                    await FirebaseManager.shared.updateRoomLastMessageAt(roomID: room.ID ?? "", date: message.sentAt)
//                }
//
//                self.messageSubject.send(message)
//            } else {
//                //                    print(#function, "********** 메시지 전송 타임아웃 **********")
//                var failedMessage = message
//                failedMessage.isFailed = true
//                self.messageSubject.send(failedMessage)
//            }
//        }
        
        socket.emitWithAck("chat message", payload).timingOut(after: 5) { [weak self] ackResponse in
            guard let self = self else { return }
            
            let ackDict = ackResponse.first as? [String:Any]
            
            let ok = (ackDict?["ok"] as? Bool) ?? (ackDict?["success"] as? Bool) ?? false
            let duplicate = (ackDict?["duplicate"] as? Bool) ?? false
            
            if ok || duplicate {
                Task { await FirebaseManager.shared.updateRoomLastMessageAt(roomID: room.ID ?? "", date: message.sentAt) }
                
                DispatchQueue.main.async {
                    self.messageSubject.send(message)
                }
            } else {
                var failedMessage = message
                failedMessage.isFailed = true
                DispatchQueue.main.async {
                    self.messageSubject.send(failedMessage)
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
            let message = ChatMessage(roomID: room.ID ?? "", senderID: LoginManager.shared.getUserEmail, senderNickname: LoginManager.shared.currentUserProfile?.nickname ?? "", msg: "", sentAt: Date(), attachments: finalAttachments, replyPreview: nil)
            
            socket.emitWithAck("send images", ["roomID": message.roomID, "senderID": message.senderID, "senderNickName": message.senderNickname, "sentAt": "\(message.sentAt ?? Date())", "images": imageDataArray]).timingOut(after: 7) { ackResponse in
                
                if let ackDict = ackResponse.first as? [String: Any],
                   let success = ackDict["success"] as? Bool, success {
                    self.messageSubject.send(message)
                } else {
                    var failedMessage = message
                    failedMessage.isFailed = true
                    self.messageSubject.send(failedMessage)
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
            roomID: room.ID ?? "",
            senderID: LoginManager.shared.getUserEmail,
            senderNickname: LoginManager.shared.currentUserProfile?.nickname ?? "",
            msg: "",
            sentAt: Date(),
            attachments: localAttachments,
            replyPreview: nil,
            isFailed: true
        )

        self.messageSubject.send(failedMessage)
    }
    
    func setUserName(_ userName: String) {
        print("setUserName 호출됨: \(userName)")
        socket.emit("set username", userName)
        print("유저 이름 이벤트 emit 완료")
    }
    
    func listenToChatMessage() {
        // 중복 방지를 위해 기존 리스너 제거 (혹시 모를 중복 대비)
        socket.off("chat message")
        socket.on("chat message") { data, _ in
            guard let messageData = data.first as? [String: Any] else {
                print("❌ 메시지 데이터 파싱 실패: data 형식 오류")
                return
            }

            // 안전한 옵셔널 바인딩
            guard let roomID = messageData["roomID"] as? String,
                  let senderID = messageData["senderID"] as? String,
                  let senderNickName = messageData["senderNickName"] as? String,
                  let messageText = messageData["msg"] as? String else {
                print("❌ 메시지 데이터 파싱 실패: \(messageData)")
                return
            }

            let sentAt: Date = {
                if let s = messageData["sentAt"] as? String,
                   let d = SocketIOManager.isoFormatter.date(from: s) {
                    return d
                } else {
                    return Date()
                }
            }()

            // replyPreview 파싱 (선택)
            var rp: ReplyPreview? = nil
            if let rpDict = messageData["replyPreview"] as? [String: Any],
               let mid = rpDict["messageID"] as? String, !mid.isEmpty {
                rp = ReplyPreview(
                    messageID: mid,
                    sender: (rpDict["author"] as? String) ?? "",
                    text: (rpDict["text"] as? String) ?? "",
                    isDeleted: (rpDict["isDeleted"] as? Bool) ?? false
                )
            }

            let message = ChatMessage(
                roomID: roomID,
                senderID: senderID,
                senderNickname: senderNickName,
                msg: messageText,
                sentAt: sentAt,
                attachments: [],
                replyPreview: rp
            )

            if senderID == LoginManager.shared.getUserEmail { return }

            DispatchQueue.main.async {
                if let myProfile = LoginManager.shared.currentUserProfile,
                   let myNickname = myProfile.nickname,
                   myNickname != senderNickName {
                    self.messageSubject.send(message)
                }
            }
        }

        //중복 방지를 위해 기존 리스너 제거 (혹시 모를 중복 대비)
        socket.off("receiveImages")
        socket.on("receiveImages") { dataArray, _ in
            guard let data = dataArray.first as? [String: Any],
                  let imageDataArray = data["images"] as? [[String:Any]],
                  let roomID = data["roomID"] as? String,
                  let senderID = data["senderID"] as? String,
                  let senderNickName = data["senderNickName"] as? String,
                  let sentAtString = data["sentAt"] as? String else { return }

            if senderID == LoginManager.shared.getUserEmail { return }

            // String -> Date 변환
            let sentAt = SocketIOManager.isoFormatter.date(from: sentAtString) ?? Date()

            let attachments = imageDataArray.compactMap { imageData -> Attachment? in
                guard let imageName = imageData["fileName"] as? String,
                      let imageData = imageData["fileData"] as? Data else {
                    print("이미지 데이터 변환 실패: \(imageData)")
                    return nil
                }
                return Attachment(type: .image, fileName: imageName, fileData: imageData)
            }

            // replyPreview 파싱 (선택)
            var rp: ReplyPreview? = nil
            if let rpDict = data["replyPreview"] as? [String: Any],
               let mid = rpDict["messageID"] as? String, !mid.isEmpty {
                rp = ReplyPreview(
                    messageID: mid,
                    sender: (rpDict["author"] as? String) ?? "",
                    text: (rpDict["text"] as? String) ?? "",
                    isDeleted: (rpDict["isDeleted"] as? Bool) ?? false
                )
            }

            let message = ChatMessage(
                roomID: roomID,
                senderID: senderID,
                senderNickname: senderNickName,
                msg: nil,
                sentAt: sentAt,
                attachments: attachments,
                replyPreview: rp
            )

            Task { @MainActor in
                if let myProfile = LoginManager.shared.currentUserProfile,
                   let myNickname = myProfile.nickname,
                   myNickname != senderNickName {
                    self.messageSubject.send(message)
                }
            }
        }
    }
    
    // Listen to server error events and handle failed messages
    private func listenToErrors() {
        SocketIOManager.shared.socket.off("error")
        SocketIOManager.shared.socket.on("error") { [weak self] data, _ in
            guard let self = self else { return }
            guard let errorInfo = data.first as? [String: Any],
                  let type = errorInfo["type"] as? String,
                  let reason = errorInfo["reason"] as? String,
                  let failedData = errorInfo["data"] as? [String: Any] else {
                print("데이터 파싱 실패")
                return
            }

            print("서버 전송 실패 (\(type)): \(reason)")

            DispatchQueue.main.async {
                if type == "message" {
                    let roomID = failedData["roomID"] as? String ?? ""
                    let senderID = failedData["senderID"] as? String ?? ""
                    let senderNickName = failedData["senderNickName"] as? String ?? ""
                    let msg = failedData["msg"] as? String ?? ""

                    var rp: ReplyPreview? = nil
                    if let rpDict = failedData["replyPreview"] as? [String: Any],
                       let mid = rpDict["messageID"] as? String, !mid.isEmpty {
                        rp = ReplyPreview(
                            messageID: mid,
                            sender: (rpDict["author"] as? String) ?? "",
                            text: (rpDict["text"] as? String) ?? "",
                            isDeleted: (rpDict["isDeleted"] as? Bool) ?? false
                        )
                    }

                    var failedMessage = ChatMessage(
                        roomID: roomID,
                        senderID: senderID,
                        senderNickname: senderNickName,
                        msg: msg,
                        sentAt: Date(),
                        attachments: [],
                        replyPreview: rp
                    )
                    failedMessage.isFailed = true

                    self.messageSubject.send(failedMessage)
                }

                if type == "image" {
                    guard let roomID = failedData["roomID"] as? String,
                          let senderID = failedData["senderID"] as? String,
                          let senderNickName = failedData["senderNickName"] as? String,
                          let sentAtString = failedData["sentAt"] as? String,
                          let imageDataArray = failedData["images"] as? [[String: Any]] else {
                        print("이미지 실패 데이터 파싱 실패")
                        return
                    }

                    let sentAt = SocketIOManager.isoFormatter.date(from: sentAtString) ?? Date()

                    let attachments = imageDataArray.compactMap { imageData -> Attachment? in
                        guard let imageName = imageData["fileName"] as? String,
                              let imageData = imageData["fileData"] as? Data else {
                            print("이미지 실패 attachment 변환 실패: \(imageData)")
                            return nil
                        }
                        return Attachment(type: .image, fileName: imageName, fileData: imageData)
                    }

                    var rp: ReplyPreview? = nil
                    if let rpDict = failedData["replyPreview"] as? [String: Any],
                       let mid = rpDict["messageID"] as? String, !mid.isEmpty {
                        rp = ReplyPreview(
                            messageID: mid,
                            sender: (rpDict["author"] as? String) ?? "",
                            text: (rpDict["text"] as? String) ?? "",
                            isDeleted: (rpDict["isDeleted"] as? Bool) ?? false
                        )
                    }

                    var failedImageMessage = ChatMessage(
                        roomID: roomID,
                        senderID: senderID,
                        senderNickname: senderNickName,
                        msg: nil,
                        sentAt: sentAt,
                        attachments: attachments,
                        replyPreview: rp
                    )
                    failedImageMessage.isFailed = true

                    self.messageSubject.send(failedImageMessage)
                }
            }
        }
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
