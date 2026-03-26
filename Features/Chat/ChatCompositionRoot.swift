//
//  ChatCompositionRoot.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import UIKit

/// Chat 탭 조립 전담 CompositionRoot
@MainActor
enum ChatCompositionRoot {
    static func makeRoomListRoot(coordinator: ChatCoordinator) -> UIViewController {
        coordinator.makeRoomListRoot()
    }

    static func makeJoinedRoomsRoot(coordinator: ChatCoordinator) -> UIViewController {
        coordinator.makeJoinedRoomsRoot()
    }

    static func makeRoomCreateViewController(
        provider: ChatManagerProviding,
        repositories: FirebaseRepositoryProviding,
        makeCreatedRoomViewController: @escaping (ChatRoom) -> ChatViewController?
    ) -> RoomCreateViewController {
        let createRoomUseCase = CreateRoomUseCase(
            chatRoomRepository: repositories.chatRoomRepository,
            imageStorageRepository: repositories.imageStorageRepository,
            roomImageManager: provider.roomImageManager
        )
        let viewModel = RoomCreateViewModel(createRoomUseCase: createRoomUseCase)
        return RoomCreateViewController(
            viewModel: viewModel,
            makeCreatedRoomViewController: makeCreatedRoomViewController
        )
    }

    static func makeChatRoomSettingPanel(
        room: ChatRoom,
        provider: ChatManagerProviding,
        repositories: FirebaseRepositoryProviding,
        onRoomUpdated: ((ChatRoom) -> Void)? = nil
    ) -> ChatRoomSettingViewController {
        let participantsRepository = GRDBChatRoomParticipantsRepository()
        let localMediaRepository = GRDBChatRoomMediaIndexRepository()
        let remoteMediaRepository = FirebaseChatRoomMediaIndexAdapter(
            repository: repositories.mediaIndexRepository
        )
        let participantsUseCase = LoadChatRoomParticipantsUseCase(
            participantsRepository: participantsRepository,
            userProfileRepository: repositories.userProfileRepository
        )
        let mediaUseCase = LoadChatRoomMediaUseCase(
            localMediaRepository: localMediaRepository,
            remoteMediaRepository: remoteMediaRepository
        )
        let initialParticipants = (
            try? participantsUseCase.loadLocalInitial(room: room)
        ) ?? ChatRoomParticipantsLoadResult(users: [], hasMore: false)
        let settingViewModel = ChatRoomSettingViewModel(
            room: room,
            initialParticipants: initialParticipants,
            mediaManager: provider.mediaManager,
            avatarImageManager: provider.avatarImageManager,
            loadParticipantsUseCase: participantsUseCase,
            loadMediaUseCase: mediaUseCase,
            networkStatusProvider: provider.networkStatusProvider
        )
        let settingVC = ChatRoomSettingViewController(
            viewModel: settingViewModel,
            mediaManager: provider.mediaManager,
            roomImageManager: provider.roomImageManager,
            avatarImageManager: provider.avatarImageManager
        )
        settingVC.onRoomUpdated = onRoomUpdated
        return settingVC
    }

    static func makeRoomEditViewController(
        room: ChatRoom,
        provider: ChatManagerProviding,
        repositories: FirebaseRepositoryProviding,
        onRoomEdited: @escaping @MainActor (ChatRoom) async -> Void
    ) -> RoomEditViewController {
        let editUseCase = RoomEditUseCase(
            chatRoomRepository: repositories.chatRoomRepository,
            imageStorageRepository: repositories.imageStorageRepository,
            roomImageManager: provider.roomImageManager
        )
        let editViewModel = RoomEditViewModel(room: room, useCase: editUseCase)
        let editVC = RoomEditViewController(viewModel: editViewModel)
        editVC.onRoomEdited = onRoomEdited
        return editVC
    }
}
