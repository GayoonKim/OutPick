//
//  ChatContainer.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import Foundation
import Combine

/// Chat feature DI container.
@MainActor
final class ChatContainer {
    let provider: ChatManagerProviding
    let firebaseRepositories: FirebaseRepositoryProviding
    let roomRepository: FirebaseChatRoomRepositoryProtocol
    let userProfileRepository: UserProfileRepositoryProtocol
    let joinedRoomsStore: JoinedRoomsStore
    let roomReadStateStore: ChatRoomReadStateStore
    let currentUserProvider: CurrentUserProviding

    private let roomListUseCase: RoomListUseCaseProtocol
    private let joinedRoomsUseCase: JoinedRoomsUseCaseProtocol
    private let roomSearchUseCase: RoomSearchUseCaseProtocol
    private let chatRoomMessageUseCase: ChatRoomMessageUseCaseProtocol
    private let chatMessageSendingRepository: ChatMessageSendingRepositoryProtocol
    private let chatRoomRealtimeUseCase: ChatRoomRealtimeUseCaseProtocol
    private let chatRoomRuntimeUseCase: ChatRoomRuntimeUseCaseProtocol
    private let chatInitialLoadUseCase: ChatInitialLoadUseCaseProtocol
    private let chatRoomSearchUseCase: ChatRoomSearchUseCaseProtocol
    private let chatRoomLifecycleUseCase: ChatRoomLifecycleUseCaseProtocol
    private let chatRoomExitUseCase: ChatRoomExitUseCaseProtocol
    private let chatMediaUploadUseCase: ChatMediaUploadUseCaseProtocol
    private let loadShareableJoinedRoomsUseCase: LoadShareableJoinedRoomsUseCaseProtocol
    private let shareLookbookContentToChatUseCase: ShareLookbookContentToChatUseCaseProtocol
    private var joinedRoomsRuntimeCancellable: AnyCancellable?
    private var isJoinedRoomsRuntimeBound = false
    private var runtimeJoinedRooms: Set<String> = []

    init(
        provider: ChatManagerProviding = ChatManagerProvider(),
        roomRepository: FirebaseChatRoomRepositoryProtocol? = nil,
        userProfileRepository: UserProfileRepositoryProtocol? = nil,
        joinedRoomsStore: JoinedRoomsStore,
        roomReadStateStore: ChatRoomReadStateStore? = nil,
        announcementRepository: FirebaseAnnouncementRepositoryProtocol? = nil,
        repositories: FirebaseRepositoryProviding = FirebaseRepositoryProvider.shared
    ) {
        self.provider = provider
        self.firebaseRepositories = repositories
        self.roomRepository = roomRepository ?? repositories.chatRoomRepository
        self.userProfileRepository = userProfileRepository ?? repositories.userProfileRepository
        self.joinedRoomsStore = joinedRoomsStore
        self.currentUserProvider = LoginManagerCurrentUserProvider()
        let resolvedRoomReadStateStore = roomReadStateStore ?? ChatRoomReadStateStore()
        self.roomReadStateStore = resolvedRoomReadStateStore
        let announcementRepository = announcementRepository ?? repositories.announcementRepository
        self.roomListUseCase = RoomListUseCase(roomRepository: self.roomRepository)
        self.chatRoomExitUseCase = ChatRoomExitUseCase(
            repository: SocketChatRoomExitRepository(),
            localCleaner: DefaultChatRoomLocalExitCleaner(joinedRoomsStore: joinedRoomsStore)
        )
        self.joinedRoomsUseCase = JoinedRoomsUseCase(
            roomRepository: self.roomRepository,
            userProfileRepository: self.userProfileRepository,
            exitUseCase: self.chatRoomExitUseCase
        )
        self.roomSearchUseCase = RoomSearchUseCase(roomRepository: self.roomRepository)
        self.chatMessageSendingRepository = SocketChatMessageSendingRepository()
        self.chatRoomMessageUseCase = ChatRoomMessageUseCase(
            messageManager: provider.messageManager,
            sendingRepository: chatMessageSendingRepository,
            deletedLastMessageSummaryUpdater: self.roomRepository as? ChatDeletedLastMessageSummaryUpdating
        )
        self.chatRoomRealtimeUseCase = ChatRoomRealtimeUseCase(
            repository: SocketChatRoomRealtimeRepository()
        )
        self.chatRoomRuntimeUseCase = ChatRoomRuntimeUseCase(
            repository: SocketChatRoomRuntimeRepository(),
            visibilityRuntimeManager: DefaultChatRoomVisibilityRuntimeManager(),
            transientLocalDataCleaner: DefaultChatRoomTransientLocalDataCleaner()
        )
        self.chatInitialLoadUseCase = DefaultChatInitialLoadUseCase(
            messageManager: provider.messageManager,
            userProfileRepository: self.userProfileRepository,
            chatRoomRepository: self.roomRepository,
            networkStatusProvider: provider.networkStatusProvider
        )
        self.chatRoomSearchUseCase = ChatRoomSearchUseCase(searchManager: provider.searchManager)
        self.chatRoomLifecycleUseCase = ChatRoomLifecycleUseCase(
            chatRoomRepository: self.roomRepository,
            userProfileRepository: self.userProfileRepository,
            joinedRoomsStore: joinedRoomsStore,
            announcementRepository: announcementRepository
        )
        self.chatMediaUploadUseCase = ChatMediaUploadUseCase(
            imageStorageRepository: repositories.imageStorageRepository,
            videoStorageRepository: FirebaseVideoStorageRepository.shared
        )
        let lookbookChatShareSendingRepository = SocketLookbookChatShareSendingRepository()
        self.loadShareableJoinedRoomsUseCase = LoadShareableJoinedRoomsUseCase(
            joinedRoomsUseCase: self.joinedRoomsUseCase
        )
        self.shareLookbookContentToChatUseCase = ShareLookbookContentToChatUseCase(
            repository: lookbookChatShareSendingRepository
        )
    }

