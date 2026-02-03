//
//  HotUserManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import Combine

private struct HotUser {
    let email: String
    var lastSeenAt: Date
}

final class HotUserManager: HotUserManagerProtocol {
    private let firebaseManager: FirebaseManager
    private let maxHotUsers: Int = 20
    
    private var hotUsers: [HotUser] = []
    private var hotUserCancellables: [String: AnyCancellable] = [:]
    
    init(firebaseManager: FirebaseManager = .shared) {
        self.firebaseManager = firebaseManager
    }
    
    func updateHotUserPool(for email: String, lastSeenAt: Date) {
        // 이미 핫 유저면 lastSeenAt만 갱신
        if let idx = hotUsers.firstIndex(where: { $0.email == email }) {
            hotUsers[idx].lastSeenAt = lastSeenAt
            return
        }
        
        // 새 유저인데 자리가 남아 있으면 추가
        if hotUsers.count < maxHotUsers {
            hotUsers.append(HotUser(email: email, lastSeenAt: lastSeenAt))
            return
        }
        
        // 새 유저이고 이미 꽉 차 있으면 가장 오래된 유저 교체
        if let oldestIndex = hotUsers.indices.min(by: { hotUsers[$0].lastSeenAt < hotUsers[$1].lastSeenAt }) {
            let oldEmail = hotUsers[oldestIndex].email
            
            // 오래된 유저 구독 해제
            unbindHotUser(email: oldEmail)
            
            // 새 유저로 교체
            hotUsers[oldestIndex] = HotUser(email: email, lastSeenAt: lastSeenAt)
        }
    }
    
    func seedHotUserPool(with messages: [ChatMessage]) {
        guard !messages.isEmpty else { return }
        
        let sorted = messages.sorted { $0.sentAt ?? Date() > $1.sentAt ?? Date() }
        var seen = Set<String>()
        
        for msg in sorted {
            let email = msg.senderID
            guard !email.isEmpty else { continue }
            if !seen.insert(email).inserted { continue }
            
            updateHotUserPool(for: email, lastSeenAt: msg.sentAt ?? Date())
            if hotUsers.count >= maxHotUsers { break }
        }
    }
    
    func bindHotUser(email: String, onProfileChanged: @escaping (UserProfile) -> Void) -> AnyCancellable? {
        if hotUserCancellables[email] != nil { return nil } // 이미 구독 중
        
        let cancellable = firebaseManager
            .userProfilePublisher(email: email)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let err) = completion {
                        print("⚠️ profile publisher error:", err)
                    }
                },
                receiveValue: { profile in
                    onProfileChanged(profile)
                }
            )
        
        hotUserCancellables[email] = cancellable
        return cancellable
    }
    
    func resetHotUserPool() {
        for user in hotUsers {
            unbindHotUser(email: user.email)
        }
        hotUsers.removeAll()
    }
    
    func getHotUserEmails() -> [String] {
        return hotUsers.map { $0.email }
    }
    
    private func unbindHotUser(email: String) {
        hotUserCancellables[email]?.cancel()
        hotUserCancellables[email] = nil
        firebaseManager.stopListenUserProfile(email: email)
    }
}

