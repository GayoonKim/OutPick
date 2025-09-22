//
//  BannerManager.swift
//  OutPick
//
//  Created by 김가윤 on 9/22/25.
//

import Foundation
import UIKit
import Combine

final class BannerManager {
    static let shared = BannerManager()
    private init() {}

    private var cancellables: [String: AnyCancellable] = [:]
    
    // 배너 탭 이벤트 퍼블리셔
    let bannerTapped = PassthroughSubject<String, Never>() // roomID 전달
    
    func startListening(for roomID: String) {
        print(#function, "startListening:", roomID)
        
        if cancellables[roomID] != nil { return }
        
        let cancellable = SocketIOManager.shared.subscribeToMessages(for: roomID)
            .sink { [weak self] message in
                print(#function, "✅✅✅✅✅ 4. message:", message)
                self?.handleIncomingMessage(message, in: roomID)
            }
        cancellables[roomID] = cancellable
    }
    
    func stopListening(for roomID: String) {
        cancellables[roomID]?.cancel()
        cancellables[roomID] = nil
        SocketIOManager.shared.unsubscribeFromMessages(for: roomID)
    }
    
    func stopAll() {
        cancellables.values.forEach { $0.cancel() }
        cancellables.removeAll()
    }
    
    private func handleIncomingMessage(_ message: ChatMessage, in roomID: String) {
        if ChatViewController.currentRoomID == roomID { return }
        DispatchQueue.main.async {
            self.showBanner(for: message, in: roomID)
        }
    }
    
    private func showBanner(for message: ChatMessage, in roomID: String) {
        print(#function, "message: \(message), roomID: \(roomID)")
        
        let banner = ChatBannerView()
        banner.configure(
            title: message.senderNickname,
            subtitle: message.msg ?? "새 메시지",
            onTap: { [weak self] in
                guard let self = self else { return }
                self.bannerTapped.send(roomID)
            }
        )
        banner.show()
    }
}
