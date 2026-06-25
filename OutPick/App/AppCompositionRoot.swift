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
    static func makeCoordinator(window: UIWindow) -> AppCoordinator {
        let db = Firestore.firestore()
        let userProfileRepository: UserProfileRepositoryProtocol = UserProfileRepository(db: db)
        let currentUserProvider = LoginManagerCurrentUserProvider()
        let realtimeSocketService = RealtimeSocketService.shared
        let joinedRoomsStore = JoinedRoomsSessionStore()
        let brandAdminSessionStore = BrandAdminSessionStore()
        let appSessionRuntime = AppSessionRuntime(
            realtimeSocketService: realtimeSocketService,
            currentUserProvider: currentUserProvider
        )

        return AppCoordinator(
            window: window,
            userProfileRepository: userProfileRepository,
            joinedRoomsStore: joinedRoomsStore,
            brandAdminSessionStore: brandAdminSessionStore,
            currentUserProvider: currentUserProvider,
            realtimeSocketService: realtimeSocketService,
            appSessionRuntime: appSessionRuntime
        )
    }
}
