import Foundation
import Combine
import AVFoundation
import PhotosUI

class ChatViewModel {
    private let chatService: ChatService
    private var cancellables = Set<AnyCancellable>()
    
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    init(chatService: ChatService = ChatService()) {
        self.chatService = chatService
        setupBindings()
    }
    
    private func setupBindings() {
        chatService.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.messages.append(message)
            }
            .store(in: &cancellables)
    }
    
    func sendMessage(_ text: String, roomId: String) {
        chatService.sendMessage(text, roomId: roomId)
    }
    
    func sendMedia(_ media: [MediaItem], roomId: String) {
        chatService.sendMedia(media, roomId: roomId)
    }
    
    func joinRoom(_ roomName: String) {
        chatService.joinRoom(roomName)
    }
    
    func leaveRoom(_ roomName: String) {
        chatService.leaveRoom(roomName)
    }
} 