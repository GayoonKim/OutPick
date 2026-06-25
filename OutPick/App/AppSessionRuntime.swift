//
//  AppSessionRuntime.swift
//  OutPick
//
//  Created by Codex on 6/24/26.
//

import Foundation

@MainActor
protocol JoinedRoomsSessionRuntimeHandling: AnyObject {
    func replaceJoinedRooms(_ roomIDs: Set<String>)
    func addJoinedRoom(_ roomID: String)
    func removeJoinedRoom(_ roomID: String)
    func clearJoinedRooms()
}

@MainActor
final class AppSessionRuntime {
    private let realtimeSocketService: RealtimeSocketService
    private let currentUserProvider: CurrentUserProviding
    private let presenceManager: PresenceManager
    private let bannerManager: BannerManager

    private var runtimeJoinedRooms = Set<String>()
    private var sessionGeneration = 0

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
        joinedRoomsStore: JoinedRoomsSessionStoring,
        brandAdminSessionStore: BrandAdminSessionStore
    ) async {
        sessionGeneration += 1
        let generation = sessionGeneration
        let identity = SocketSessionIdentity.current(currentUserProvider: currentUserProvider)

        await connectSocketWithRetry(identity: identity, generation: generation)
        guard generation == sessionGeneration else { return }

        syncJoinedRooms(joinedRoomsStore.joined)

        await presenceManager.startAuthenticatedSession()
    }

    private func connectSocketWithRetry(identity: SocketSessionIdentity, generation: Int) async {
        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            guard generation == sessionGeneration else { return }
            do {
                try await realtimeSocketService.connect(identity: identity)
                return
            } catch {
                print("RealtimeSocketService connect 실패(\(attempt)/\(maxAttempts)): \(error.localizedDescription)")
                guard attempt < maxAttempts else { return }
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
            }
        }
    }

    func stopAuthenticatedSession() async {
        sessionGeneration += 1
        let generation = sessionGeneration
        runtimeJoinedRooms.removeAll()
        bannerManager.stopAll()
        await presenceManager.handleLogout()
        guard generation == sessionGeneration else { return }
        await realtimeSocketService.disconnect()
        await realtimeSocketService.resetMembership()
    }

    func handleSceneDidBecomeActive() async {
        await presenceManager.handleAppDidBecomeActive()
    }

    func handleSceneWillResignActive() async {
        await presenceManager.handleAppWillResignActive()
    }

    func handleSceneDidEnterBackground() async {
        await presenceManager.handleAppDidEnterBackground()
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

extension AppSessionRuntime: JoinedRoomsSessionRuntimeHandling {
    func replaceJoinedRooms(_ roomIDs: Set<String>) {
        syncJoinedRooms(roomIDs)
    }

    func addJoinedRoom(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        syncJoinedRooms(runtimeJoinedRooms.union([roomID]))
    }

    func removeJoinedRoom(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        syncJoinedRooms(runtimeJoinedRooms.subtracting([roomID]))
    }

    func clearJoinedRooms() {
        syncJoinedRooms([])
    }
}
