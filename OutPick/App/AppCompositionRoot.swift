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
        let userProfileRepository: UserProfileRepositoryProtocol = UserProfileRepository(db: db)
        let currentUserSessionStore = CurrentUserSessionStore()
        let currentUserProvider = LoginManagerCurrentUserProvider(
            sessionStore: currentUserSessionStore
        )
        let cloudFunctionsTransport = FirebaseCloudFunctionsTransport()
        let socialAuthRepository = DefaultSocialAuthRepository.live(
            transport: cloudFunctionsTransport
        )
        let lookbookProvider = LookbookRepositoryProvider.live(
            transport: cloudFunctionsTransport
        )
        let realtimeSocketService = RealtimeSocketService.shared
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

        return AppCoordinator(
            window: window,
            lookbookProvider: lookbookProvider,
            userProfileRepository: userProfileRepository,
            joinedRoomsStore: joinedRoomsStore,
            brandAdminSessionStore: brandAdminSessionStore,
            socialAuthRepository: socialAuthRepository,
            currentUserSessionStore: currentUserSessionStore,
            currentUserProvider: currentUserProvider,
            realtimeSocketService: realtimeSocketService,
            avatarImageManager: avatarImageManager,
            appSessionRuntime: appSessionRuntime,
            chatPersistence: chatPersistence
        )
    }
}
