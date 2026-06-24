//
//  ChatContainer.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import Foundation

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
    private let chatOutgoingOutboxUseCase: ChatOutgoingOutboxUseCaseProtocol
    private let attachmentImageLoader: ChatAttachmentImageLoading
    private let chatVideoAssetLoader: ChatVideoAssetLoading
    private let chatVideoThumbnailGenerator: ChatVideoThumbnailGenerating
    private let storageDownloadURLCache: ChatStorageURLResolving
    private let chatVideoDiskCache: ChatVideoDiskCaching
    private let chatRemoteFileDownloader: ChatRemoteFileDownloading
    private let chatVideoPlaybackResolver: ChatVideoPlaybackResolving
    private let photoLibrarySaver: PhotoLibrarySaving
    private let mediaProcessor: MediaProcessingServiceProtocol
    private let loadShareableJoinedRoomsUseCase: LoadShareableJoinedRoomsUseCaseProtocol
    private let shareLookbookContentToChatUseCase: ShareLookbookContentToChatUseCaseProtocol

    init(
        provider: ChatManagerProviding? = nil,
        roomRepository: FirebaseChatRoomRepositoryProtocol? = nil,
        userProfileRepository: UserProfileRepositoryProtocol? = nil,
        joinedRoomsStore: JoinedRoomsStore,
        roomReadStateStore: ChatRoomReadStateStore? = nil,
        announcementRepository: FirebaseAnnouncementRepositoryProtocol? = nil,
        repositories: FirebaseRepositoryProviding = FirebaseRepositoryProvider.shared
    ) {
        self.firebaseRepositories = repositories
        let attachmentImageLoader = ChatAttachmentImageService(
            imageStorageRepository: repositories.imageStorageRepository
        )
        self.attachmentImageLoader = attachmentImageLoader
        let resolvedProvider = provider ?? ChatManagerProvider(repositories: repositories)
        self.provider = resolvedProvider
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
            messageManager: resolvedProvider.messageManager,
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
            messageManager: resolvedProvider.messageManager,
            userProfileRepository: self.userProfileRepository,
            chatRoomRepository: self.roomRepository,
            networkStatusProvider: resolvedProvider.networkStatusProvider
        )
        self.chatRoomSearchUseCase = ChatRoomSearchUseCase(searchManager: resolvedProvider.searchManager)
        self.chatRoomLifecycleUseCase = ChatRoomLifecycleUseCase(
            chatRoomRepository: self.roomRepository,
            userProfileRepository: self.userProfileRepository,
            joinedRoomsStore: joinedRoomsStore,
            announcementRepository: announcementRepository
        )
        self.chatMediaUploadUseCase = ChatMediaUploadUseCase(
            imageStorageRepository: repositories.imageStorageRepository,
            videoStorageRepository: repositories.videoStorageRepository,
            attachmentImageLoader: attachmentImageLoader
        )
        self.chatOutgoingOutboxUseCase = ChatOutgoingOutboxUseCase(
            imageStorageRepository: repositories.imageStorageRepository,
            videoStorageRepository: repositories.videoStorageRepository
        )
        self.storageDownloadURLCache = StorageDownloadURLCache.shared
        self.chatVideoDiskCache = OPVideoDiskCache.shared
        self.chatRemoteFileDownloader = URLSessionChatRemoteFileDownloader()
        self.chatVideoAssetLoader = ChatVideoAssetService(
            attachmentImageLoader: attachmentImageLoader,
            storageURLResolver: storageDownloadURLCache
        )
        self.chatVideoThumbnailGenerator = DefaultChatVideoThumbnailGenerator()
        self.chatVideoPlaybackResolver = DefaultChatVideoPlaybackResolver(
            storageURLResolver: storageDownloadURLCache,
            videoDiskCache: chatVideoDiskCache,
            fileDownloader: chatRemoteFileDownloader
        )
        self.photoLibrarySaver = DefaultPhotoLibrarySaver()
        self.mediaProcessor = DefaultMediaProcessingService()
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

    func makeChatOutgoingOutboxUseCase() -> ChatOutgoingOutboxUseCaseProtocol {
        chatOutgoingOutboxUseCase
    }

    func makeAttachmentImageLoader() -> ChatAttachmentImageLoading {
        attachmentImageLoader
    }

    func makeChatVideoAssetLoader() -> ChatVideoAssetLoading {
        chatVideoAssetLoader
    }

    func makeChatVideoThumbnailGenerator() -> ChatVideoThumbnailGenerating {
        chatVideoThumbnailGenerator
    }

    func makeStorageURLResolver() -> ChatStorageURLResolving {
        storageDownloadURLCache
    }

    func makeChatVideoPlaybackResolver() -> ChatVideoPlaybackResolving {
        chatVideoPlaybackResolver
    }

    func makePhotoLibrarySaver() -> PhotoLibrarySaving {
        photoLibrarySaver
    }

    func makeMediaProcessor() -> MediaProcessingServiceProtocol {
        mediaProcessor
    }

    func makeAvatarImageManager() -> ChatAvatarImageManaging {
        provider.avatarImageManager
    }

    func makeProfileSyncManager() -> ChatProfileSyncManaging {
        provider.profileSyncManager
    }
}
