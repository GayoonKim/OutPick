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
    
    // 연결 상태 확인 프로퍼티 추가
    var isConnected: Bool {
        return socket.status == .connected
    }
    
    private static let isoFormatter = ISO8601DateFormatter()
    
    // Combine의 PassthroughSubject를 사용하여 이벤트 스트림 생성
    private let messageSubject = PassthroughSubject<ChatMessage, Never>()
    var receivedMessagePublisher: AnyPublisher<ChatMessage, Never> {
        return messageSubject.eraseToAnyPublisher()
    }
    
    private init() {
        //manager = SocketManager(socketURL: URL(string: "http://127.0.0.1:3000")!, config: [.log(true), .compress])
        manager = SocketManager(socketURL: URL(string: "http://192.168.123.172:3000")!, config: [.log(true), .compress])
        socket = manager.defaultSocket
        
        socket.on(clientEvent: .connect) {data, ack in
            print("Socket Connected")
            
            guard let nickName = UserProfile.shared.nickname else { return }
            self.socket.emit("set username", nickName)
        }
        
        socket.on(clientEvent: .error) { data, ack in
            print("소켓 에러:", data)
        }
    }
    
    func establishConnection(completion: @escaping () -> Void) {
        print("establishConnection 호출됨")
        
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
        
        // 연결 시도
        socket.once(clientEvent: .connect) { [weak self] _, _ in
            guard self != nil else { return }
            print("소켓 연결 성공")
            completion()
        }
        
        print("소켓 연결 시도")
        socket.connect()
    }
    
    func closeConnection() {
        socket.disconnect()
    }
    
    func joinRoom(_ roomName: String) {
        print("joinRomm 호출 - roomName: ", roomName)
        
        guard socket.status == .connected else {
            print("소켓이 연결되지 않음")
            return
        }
        
        //기존 리스너 제거, 중복 방지
        socket.off("join success")
        socket.off("error")
        
        // 방 참여 시도
        socket.emit("join room", roomName)
        
        // 방 참여 성공/실패 모니터링
        socket.on("join success") { data, _ in
            print("방 참여 성공: ", data)
        }
        socket.on("error") { data, _ in
            print("방 참여 실패: ", data)
        }
    }
    
    func createRoom(_ roomName: String) {
        
        print("createRoom 호출 - roomName: ", roomName)
        
        guard socket.status == .connected else {
            print("소켓이 연결되지 않음")
            return
        }
        
        socket.emit("create room", roomName)
        
        // 방 참여 성공/실패 모니터링
        socket.on("join success") { data, _ in
            print("방 참여 성공: ", data)
        }
        socket.on("error") { data, _ in
            print("방 참여 실패: ", data)
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
        
        socket.emitWithAck("chat message", message.toSocketRepresentation()).timingOut(after: 5) { ackResponse in
            DispatchQueue.main.async {
                if let ackDict = ackResponse.first as? [String:Any],
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
            
            let imageNames = try await FirebaseStorageManager.shared.uploadImagesToStorage(images: images, location: ImageLocation.Message)
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
            let images = finalAttachments.compactMap{ $0.toUIImage() }
            let message = ChatMessage(roomName: room.roomName, senderID: LoginManager.shared.getUserEmail, senderNickname: UserProfile.shared.nickname ?? "", msg: "", sentAt: Date(), attachments: finalAttachments)
            
            socket.emitWithAck("send images", ["roomName": message.roomName, "senderID": message.senderID, "senderNickName": message.senderNickname, "sentAt": "\(message.sentAt ?? Date())", "images": imageDataArray]).timingOut(after: 5) { ackResponse in
                
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
            roomName: room.roomName,
            senderID: LoginManager.shared.getUserEmail,
            senderNickname: UserProfile.shared.nickname ?? "",
            msg: "",
            sentAt: Date(),
            attachments: localAttachments,
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
        // 중복 방지를 위해 기존 리스너 제거
        socket.off("chat message")
        socket.on("chat message") { data, _ in
            guard let messageData = data.first as? [String: Any] else { return }
            let roomName = messageData["roomName"] as! String
            let senderID = messageData["senderID"] as! String
            let senderNickName = messageData["senderNickName"] as! String
            let messageText = messageData["msg"] as? String
            
            let message = ChatMessage(roomName: roomName, senderID: senderID, senderNickname: senderNickName, msg: messageText, sentAt: Date(), attachments: [])
            
            if senderID == LoginManager.shared.getUserEmail { return }
            
            DispatchQueue.main.async {
                self.messageSubject.send(message)
            }
            
        }
        
        //중복 방지를 위해 기존 리스너 제거
        socket.off("receiveImages")
        socket.on("receiveImages") { dataArray, _ in
            guard let data = dataArray.first as? [String: Any],
                  let imageDataArray = data["images"] as? [[String:Any]],
                  let roomName = data["roomName"] as? String,
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

            let message = ChatMessage(roomName: roomName, senderID: senderID, senderNickname: senderNickName, msg: nil, sentAt: sentAt, attachments: attachments)
            
            DispatchQueue.main.async {
                self.messageSubject.send(message)
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
                    let roomName = failedData["roomName"] as? String ?? ""
                    let senderID = failedData["senderID"] as? String ?? ""
                    let senderNickName = failedData["senderNickName"] as? String ?? ""
                    let msg = failedData["msg"] as? String ?? ""
                    
                    var failedMessage = ChatMessage(
                        roomName: roomName,
                        senderID: senderID,
                        senderNickname: senderNickName,
                        msg: msg,
                        sentAt: Date(),
                        attachments: []
                    )
                    failedMessage.isFailed = true
                    
                    self.messageSubject.send(failedMessage)
                }
                
                if type == "image" {
                    guard let roomName = failedData["roomName"] as? String,
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
                    
                    var failedImageMessage = ChatMessage(
                        roomName: roomName,
                        senderID: senderID,
                        senderNickname: senderNickName,
                        msg: nil,
                        sentAt: sentAt,
                        attachments: attachments
                    )
                    failedImageMessage.isFailed = true
                    
                    self.messageSubject.send(failedImageMessage)
                }
            }
        }
    }
}