    func makeRoomListsViewModel() -> RoomListsViewModel {
        RoomListsViewModel(useCase: roomListUseCase)
    }

    func makeJoinedRoomsViewModel() -> JoinedRoomsViewModel {
        JoinedRoomsViewModel(
            useCase: joinedRoomsUseCase,
            roomReadStateStore: roomReadStateStore
        )
    }

    func makeRoomSearchViewModel() -> RoomSearchViewModel {
        RoomSearchViewModel(useCase: roomSearchUseCase)
    }

    func makeChatRoomViewModel(room: ChatRoom) -> ChatRoomViewModel {
        ChatRoomViewModel(
            room: room,
            initialLoadUseCase: chatInitialLoadUseCase,
            messageUseCase: chatRoomMessageUseCase,
            searchUseCase: chatRoomSearchUseCase,
            lifecycleUseCase: chatRoomLifecycleUseCase,
            realtimeUseCase: chatRoomRealtimeUseCase,
            runtimeUseCase: chatRoomRuntimeUseCase,
            currentUserProvider: currentUserProvider,
            roomReadStateStore: roomReadStateStore
        )
    }

    func makeLoadShareableJoinedRoomsUseCase() -> LoadShareableJoinedRoomsUseCaseProtocol {
        loadShareableJoinedRoomsUseCase
    }

    func makeShareLookbookContentToChatUseCase() -> ShareLookbookContentToChatUseCaseProtocol {
        shareLookbookContentToChatUseCase
    }

    func makeChatRoomExitUseCase() -> ChatRoomExitUseCaseProtocol {
        chatRoomExitUseCase
    }

    func makeChatMediaUploadUseCase() -> ChatMediaUploadUseCaseProtocol {
        chatMediaUploadUseCase
    }

    func bindJoinedRoomsRuntimeIfNeeded() {
        guard !isJoinedRoomsRuntimeBound else { return }
        isJoinedRoomsRuntimeBound = true

        joinedRoomsRuntimeCancellable = joinedRoomsStore.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] joinedSet in
                guard let self else { return }
                let joinedRooms = Array(joinedSet)
                BannerManager.shared.start(for: joinedRooms)

                let toJoin = joinedSet.subtracting(self.runtimeJoinedRooms)
                let toLeave = self.runtimeJoinedRooms.subtracting(joinedSet)
                self.runtimeJoinedRooms = joinedSet

                for roomID in toJoin {
                    SocketIOManager.shared.joinRoom(roomID)
                }
                for roomID in toLeave {
                    SocketIOManager.shared.leaveRoom(roomID)
                }
            }
    }
}
