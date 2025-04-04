import Foundation
import Combine
import SocketIO

class ChatService {
    private let socketManager: SocketIOManager
    let messagePublisher = PassthroughSubject<ChatMessage, Never>()
    
    init(socketManager: SocketIOManager = .shared) {
        self.socketManager = socketManager
        setupSocketListeners()
    }
    
    private func setupSocketListeners() {
        socketManager.socket.on("chat message") { [weak self] data, _ in
            if let message = self?.parseChatMessage(data) {
                self?.messagePublisher.send(message)
            }
        }
    }
    
    func establishConnection(completion: @escaping () -> Void) {
        socketManager.establishConnection(completion: completion)
    }
    
    func joinRoom(_ roomName: String) {
        socketManager.joinRoom(roomName)
    }
    
    func leaveRoom(_ roomName: String) {
        socketManager.leaveRoom(roomName)
    }
    
    func sendMessage(_ text: String, roomId: String) {
        socketManager.sendMessage(text, roomId: roomId)
    }
    
    func sendMedia(_ media: [MediaItem], roomId: String) {
        // 미디어 전송 로직 구현
    }
    
    private func parseChatMessage(_ data: [Any]) -> ChatMessage? {
        // 메시지 파싱 로직 구현
        return nil
    }
} 