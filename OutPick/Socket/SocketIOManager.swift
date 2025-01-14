//
//  SocketIOManager.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit
import SocketIO

class SocketIOManager {
    
    static let shared = SocketIOManager()
    
    var manager: SocketManager!
    var socket: SocketIOClient!
    
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
        socket.connect()
        completion()
    }
    
    func closeConnection() {
        socket.disconnect()
    }

    func joinRoom(_ roomName: String) {
        socket.emit("join room", roomName)
    }
    
    func createRoom(_ roomName: String) {
        socket.emit("create room", roomName)
    }
    
    func sendMessage(_ roomName: String, _ message: String) {
        socket.emit("chat message", ["roomName": roomName, "message": message])
    }
    
    func setUserName(_ userName: String) {
        print("setUserName 호출됨: \(userName)")
        socket.emit("set username", userName)
        print("유저 이름 이벤트 emit 완료")
    }
}
