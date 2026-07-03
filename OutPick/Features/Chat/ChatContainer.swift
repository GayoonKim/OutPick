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
    let firebaseRepositories: FirebaseRepositoryProviding
    let roomRepository: FirebaseChatRoomRepositoryProtocol
    let userProfileRepository: UserProfileRepositoryProtocol
    let joinedRoomsStore: JoinedRoomsSessionStoring
    let joinedRoomsRuntime: JoinedRoomsSessionRuntimeHandling
    let roomReadStateStore: ChatRoomReadStateStore
    let currentUserProvider: CurrentUserProviding
    let realtimeSocketService: RealtimeSocketService

    private let managers: ChatManagerProvider
    private let avatarImageManager: AvatarImageManaging
    private let roomListUseCase: RoomListUseCaseProtocol
    private let joinedRoomsUseCase: JoinedRoomsUseCaseProtocol
    private let roomSearchUseCase: RoomSearchUseCaseProtocol
    private let chatRoomMessageUseCase: ChatRoomMessageUseCaseProtocol
    private let chatMessageSendingRepository: ChatMessageSendingRepositoryProtocol
    private let chatMediaMessageSendingRepository: ChatMediaMessageSendingRepositoryProtocol
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
        roomRepository: FirebaseChatRoomRepositoryProtocol? = nil,
        userProfileRepository: UserProfileRepositoryProtocol? = nil,
        joinedRoomsStore: JoinedRoomsSessionStoring,
        joinedRoomsRuntime: JoinedRoomsSessionRuntimeHandling,
        currentUserProvider: CurrentUserProviding,
        realtimeSocketService: RealtimeSocketService,
        avatarImageManager: AvatarImageManaging,
        roomReadStateStore: ChatRoomReadStateStore? = nil,
        announcementRepository: FirebaseAnnouncementRepositoryProtocol? = nil,
        repositories: FirebaseRepositoryProviding = FirebaseRepositoryProvider.shared
    ) {
        self.firebaseRepositories = repositories
        let attachmentImageLoader = ChatAttachmentImageService(
            imageStorageRepository: repositories.imageStorageRepository
        )
        self.attachmentImageLoader = attachmentImageLoader
        let managers = ChatManagerProvider(repositories: repositories)
        self.managers = managers
        self.avatarImageManager = avatarImageManager
        self.roomRepository = roomRepository ?? repositories.chatRoomRepository
        self.userProfileRepository = userProfileRepository ?? repositories.userProfileRepository
        self.joinedRoomsStore = joinedRoomsStore
        self.joinedRoomsRuntime = joinedRoomsRuntime
        self.currentUserProvider = currentUserProvider
        self.realtimeSocketService = realtimeSocketService
        let resolvedRoomReadStateStore = roomReadStateStore ?? ChatRoomReadStateStore()
        self.roomReadStateStore = resolvedRoomReadStateStore
        let announcementRepository = announcementRepository ?? repositories.announcementRepository
        self.roomListUseCase = RoomListUseCase(roomRepository: self.roomRepository)
        self.chatRoomExitUseCase = ChatRoomExitUseCase(
            repository: SocketChatRoomExitRepository(socket: realtimeSocketService),
            localCleaner: DefaultChatRoomLocalExitCleaner(
                joinedRoomsStore: joinedRoomsStore,
                joinedRoomsRuntime: joinedRoomsRuntime,
                roomRepository: self.roomRepository,
                currentUserProvider: currentUserProvider
            )
        )
        self.joinedRoomsUseCase = JoinedRoomsUseCase(
            roomRepository: self.roomRepository,
            userProfileRepository: self.userProfileRepository,
            exitUseCase: self.chatRoomExitUseCase
        )
        self.roomSearchUseCase = RoomSearchUseCase(roomRepository: self.roomRepository)
        self.chatMessageSendingRepository = SocketChatMessageSendingRepository(
            socketManager: realtimeSocketService
        )
        self.chatRoomMessageUseCase = ChatRoomMessageUseCase(
            messageManager: managers.messageManager,
            sendingRepository: chatMessageSendingRepository,
            deletedLastMessageSummaryUpdater: self.roomRepository as? ChatDeletedLastMessageSummaryUpdating,
            currentUserProvider: {
                ChatMessageSenderSnapshot(
                    senderUID: currentUserProvider.canonicalUserID,
                    senderEmail: currentUserProvider.email,
                    senderNickname: currentUserProvider.nickname ?? "",
                    senderAvatarPath: currentUserProvider.avatarPath
                )
            }
        )
        self.chatRoomRealtimeUseCase = ChatRoomRealtimeUseCase(
            repository: SocketChatRoomRealtimeRepository(socketManager: realtimeSocketService)
        )
        self.chatRoomRuntimeUseCase = ChatRoomRuntimeUseCase(
            repository: SocketChatRoomRuntimeRepository(socketObserver: realtimeSocketService),
            visibilityRuntimeManager: DefaultChatRoomVisibilityRuntimeManager(),
            transientLocalDataCleaner: DefaultChatRoomTransientLocalDataCleaner()
        )
        self.chatInitialLoadUseCase = DefaultChatInitialLoadUseCase(
            messageManager: managers.messageManager,
            userProfileRepository: self.userProfileRepository,
            chatRoomRepository: self.roomRepository,
            networkStatusProvider: managers.networkStatusProvider,
            currentUserUIDProvider: { currentUserProvider.canonicalUserID }
        )
        self.chatRoomSearchUseCase = ChatRoomSearchUseCase(searchManager: managers.searchManager)
        self.chatRoomLifecycleUseCase = ChatRoomLifecycleUseCase(
            chatRoomRepository: self.roomRepository,
            userProfileRepository: self.userProfileRepository,
            joinedRoomsStore: joinedRoomsStore,
            joinedRoomsRuntime: joinedRoomsRuntime,
            announcementRepository: announcementRepository,
            realtimeService: realtimeSocketService
        )
        self.chatMediaMessageSendingRepository = SocketChatMediaMessageSendingRepository(
            socketManager: realtimeSocketService
        )
        self.chatMediaUploadUseCase = ChatMediaUploadUseCase(
            imageStorageRepository: repositories.imageStorageRepository,
            videoStorageRepository: repositories.videoStorageRepository,
            sendingRepository: chatMediaMessageSendingRepository,
            attachmentImageLoader: attachmentImageLoader,
            currentUserProvider: {
                ChatMessageSenderSnapshot(
                    senderUID: currentUserProvider.canonicalUserID,
                    senderEmail: currentUserProvider.email,
                    senderNickname: currentUserProvider.nickname ?? "",
                    senderAvatarPath: currentUserProvider.avatarPath
                )
            }
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
        let lookbookChatShareSendingRepository = SocketLookbookChatShareSendingRepository(
            socketManager: realtimeSocketService
        )
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
            joinedRoomsStore: joinedRoomsStore,
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

    func makeAvatarImageManager() -> AvatarImageManaging {
        avatarImageManager
    }

    func makeProfileSyncManager() -> ChatProfileSyncManaging {
        managers.profileSyncManager
    }

    func makeRoomImageManager() -> RoomImageManaging {
        managers.roomImageManager
    }

    func makeNetworkStatusProvider() -> NetworkStatusProviding {
        managers.networkStatusProvider
    }
}
