//
//  AppSessionRuntime.swift
//  OutPick
//
//  Created by Codex on 6/24/26.
//

import Combine
import Foundation

@MainActor
final class AppSessionRuntime {
    private let realtimeSocketService: RealtimeSocketService
    private let currentUserProvider: CurrentUserProviding
    private let presenceManager: PresenceManager
    private let bannerManager: BannerManager

    private var joinedRoomsCancellable: AnyCancellable?
    private var runtimeJoinedRooms = Set<String>()

    init(
        realtimeSocketService: RealtimeSocketService = .shared,
        currentUserProvider: CurrentUserProviding = LoginManagerCurrentUserProvider(),
        presenceManager: PresenceManager? = nil,
        bannerManager: BannerManager? = nil
    ) {
        self.realtimeSocketService = realtimeSocketService
        self.currentUserProvider = currentUserProvider
        self.presenceManager = presenceManager ?? .shared
        self.bannerManager = bannerManager ?? .shared
    }

    func startAuthenticatedSession(
        joinedRoomsStore: JoinedRoomsStore,
        brandAdminSessionStore: BrandAdminSessionStore
    ) async {
        bindJoinedRoomsRuntimeIfNeeded(joinedRoomsStore: joinedRoomsStore)
        syncJoinedRooms(joinedRoomsStore.joined)

        let identity = SocketSessionIdentity.current(currentUserProvider: currentUserProvider)
        Task {
            do {
                try await realtimeSocketService.connect(identity: identity)
            } catch {
                print("RealtimeSocketService connect 실패: \(error.localizedDescription)")
            }
        }

        await presenceManager.startAuthenticatedSession()
    }

    func stopAuthenticatedSession() async {
        joinedRoomsCancellable?.cancel()
        joinedRoomsCancellable = nil
        runtimeJoinedRooms.removeAll()
        bannerManager.stopAll()
        await presenceManager.handleLogout()
        await realtimeSocketService.disconnect()
        await realtimeSocketService.resetMembership()
    }

    private func bindJoinedRoomsRuntimeIfNeeded(joinedRoomsStore: JoinedRoomsStore) {
        guard joinedRoomsCancellable == nil else { return }

        joinedRoomsCancellable = joinedRoomsStore.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] joinedSet in
                guard let self else { return }
                self.syncJoinedRooms(joinedSet)
            }
    }

    private func syncJoinedRooms(_ joinedSet: Set<String>) {
        let toJoin = joinedSet.subtracting(runtimeJoinedRooms)
        let toLeave = runtimeJoinedRooms.subtracting(joinedSet)
        runtimeJoinedRooms = joinedSet

        bannerManager.start(for: Array(joinedSet))

        for roomID in toJoin {
            Task {
                await realtimeSocketService.joinRoom(roomID)
            }
        }

        for roomID in toLeave {
            Task {
                await realtimeSocketService.leaveRoom(roomID)
            }
        }
    }
}
