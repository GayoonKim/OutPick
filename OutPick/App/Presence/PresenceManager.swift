//
//  PresenceManager.swift
//  OutPick
//
//  Created by Codex on 4/10/26.
//

import UIKit

@MainActor
final class PresenceManager {
    static let shared = PresenceManager()

    private let userProfileRepository: UserProfileRepositoryProtocol

    private var visibleRoomID: String?
    private var currentAppState: AppPresenceState = .offline
    private var latestFCMToken: String?
    private var latestPushEnabled = false
    private var lastSyncedSignature: String?

    private init(repositories: FirebaseRepositoryProviding = FirebaseRepositoryProvider.shared) {
        self.userProfileRepository = repositories.userProfileRepository
    }

    func startAuthenticatedSession() async {
        currentAppState = resolvedCurrentAppState()
        await refreshCurrentDeviceState()
    }

    func handleAppDidBecomeActive() async {
        currentAppState = .foreground
        await refreshCurrentDeviceState()
    }

    func handleAppWillResignActive() async {
        currentAppState = .background
        visibleRoomID = nil
        await refreshCurrentDeviceState()
    }

    func handleAppDidEnterBackground() async {
        currentAppState = .background
        visibleRoomID = nil
        await refreshCurrentDeviceState()
    }

    func enterRoom(_ roomID: String) async {
        guard !roomID.isEmpty else { return }
        visibleRoomID = roomID
        await refreshCurrentDeviceState()
    }

    func leaveCurrentRoom() async {
        guard visibleRoomID != nil else { return }
        visibleRoomID = nil
        await refreshCurrentDeviceState()
    }

    func updatePushPermission(granted: Bool, fcmToken: String?) async {
        latestPushEnabled = granted
        latestFCMToken = normalizedOptionalString(fcmToken)
        await refreshCurrentDeviceState()
    }

    func refreshCurrentDeviceState(
        pushEnabledOverride: Bool? = nil,
        fcmTokenOverride: String? = nil
    ) async {
        if let pushEnabledOverride {
            latestPushEnabled = pushEnabledOverride
        }
        if let fcmTokenOverride {
            latestFCMToken = normalizedOptionalString(fcmTokenOverride)
        }

        guard let context = await currentContext() else { return }

        let visibleRoom = currentAppState == .foreground ? visibleRoomID : nil
        let state = PushDeviceState(
            deviceID: UIDevice.persistentDeviceID,
            email: context.email,
            fcmToken: latestFCMToken,
            pushEnabled: latestPushEnabled,
            appState: currentAppState,
            visibleRoomID: visibleRoom,
            socketID: nil
        )

        let signature = [
            context.userDocumentID,
            state.deviceID,
            state.email,
            state.fcmToken ?? "",
            state.pushEnabled ? "1" : "0",
            state.appState.rawValue,
            state.visibleRoomID ?? "",
        ].joined(separator: "|")

        guard signature != lastSyncedSignature else { return }

        do {
            try await userProfileRepository.upsertPushDevice(
                userDocumentID: context.userDocumentID,
                state: state
            )
            lastSyncedSignature = signature
        } catch {
            print("[PresenceManager] sync failed: \(error.localizedDescription)")
        }
    }

    func handleLogout() async {
        guard let context = await currentContext() else {
            resetLocalState()
            return
        }

        let state = PushDeviceState(
            deviceID: UIDevice.persistentDeviceID,
            email: context.email,
            fcmToken: latestFCMToken,
            pushEnabled: false,
            appState: .offline,
            visibleRoomID: nil,
            socketID: nil
        )

        do {
            try await userProfileRepository.upsertPushDevice(
                userDocumentID: context.userDocumentID,
                state: state
            )
        } catch {
            print("[PresenceManager] logout sync failed: \(error.localizedDescription)")
        }

        resetLocalState()
    }

    private func resetLocalState() {
        visibleRoomID = nil
        currentAppState = .offline
        lastSyncedSignature = nil
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resolvedCurrentAppState() -> AppPresenceState {
        switch UIApplication.shared.applicationState {
        case .active:
            return .foreground
        case .background, .inactive:
            return .background
        @unknown default:
            return .background
        }
    }

    private func currentContext() async -> (userDocumentID: String, email: String)? {
        let email = LoginManager.shared.getUserEmail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let userDocumentID: String
        if !LoginManager.shared.getUserDocumentID.isEmpty {
            userDocumentID = LoginManager.shared.getUserDocumentID
        } else {
            guard LoginManager.shared.hasAuthenticatedIdentity else {
                return nil
            }
            do {
                userDocumentID = try await LoginManager.shared.ensureUserDocumentID()
            } catch {
                print("[PresenceManager] failed to resolve user document ID: \(error.localizedDescription)")
                return nil
            }
        }

        guard !userDocumentID.isEmpty else { return nil }
        return (userDocumentID, email)
    }
}
