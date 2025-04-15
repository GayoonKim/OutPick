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
    
    // Combine의 PassthroughSubject를 사용하여 이벤트 스트림 생성
    var receivedMessagePublisher = PassthroughSubject<ChatMessage, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        manager = SocketManager(socketURL: URL(string: "http://127.0.0.1:3000")!, config: [.log(true), .compress])
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
        
        if socket.status == .connected {
            print("이미 연결된 상태")
            completion()
            return
        }
        
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
        Task { try await FirebaseManager.shared.saveMessage(message, room) }
        socket.emit("chat message", message.toSocketRepresentation())
    }
    
    func sendImages(_ room: ChatRoom, _ images: [UIImage]) {
        guard socket.status == .connected else {
            print("소켓이 연결되지 않음")
            return
        }
        
        // 이미지 Storage에 저장 및 이미지 데이터 Firestore에 저장
//        Task {
//            let imageNames = try await FirebaseStorageManager.shared.uploadImagesToStorage(images: images, location: ImageLocation.Message)
//            var attachments = [Attachment]()
//            
//            let imageDataArray = imageNames.enumerated().compactMap { index, fileName -> [String: Any]? in
//                if let imageData = images[index].jpegData(compressionQuality: 1) {
//                    let attachment = Attachment(type: .image, fileName: fileName, fileData: imageData)
//                    attachments.append(attachment)
//                    return ["fileName": fileName, "fileData": imageData]
//                }
//                
//                return nil
//            }
//            
//            let message = ChatMessage(roomName: room.roomName, senderID: LoginManager.shared.getUserEmail, senderNickname: UserProfile.shared.nickname ?? "", msg: "", sentAt: Date(), attachments: attachments)
//            try await FirebaseManager.shared.saveMessage(message, room)
//            
//            socket.emit("send images", ["roomName": message.roomName, "senderID": message.senderID, "senderNickName": message.senderNickname, "sentAt": "\(message.sentAt ?? Date())", "images": imageDataArray])
//        }
        
        Task {
            let imageNames = try await FirebaseStorageManager.shared.uploadImagesToStorage(images: images, location: ImageLocation.Message)
            var attachments = [Attachment]()
            
            let imageDataArray = try await withThrowingTaskGroup(of: [String:Any]?.self) { group in
                for (index, _) in images.enumerated() {
                    
                    group.addTask {
                        guard let imageData = images[index].jpegData(compressionQuality: 0.3) else {
                            return nil
                        }
                        
                        let attachment = Attachment(type: .image, fileName: imageNames[index], fileData: imageData)
                        attachments.append(attachment)
                        
                        return ["fileName": imageNames[index], "fileData": imageData]
                    }
                    
                }
                
                var results = [[String: Any]]()
                for try await result in group {
                    
                    if let result = result {
                        results.append(result)
                    }
                    
                }
                
                return results
            }
            
            let message = ChatMessage(roomName: room.roomName, senderID: LoginManager.shared.getUserEmail, senderNickname: UserProfile.shared.nickname ?? "", msg: "", sentAt: Date(), attachments: attachments)
            try await FirebaseManager.shared.saveMessage(message, room)
            
            socket.emit("send images", ["roomName": message.roomName, "senderID": message.senderID, "senderNickName": message.senderNickname, "sentAt": "\(message.sentAt ?? Date())", "images": imageDataArray])
        }
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
            
            let message = ChatMessage(roomName: roomName, senderID: senderID, senderNickname: senderNickName, msg: messageText, sentAt: Date(), attachments: nil)
            
            DispatchQueue.main.async {
                self.receivedMessagePublisher.send(message)
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
            
            // String -> Date 변환
            let dateFormatter = ISO8601DateFormatter()
            let sentAt = dateFormatter.date(from: sentAtString) ?? Date()
            
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
                self.receivedMessagePublisher.send(message)
            }
        }
    }
}
