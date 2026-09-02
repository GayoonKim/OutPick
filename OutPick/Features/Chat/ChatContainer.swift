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
    let persistence: ChatPersistenceProvider
    let firebaseRepositories: FirebaseRepositoryProviding
    let roomRepository: FirebaseChatRoomRepositoryProtocol
    let userProfileRepository: UserProfileRepositoryProtocol
    let publicProfileRepository: UserPublicProfileRepositoryProtocol
    let joinedRoomsStore: JoinedRoomsSessionStoring
    let joinedRoomsRuntime: JoinedRoomsSessionRuntimeHandling
    let roomReadStateStore: ChatRoomReadStateStore
    let currentUserProvider: CurrentUserProviding
    let realtimeSocketService: RealtimeSocketService
    let userBlockVisibilityStore: any UserBlockVisibilityChecking
    let featureGate: any AppFeatureGateChecking

    private let managers: ChatManagerProvider
    private let avatarImageManager: AvatarImageManaging
    private let roomListUseCase: RoomListUseCaseProtocol
    private let joinedRoomsUseCase: JoinedRoomsUseCaseProtocol
    private let chatVisibleUnreadUseCase: any ChatVisibleUnreadUseCaseProtocol
    private let roomSearchUseCase: RoomSearchUseCaseProtocol
    private let chatRoomMessageUseCase: ChatRoomMessageUseCaseProtocol
    private let chatMessageSendingRepository: ChatMessageSendingRepositoryProtocol
    private let chatMediaMessageSendingRepository: ChatMediaMessageSendingRepositoryProtocol
    private let chatRoomRealtimeUseCase: ChatRoomRealtimeUseCaseProtocol
    private let chatRoomRuntimeUseCase: ChatRoomRuntimeUseCaseProtocol
    private let chatInitialLoadUseCase: ChatInitialLoadUseCaseProtocol
    private let chatDeletionSyncUseCase: ChatDeletionSyncUseCaseProtocol
    private let chatRoomSearchUseCase: ChatRoomSearchUseCaseProtocol
    private let chatRoomLifecycleUseCase: ChatRoomLifecycleUseCaseProtocol
    private let chatRoomExitUseCase: ChatRoomExitUseCaseProtocol
    let roomClosureAcknowledgementUseCase: ChatRoomClosureAcknowledging
    private let moderationLifecycleRepository: ChatModerationLifecycleRepositoryProtocol
    private let roleMutationRepository: ChatRoomRoleMutationRepositoryProtocol
    private let observeRoomRoleUseCase: ObserveChatRoomRoleUseCaseProtocol
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
    private let blockUserUseCase: any BlockUserUseCaseProtocol
    private let submitModerationReportUseCase: any SubmitChatModerationReportUseCaseProtocol

    init(
        persistence: ChatPersistenceProvider,
        roomRepository: FirebaseChatRoomRepositoryProtocol? = nil,
        userProfileRepository: UserProfileRepositoryProtocol? = nil,
        publicProfileRepository: UserPublicProfileRepositoryProtocol,
        joinedRoomsStore: JoinedRoomsSessionStoring,
        joinedRoomsRuntime: JoinedRoomsSessionRuntimeHandling,
        currentUserProvider: CurrentUserProviding,
        realtimeSocketService: RealtimeSocketService,
        avatarImageManager: AvatarImageManaging,
        featureGate: any AppFeatureGateChecking,
        userBlockVisibilityStore: any UserBlockVisibilityChecking = UserBlockVisibilityStore(),
        userBlockRepository: any UserBlockRepositoryProtocol = CloudFunctionsUserBlockRepository(),
        userBlockSessionSynchronizer: (any UserBlockSessionSynchronizing)? = nil,
        roomReadStateStore: ChatRoomReadStateStore? = nil,
        announcementRepository: FirebaseAnnouncementRepositoryProtocol? = nil,
        repositories: FirebaseRepositoryProviding = FirebaseRepositoryProvider.shared
    ) {
        self.persistence = persistence
        self.firebaseRepositories = repositories
        let attachmentImageLoader = ChatAttachmentImageService(
            imageStorageRepository: repositories.imageStorageRepository
        )
        self.attachmentImageLoader = attachmentImageLoader
        let deletionSyncUseCase = ChatDeletionSyncUseCase(
            repository: FirebaseChatDeletionSyncRepository(
                messageRepository: repositories.messageRepository
            ),
            persistence: persistence.deletionSyncStore,
            mediaCleaner: DefaultChatDeletionMediaCleaner(
                imageLoader: attachmentImageLoader,
                videoDiskCache: OPVideoDiskCache.shared,
                storageURLResolver: StorageDownloadURLCache.shared
            )
        )
        self.chatDeletionSyncUseCase = deletionSyncUseCase
        let moderationLifecycleRepository = CloudFunctionsChatModerationLifecycleRepository(
            currentUserID: { currentUserProvider.canonicalUserID }
        )
        self.moderationLifecycleRepository = moderationLifecycleRepository
        self.roleMutationRepository = moderationLifecycleRepository
        self.observeRoomRoleUseCase = ObserveChatRoomRoleUseCase(
            repository: FirestoreChatRoomRoleRepository()
        )
        let managers = ChatManagerProvider(
            repositories: repositories,
            publicProfileRepository: publicProfileRepository,
            persistence: persistence,
            moderationLifecycleRepository: moderationLifecycleRepository,
            deletionSanitizer: deletionSyncUseCase,
            currentAccountID: { currentUserProvider.canonicalUserID }
        )
        self.managers = managers
        self.avatarImageManager = avatarImageManager
        self.roomRepository = roomRepository ?? repositories.chatRoomRepository
        self.userProfileRepository = userProfileRepository ?? repositories.userProfileRepository
        self.publicProfileRepository = publicProfileRepository
        self.joinedRoomsStore = joinedRoomsStore
        self.joinedRoomsRuntime = joinedRoomsRuntime
        self.currentUserProvider = currentUserProvider
        self.realtimeSocketService = realtimeSocketService
        self.featureGate = featureGate
        self.userBlockVisibilityStore = userBlockVisibilityStore
        self.blockUserUseCase = BlockUserUseCase(
            repository: userBlockRepository,
            sessionSynchronizer: userBlockSessionSynchronizer
        )
        self.submitModerationReportUseCase = SubmitChatModerationReportUseCase(
            repository: CloudFunctionsChatModerationReportingRepository()
        )
        let resolvedRoomReadStateStore = roomReadStateStore ?? ChatRoomReadStateStore()
        self.roomReadStateStore = resolvedRoomReadStateStore
        BannerManager.shared.configure(
            roomReadStateStore: resolvedRoomReadStateStore,
            roomRepository: self.roomRepository
        )
        let announcementRepository = announcementRepository ?? repositories.announcementRepository
        self.roomListUseCase = RoomListUseCase(
            roomRepository: self.roomRepository,
            profileSyncManager: managers.profileSyncManager
        )
        let roomLocalExitCleaner = DefaultChatRoomLocalExitCleaner(
            localDataStore: persistence.roomLocalDataStore,
            joinedRoomsStore: joinedRoomsStore,
            joinedRoomsRuntime: joinedRoomsRuntime,
            roomRepository: self.roomRepository,
            currentUserProvider: currentUserProvider
        )
        self.chatRoomExitUseCase = ChatRoomExitUseCase(
            repository: DefaultChatRoomExitRepository(
                socket: realtimeSocketService,
                moderationLifecycleRepository: moderationLifecycleRepository,
                roleMutationRepository: moderationLifecycleRepository,
                currentUserID: { currentUserProvider.canonicalUserID }
            ),
            localCleaner: roomLocalExitCleaner,
            roleMutationRepository: moderationLifecycleRepository
        )
        self.roomClosureAcknowledgementUseCase = ChatRoomClosureAcknowledgementUseCase(
            repository: moderationLifecycleRepository,
            localCleaner: roomLocalExitCleaner
        )
        self.joinedRoomsUseCase = JoinedRoomsUseCase(
            roomRepository: self.roomRepository,
            userProfileRepository: self.userProfileRepository,
            exitUseCase: self.chatRoomExitUseCase
        )
        self.chatVisibleUnreadUseCase = ChatVisibleUnreadUseCase(
            messageRepository: repositories.messageRepository
        )
        self.roomSearchUseCase = RoomSearchUseCase(roomRepository: self.roomRepository)
        self.chatMessageSendingRepository = SocketChatMessageSendingRepository(
            socketManager: realtimeSocketService
        )
        let chatOutgoingOutboxUseCase = ChatOutgoingOutboxUseCase(
            outboxPersistence: persistence.outboxStore,
            messagePersistence: persistence.messageStore,
            imageStorageRepository: repositories.imageStorageRepository,
            videoStorageRepository: repositories.videoStorageRepository
        )
        self.chatOutgoingOutboxUseCase = chatOutgoingOutboxUseCase
        self.chatRoomMessageUseCase = ChatRoomMessageUseCase(
            messageManager: managers.messageManager,
            sendingRepository: chatMessageSendingRepository,
            serverConfirmedMessageReconciler: chatOutgoingOutboxUseCase,
            currentUserProvider: {
                ChatMessageSenderSnapshot(
                    senderUID: currentUserProvider.canonicalUserID,
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
            transientLocalDataCleaner: DefaultChatRoomTransientLocalDataCleaner(
                localDataStore: persistence.roomLocalDataStore
            )
        )
        self.chatInitialLoadUseCase = DefaultChatInitialLoadUseCase(
            messageManager: managers.messageManager,
            userProfileRepository: self.userProfileRepository,
            chatRoomRepository: self.roomRepository,
            networkStatusProvider: managers.networkStatusProvider,
            deletionSyncUseCase: deletionSyncUseCase,
            serverConfirmedMessageReconciler: chatOutgoingOutboxUseCase,
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
                    senderNickname: currentUserProvider.nickname ?? "",
                    senderAvatarPath: currentUserProvider.avatarPath
                )
            }
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
        Task { await deletionSyncUseCase.resumePendingCleanup() }
    }

    func makeRoomListsViewModel() -> RoomListsViewModel {
        RoomListsViewModel(
            useCase: roomListUseCase,
            roomReadStateStore: roomReadStateStore
        )
    }

    func makeJoinedRoomsViewModel() -> JoinedRoomsViewModel {
        JoinedRoomsViewModel(
            useCase: joinedRoomsUseCase,
            roomReadStateStore: roomReadStateStore,
            joinedRoomsStore: joinedRoomsStore,
            moderationLifecycleRepository: moderationLifecycleRepository,
            closureAcknowledgementUseCase: roomClosureAcknowledgementUseCase,
            userBlockVisibilityStore: userBlockVisibilityStore,
            visibleUnreadUseCase: chatVisibleUnreadUseCase
        )
    }

    func makeRoomSearchViewModel() -> RoomSearchViewModel {
        RoomSearchViewModel(useCase: roomSearchUseCase)
    }

    func makeChatRoomViewModel(room: ChatRoom) -> ChatRoomViewModel {
        let currentUserID = currentUserProvider.canonicalUserID
        let cachedRole: ChatRoomMemberRole? = room.ownerUID == currentUserID
            ? .owner
            : (joinedRoomsStore.contains(room.id) ? .member : nil)
        let roleSession = ChatRoomRoleSession(
            roomID: room.id,
            userID: currentUserID,
            cachedRole: cachedRole,
            observeUseCase: observeRoomRoleUseCase
        )
        return ChatRoomViewModel(
            room: room,
            initialLoadUseCase: chatInitialLoadUseCase,
            messageUseCase: chatRoomMessageUseCase,
            searchUseCase: chatRoomSearchUseCase,
            lifecycleUseCase: chatRoomLifecycleUseCase,
            realtimeUseCase: chatRoomRealtimeUseCase,
            runtimeUseCase: chatRoomRuntimeUseCase,
            currentUserProvider: currentUserProvider,
            joinedRoomsStore: joinedRoomsStore,
            roomReadStateStore: roomReadStateStore,
            userBlockVisibilityStore: userBlockVisibilityStore,
            blockUserUseCase: blockUserUseCase,
            memberModerationUseCase: makeChatRoomMemberModerationUseCase(),
            deletionSyncUseCase: chatDeletionSyncUseCase,
            roomRoleSession: roleSession,
            roomRoleUseCase: observeRoomRoleUseCase
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

    func makeChatRoomMemberModerationUseCase() -> ChatRoomMemberModerationUseCaseProtocol {
        ChatRoomMemberModerationUseCase(repository: moderationLifecycleRepository)
    }

    func makeManageChatRoomRoleUseCase() -> ManageChatRoomRoleUseCaseProtocol {
        ManageChatRoomRoleUseCase(repository: roleMutationRepository)
    }

    func makeChatRoomBannedUsersViewModel(roomID: String) -> ChatRoomBannedUsersViewModel {
        ChatRoomBannedUsersViewModel(
            roomID: roomID,
            useCase: makeChatRoomMemberModerationUseCase()
        )
    }

    func makeBlockUserUseCase() -> any BlockUserUseCaseProtocol {
        blockUserUseCase
    }

    func makeMessageReportViewModel(
        roomID: String,
        messageID: String,
        isMediaContext: Bool
    ) -> ChatMessageReportViewModel {
        ChatMessageReportViewModel(
            roomID: roomID,
            messageID: messageID,
            isMediaContext: isMediaContext,
            useCase: submitModerationReportUseCase
        )
    }

    func makeChatMediaUploadUseCase() -> ChatMediaUploadUseCaseProtocol {
        chatMediaUploadUseCase
    }

    func makeChatOutgoingOutboxUseCase() -> ChatOutgoingOutboxUseCaseProtocol {
        chatOutgoingOutboxUseCase
    }

    func makeLocalParticipantsRepository() -> ChatRoomParticipantsRepositoryProtocol {
        persistence.profileStore
    }

    func makeLocalMediaRepository() -> ChatRoomMediaIndexRepositoryProtocol {
        persistence.mediaStore
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
