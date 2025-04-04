import Foundation
import SocketIO

class ChatModel {
    private let socketManager: SocketIOManager
    private var messages: [ChatMessage] = []
    
    var onMessagesUpdated: (([ChatMessage]) -> Void)?
    
    init(socketManager: SocketIOManager = .shared) {
        self.socketManager = socketManager
        setupSocketListeners()
    }
    
    private func setupSocketListeners() {
        socketManager.socket.on("chat message") { [weak self] data, _ in
            if let message = self?.parseChatMessage(data) {
                self?.messages.append(message)
                self?.onMessagesUpdated?(self?.messages ?? [])
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
    
    func getMessages() -> [ChatMessage] {
        return messages
    }
} 