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
    var receivedImagesPublisher = PassthroughSubject<[UIImage], Never>()
    var receviedMessagePublisher = PassthroughSubject<ChatMessage, Never>()
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
            guard let self = self else { return }
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
        socket.emit("chat message", message.toSocketRepresentation())
        Task { try await FirebaseManager.shared.saveMessage(message, room) }
    }
    
    func sendImages(_ room: ChatRoom, _ images: [UIImage]) {
        guard socket.status == .connected else {
            print("소켓이 연결되지 않음")
            return
        }
        
        var imageDataArray = Array<Data?>(repeating: nil, count: images.count)
        
        images.forEach {
            if let imageData = $0.jpegData(compressionQuality: 1) {
                imageDataArray.append(imageData)
            }
        }

        // 이미지 Storage에 저장 및 이미지 데이터 Firestore에 저장
        Task {
            let imageNames = try await FirebaseStorageManager.shared.uploadImagesToStorage(images: images, location: ImageLocation.Message)
            var attachments = [Attachment]()
            
            imageNames.forEach {
                let temp = Attachment(type: Attachment.AttachmentType.image, fileName: $0)
                attachments.append(temp)
            }
            
            let tempMessage = ChatMessage(roomName: room.roomName, senderID: room.creatorID, senderNickname: UserProfile.shared.nickname ?? "", msg: nil, sentAt: Date(), attachments: attachments)
            try await FirebaseManager.shared.saveMessage(tempMessage, room)
        }
        
        socket.emit("send images", ["roomName": room.roomName, "images": imageDataArray.compactMap{$0}])
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
            let senderNickName = messageData["senderNickname"] as! String
            let messageText = messageData["msg"] as! String
            
            DispatchQueue.main.async {
                let message = ChatMessage(roomName: roomName, senderID: senderID, senderNickname: senderNickName, msg: messageText, sentAt: Date(), attachments: nil)
                self.receviedMessagePublisher.send(message)
            }
        }
        
        // 중복 방지를 위해 기존 리스너 제거
        socket.off("receiveImages")
        socket.on("receiveImages") { dataArray, _ in
            if let data = dataArray.first as? [String: Any],
               let imageDataArray = data["images"] as? [Data] {
                var images: [UIImage] = []
                for imageData in imageDataArray {
                    if let image = UIImage(data: imageData) {
                        images.append(image)
                    }
                }

                DispatchQueue.main.async {
                    self.receivedImagesPublisher.send(images)
                }
            }
        }
    }
}
