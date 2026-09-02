//
//  AppCompositionRoot.swift
//  OutPick
//
//  Created by Codex on 6/25/26.
//

import FirebaseFirestore
import UIKit

@MainActor
enum AppCompositionRoot {
    typealias DatabaseFactory = () throws -> AppDatabase

    static func makeCoordinator(
        window: UIWindow,
        makeDatabase: DatabaseFactory = AppDatabase.live
    ) throws -> AppCoordinator {
        let appDatabase: AppDatabase
        do {
            appDatabase = try makeDatabase()
        } catch {
            throw AppBootstrapError.localDatabaseInitializationFailed(underlying: error)
        }

        let db = Firestore.firestore()
        let publicProfileRepository = FirestoreUserPublicProfileRepository(db: db)
        let userProfileRepository: UserProfileRepositoryProtocol = UserProfileRepository(db: db)
        let currentUserSessionStore = CurrentUserSessionStore()
        let currentUserStylePreferenceStore = CurrentUserStylePreferenceStore()
        let currentUserProvider = LoginManagerCurrentUserProvider(
            sessionStore: currentUserSessionStore
        )
        let cloudFunctionsTransport = FirebaseCloudFunctionsTransport()
        let accountRepository = FirestoreCurrentUserAccountRepository(db: db)
        let moderationRepository = CloudFunctionsCurrentUserModerationRepository(
            transport: cloudFunctionsTransport
        )
        let profileMutationRepository = CloudFunctionsProfileMutationRepository(
            transport: cloudFunctionsTransport
        )
        let styleMoodRepository = FirestoreStyleMoodRepository(db: db)
        let loadCurrentUserBootstrapUseCase = LoadCurrentUserBootstrapUseCase(
            moderationRepository: moderationRepository,
            accountRepository: accountRepository,
            publicProfileRepository: publicProfileRepository
        )
        let completeOnboardingUseCase = CompleteOnboardingUseCase(
            mutationRepository: profileMutationRepository,
            avatarUploader: FirebaseProfileAvatarUploader(
                imageRepository: FirebaseRepositoryProvider.shared.imageStorageRepository
            )
        )
        let updatePublicProfileUseCase = UpdatePublicProfileUseCase(
            mutationRepository: profileMutationRepository,
            avatarUploader: FirebaseProfileAvatarUploader(
                imageRepository: FirebaseRepositoryProvider.shared.imageStorageRepository
            )
        )
        let updateStylePreferencesUseCase = UpdateStylePreferencesUseCase(
            mutationRepository: profileMutationRepository
        )
        let checkNicknameAvailabilityUseCase = CheckNicknameAvailabilityUseCase(
            mutationRepository: profileMutationRepository
        )
        let socialAuthRepository = DefaultSocialAuthRepository.live(
            transport: cloudFunctionsTransport
        )
        let accountDeletionRepository = CloudFunctionsAccountDeletionRepository(
            transport: cloudFunctionsTransport
        )
        let accountDeletionReceiptStore = AccountDeletionReceiptStore()
        let accountDeletionLocalDataScrubber = AccountDeletionLocalDataScrubber(
            database: appDatabase
        )
        let requestAccountDeletionUseCase = RequestAccountDeletionUseCase(
            repository: accountDeletionRepository,
            reauthenticator: socialAuthRepository,
            receiptStore: accountDeletionReceiptStore,
            localDataScrubber: accountDeletionLocalDataScrubber
        )
        let cancelAccountDeletionUseCase = CancelAccountDeletionUseCase(
            repository: accountDeletionRepository,
            reauthenticator: socialAuthRepository,
            receiptStore: accountDeletionReceiptStore
        )
        let loadAccountDeletionStatusUseCase = LoadAccountDeletionStatusUseCase(
            repository: accountDeletionRepository,
            receiptStore: accountDeletionReceiptStore
        )
        let userBlockVisibilityStore = UserBlockVisibilityStore()
        let userBlockRepository = CloudFunctionsUserBlockRepository(
            transport: cloudFunctionsTransport,
            db: db
        )
        let userBlockSessionController = UserBlockSessionController(
            repository: userBlockRepository,
            snapshotStore: UserDefaultsUserBlockSnapshotStore(),
            visibilityStore: userBlockVisibilityStore
        )
        let lookbookProvider = LookbookRepositoryProvider.live(
            transport: cloudFunctionsTransport,
            userBlockRepository: userBlockRepository
        )
        let realtimeSocketService = RealtimeSocketService(
            gapRecoveryLoader: FirebaseChatRealtimeGapRecoveryLoader(db: db),
            userBlockVisibilityStore: userBlockVisibilityStore
        )
        BannerManager.shared.configure(
            realtimeSocketService: realtimeSocketService,
            userBlockVisibilityStore: userBlockVisibilityStore
        )
        let joinedRoomsStore = JoinedRoomsSessionStore()
        let brandAdminSessionStore = BrandAdminSessionStore(
            capabilitiesClient: BrandAdminCapabilitiesCloudFunctionsClient(
                transport: cloudFunctionsTransport
            )
        )
        let avatarImageManager = AvatarImageService(
            imageStorageRepository: FirebaseRepositoryProvider.shared.imageStorageRepository
        )
        let appSessionRuntime = AppSessionRuntime(
            realtimeSocketService: realtimeSocketService,
            currentUserProvider: currentUserProvider
        )
        let chatPersistence = ChatPersistenceProvider(database: appDatabase)
        let appFeatureGateStore = AppFeatureGateStore()
        let rolloutDecisionUseCase = LoadAppRolloutDecisionUseCase(
            repository: FirebaseRemoteConfigAppRolloutRepository()
        )

        return AppCoordinator(
            window: window,
            lookbookProvider: lookbookProvider,
            userProfileRepository: userProfileRepository,
            publicProfileRepository: publicProfileRepository,
            loadCurrentUserBootstrapUseCase: loadCurrentUserBootstrapUseCase,
            styleMoodRepository: styleMoodRepository,
            checkNicknameAvailabilityUseCase: checkNicknameAvailabilityUseCase,
            completeOnboardingUseCase: completeOnboardingUseCase,
            updatePublicProfileUseCase: updatePublicProfileUseCase,
            updateStylePreferencesUseCase: updateStylePreferencesUseCase,
            requestAccountDeletionUseCase: requestAccountDeletionUseCase,
            cancelAccountDeletionUseCase: cancelAccountDeletionUseCase,
            loadAccountDeletionStatusUseCase: loadAccountDeletionStatusUseCase,
            accountDeletionLocalDataScrubber: accountDeletionLocalDataScrubber,
            accountRepository: accountRepository,
            joinedRoomsStore: joinedRoomsStore,
            brandAdminSessionStore: brandAdminSessionStore,
            socialAuthRepository: socialAuthRepository,
            currentUserSessionStore: currentUserSessionStore,
            currentUserStylePreferenceStore: currentUserStylePreferenceStore,
            currentUserProvider: currentUserProvider,
            realtimeSocketService: realtimeSocketService,
            avatarImageManager: avatarImageManager,
            appSessionRuntime: appSessionRuntime,
            chatPersistence: chatPersistence,
            rolloutDecisionUseCase: rolloutDecisionUseCase,
            appFeatureGateStore: appFeatureGateStore,
            userBlockVisibilityStore: userBlockVisibilityStore,
            userBlockSessionController: userBlockSessionController,
            userBlockRepository: userBlockRepository
        )
    }
}
