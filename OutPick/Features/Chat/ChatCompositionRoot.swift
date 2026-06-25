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
        repositories: FirebaseRepositoryProviding,
        roomImageManager: RoomImageManaging,
        mediaProcessor: MediaProcessingServiceProtocol,
        makeCreatedRoomViewController: @escaping (ChatRoom) -> ChatViewController?
    ) -> RoomCreateViewController {
        let createRoomUseCase = CreateRoomUseCase(
            chatRoomRepository: repositories.chatRoomRepository,
            imageStorageRepository: repositories.imageStorageRepository,
            roomImageManager: roomImageManager
        )
        let viewModel = RoomCreateViewModel(createRoomUseCase: createRoomUseCase)
        return RoomCreateViewController(
            viewModel: viewModel,
            mediaProcessor: mediaProcessor,
            makeCreatedRoomViewController: makeCreatedRoomViewController
        )
    }

    static func makeChatRoomSettingPanel(
        room: ChatRoom,
        repositories: FirebaseRepositoryProviding,
        attachmentImageLoader: ChatAttachmentImageLoading,
        videoResolver: ChatVideoPlaybackResolving,
        photoLibrarySaver: PhotoLibrarySaving,
        roomImageManager: RoomImageManaging,
        avatarImageManager: AvatarImageManaging,
        networkStatusProvider: NetworkStatusProviding,
        exitUseCase: ChatRoomExitUseCaseProtocol,
        onEvent: @escaping (ChatRoomSettingEvent) -> Void = { _ in }
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
            attachmentImageLoader: attachmentImageLoader,
            avatarImageManager: avatarImageManager,
            loadParticipantsUseCase: participantsUseCase,
            loadMediaUseCase: mediaUseCase,
            exitUseCase: exitUseCase,
            networkStatusProvider: networkStatusProvider
        )
        let settingVC = ChatRoomSettingViewController(
            viewModel: settingViewModel,
            attachmentImageLoader: attachmentImageLoader,
            videoResolver: videoResolver,
            photoLibrarySaver: photoLibrarySaver,
            roomImageManager: roomImageManager,
            avatarImageManager: avatarImageManager
        )
        settingVC.onEvent = onEvent
        return settingVC
    }

    static func makeRoomEditViewController(
        room: ChatRoom,
        repositories: FirebaseRepositoryProviding,
        roomImageManager: RoomImageManaging,
        mediaProcessor: MediaProcessingServiceProtocol,
        onRoomEdited: @escaping @MainActor (ChatRoom) async -> Void
    ) -> RoomEditViewController {
        let editUseCase = RoomEditUseCase(
            chatRoomRepository: repositories.chatRoomRepository,
            imageStorageRepository: repositories.imageStorageRepository,
            roomImageManager: roomImageManager
        )
        let editViewModel = RoomEditViewModel(room: room, useCase: editUseCase)
        let editVC = RoomEditViewController(
            viewModel: editViewModel,
            mediaProcessor: mediaProcessor
        )
        editVC.onRoomEdited = onRoomEdited
        return editVC
    }
}
