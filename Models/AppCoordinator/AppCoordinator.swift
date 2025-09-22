//  AppCoordinator.swift
//  OutPick
//
//  Created by 김가윤 on 2025/09/22.
//

import UIKit

protocol Coordinator {
    func start()
}

/// 전역 화면 전환을 관리하는 AppCoordinator
final class AppCoordinator: Coordinator {
    private weak var window: UIWindow?

    init(window: UIWindow?) {
        self.window = window
    }

    func start() {
        // 필요 시 초기 루트 세팅 로직을 배치하세요.
        // 현재는 SceneDelegate에서 루트 세팅을 수행 중이므로 비워둡니다.
    }

    /// ChatRoom 객체가 준비된 경우 바로 채팅방으로 이동
    func showChatRoom(room: ChatRoom, isRoomSaving: Bool) {
        guard let window = window else { return }

        // Root를 UITabBarController 기반으로 가정
        if let tabBar = window.rootViewController as? UITabBarController,
           let nav = tabBar.selectedViewController as? UINavigationController {
            let chatVC = ChatViewController()
            chatVC.room = room
            chatVC.isRoomSaving = isRoomSaving
            nav.pushViewController(chatVC, animated: true)
            return
        }

        // Fallback: Root가 탭바가 아닐 때 간단히 푸시/프리젠트
        if let nav = window.rootViewController as? UINavigationController {
            let chatVC = ChatViewController()
            chatVC.room = room
            chatVC.isRoomSaving = isRoomSaving
            nav.pushViewController(chatVC, animated: true)
        } else {
            let chatVC = ChatViewController()
            chatVC.room = room
            chatVC.isRoomSaving = isRoomSaving
            window.rootViewController?.present(chatVC, animated: true)
        }
    }

    /// roomID만 있는 경우: 방 정보를 로드한 후 위 showChatRoom(room:isRoomSaving:)으로 연결
    /// 실제 데이터 로드는 프로젝트의 Repository/Manager에 맞게 구현하세요.
    func loadAndShowChatRoom(roomID: String, isRoomSaving: Bool = false) {
        Task { @MainActor in
            // 1) 로컬(DB) 우선 조회 → 실패 시 서버 조회 순으로 시도하는 것을 권장합니다.
            // 아래는 예시이며, 실제 메서드명은 프로젝트에 맞게 교체하세요.

            var resolvedRoom: ChatRoom?

            // 예: GRDB에서 우선 조회 (프로젝트 메서드명에 맞게 변경하세요)
            if let room = try? GRDBManager.shared.fetchRoomInfo(roomID: roomID) {
                resolvedRoom = room
            }

            // 예: 원격(Firebase)에서 최신 데이터 조회 (프로젝트 메서드명에 맞게 변경하세요)
            if resolvedRoom == nil {
                do {
                    let room = try await FirebaseManager.shared.fetchRoomInfoWithID(roomID: roomID)
                    resolvedRoom = room
                } catch {
                    print("[AppCoordinator] 원격 room 조회 실패: \(error)")
                }
            }

            guard let room = resolvedRoom else {
                print("[AppCoordinator] room 정보를 찾지 못했습니다. roomID=\(roomID)")
                return
            }

            self.showChatRoom(room: room, isRoomSaving: isRoomSaving)
        }
    }
}
