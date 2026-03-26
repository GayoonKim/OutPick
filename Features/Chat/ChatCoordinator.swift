//
//  ChatCoordinator.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import UIKit

@MainActor
protocol ChatRoomRouting: AnyObject {
    func showSettings(from source: ChatViewController)
}

@MainActor
final class ChatCoordinator {

    private let container: ChatContainer

    init(container: ChatContainer) {
        self.container = container
    }

    func makeRoomListRoot() -> UIViewController {
        let listVC = RoomListsCollectionViewController(
            collectionViewLayout: UICollectionViewFlowLayout(),
            viewModel: container.makeRoomListsViewModel()
        )

        listVC.onSelectRoom = { [weak self, weak listVC] room in
            guard let self, let source = listVC else { return }
            self.presentChatRoom(room: room, from: source)
        }
        listVC.onCreateRoom = { [weak self, weak listVC] in
            guard let self, let source = listVC else { return }
            self.presentCreateRoom(from: source)
        }
        listVC.onSearchRoom = { [weak self, weak listVC] in
            guard let self, let source = listVC else { return }
            self.presentSearch(from: source)
        }

        let nav = UINavigationController(rootViewController: listVC)
        nav.isNavigationBarHidden = true
        return nav
    }

    func makeJoinedRoomsRoot() -> UIViewController {
        let joinedVC = JoinedRoomsViewController(
            viewModel: container.makeJoinedRoomsViewModel(),
            roomImageManager: container.provider.roomImageManager
        )
        print(#function, joinedVC)
        joinedVC.onOpenRoom = { [weak self, weak joinedVC] room in
            guard let self, let source = joinedVC else { return }
            self.presentChatRoom(room: room, from: source)
        }
        joinedVC.onCreateRoom = { [weak self, weak joinedVC] in
            guard let self, let source = joinedVC else { return }
            self.presentCreateRoom(from: source)
        }
        joinedVC.onSearchRoom = { [weak self, weak joinedVC] in
            guard let self, let source = joinedVC else { return }
            self.presentSearch(from: source)
        }

        let nav = UINavigationController(rootViewController: joinedVC)
        nav.isNavigationBarHidden = true
        return nav
    }

    private func presentChatRoom(room: ChatRoom, from source: UIViewController) {
        let chatRoomVC = makeChatRoomViewController(room: room, isRoomSaving: false)
        ChatModalTransitionManager.present(chatRoomVC, from: source)
    }

    private func presentCreateRoom(from source: UIViewController) {
        ChatDependencyContainer.provider = container.provider
        ChatDependencyContainer.firebaseRepositories = container.firebaseRepositories
        let createVC = ChatCompositionRoot.makeRoomCreateViewController(
            provider: container.provider,
            repositories: container.firebaseRepositories,
            makeCreatedRoomViewController: { [weak self] room in
                self?.makeChatRoomViewController(room: room, isRoomSaving: true)
            }
        )
        createVC.modalPresentationStyle = .fullScreen
        ChatModalTransitionManager.present(createVC, from: source)
    }

    private func presentSearch(from source: UIViewController) {
        let searchVC = RoomSearchViewController(viewModel: container.makeRoomSearchViewModel())
        searchVC.onSelectRoom = { [weak self, weak searchVC] room in
            guard let self, let searchVC else { return }
            self.presentChatRoomFromSearch(room: room, searchVC: searchVC)
        }
        searchVC.modalPresentationStyle = .fullScreen
        ChatModalTransitionManager.present(searchVC, from: source)
    }

    private func presentChatRoomFromSearch(room: ChatRoom, searchVC: RoomSearchViewController) {
        let chatRoomVC = makeChatRoomViewController(room: room, isRoomSaving: false)

        guard let presenter = searchVC.presentingViewController else { return }
        searchVC.dismiss(animated: false) {
            presenter.present(chatRoomVC, animated: true)
        }
    }

    private func presentRoomEdit(from source: ChatRoomSettingViewController, room: ChatRoom) {
        let editVC = ChatCompositionRoot.makeRoomEditViewController(
            room: room,
            provider: container.provider,
            repositories: container.firebaseRepositories,
            onRoomEdited: { [weak source] updatedRoom in
                guard let source else { return }
                await source.applyEditedRoom(updatedRoom)
            }
        )
        editVC.modalPresentationStyle = .fullScreen
        source.present(editVC, animated: true)
    }

    private func makeChatRoomViewController(room: ChatRoom, isRoomSaving: Bool) -> ChatViewController {
        ChatDependencyContainer.provider = container.provider
        ChatDependencyContainer.firebaseRepositories = container.firebaseRepositories

        let chatRoomVC = ChatViewController(provider: container.provider)

        chatRoomVC.injectedFirebaseRepositories = container.firebaseRepositories
        chatRoomVC.configure(viewModel: container.makeChatRoomViewModel(room: room))
        chatRoomVC.isRoomSaving = isRoomSaving
        chatRoomVC.router = self
        chatRoomVC.modalPresentationStyle = .fullScreen
        return chatRoomVC
    }
}

extension ChatCoordinator: ChatRoomRouting {
    func showSettings(from source: ChatViewController) {
        guard let room = source.room else { return }

        let settingVC = ChatCompositionRoot.makeChatRoomSettingPanel(
            room: room,
            provider: container.provider,
            repositories: container.firebaseRepositories,
            onRoomUpdated: { [weak source] updatedRoom in
                Task { @MainActor in
                    source?.applyUpdatedRoom(updatedRoom)
                }
            }
        )
        settingVC.onRequestEditRoom = { [weak self, weak settingVC] room in
            guard let self, let settingVC else { return }
            self.presentRoomEdit(from: settingVC, room: room)
        }
        source.presentSettingPanel(settingVC)
    }
}
