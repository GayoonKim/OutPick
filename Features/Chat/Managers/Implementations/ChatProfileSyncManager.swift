//
//  ChatProfileSyncManager.swift
//  OutPick
//
//  Created by Codex on 3/17/26.
//

import Foundation
import Combine

final class ChatProfileSyncManager: ChatProfileSyncManaging {
    private struct ScopeState {
        var roomID: String
        var recency: [String: Date]
        var watchedEmails: Set<String>
    }

    private let userProfileRepository: UserProfileRepositoryProtocol
    private let grdbManager: GRDBManager
    private let maxWatchedEmailsPerScope: Int

    private var scopeStates: [UUID: ScopeState] = [:]
    private var scopeSubjects: [UUID: PassthroughSubject<Set<String>, Never>] = [:]

    private var emailRefCounts: [String: Int] = [:]
    private var emailToScopes: [String: Set<UUID>] = [:]
    private var emailSubscriptions: [String: AnyCancellable] = [:]
    private var cachedProfiles: [String: LocalUser] = [:]

    init(
        userProfileRepository: UserProfileRepositoryProtocol = FirebaseRepositoryProvider.shared.userProfileRepository,
        grdbManager: GRDBManager = .shared,
        maxWatchedEmailsPerScope: Int = 20
    ) {
        self.userProfileRepository = userProfileRepository
        self.grdbManager = grdbManager
        self.maxWatchedEmailsPerScope = max(1, maxWatchedEmailsPerScope)
    }

    func activateScope(_ scopeID: UUID, roomID: String, initialMessages: [ChatMessage]) {
        let existing = scopeStates[scopeID]
        scopeStates[scopeID] = ScopeState(
            roomID: roomID,
            recency: [:],
            watchedEmails: existing?.watchedEmails ?? []
        )
        ingestMessages(initialMessages, into: scopeID)
    }

    func ingestMessages(_ messages: [ChatMessage], into scopeID: UUID) {
        guard var state = scopeStates[scopeID] else { return }

        for message in messages {
            let email = normalizedEmail(message.senderID)
            guard !email.isEmpty else { continue }
            let sentAt = message.sentAt ?? Date()
            let current = state.recency[email] ?? .distantPast
            if sentAt >= current {
                state.recency[email] = sentAt
            }
        }

        let oldWatched = state.watchedEmails
        let newWatched = Set(
            state.recency
                .sorted { lhs, rhs in lhs.value > rhs.value }
                .prefix(maxWatchedEmailsPerScope)
                .map(\.key)
        )

        state.watchedEmails = newWatched
        scopeStates[scopeID] = state

        reconcileScope(scopeID, oldWatched: oldWatched, newWatched: newWatched)
    }

    func changedSenderIDsPublisher(scopeID: UUID) -> AnyPublisher<Set<String>, Never> {
        let subject = scopeSubjects[scopeID] ?? {
            let subject = PassthroughSubject<Set<String>, Never>()
            scopeSubjects[scopeID] = subject
            return subject
        }()
        return subject.eraseToAnyPublisher()
    }

    func profile(for email: String) -> LocalUser? {
        let email = normalizedEmail(email)
        guard !email.isEmpty else { return nil }

        if let cached = cachedProfiles[email] {
            return cached
        }

        if let local = try? grdbManager.fetchLocalUser(email: email) {
            cachedProfiles[email] = local
            return local
        }

        return nil
    }

    func deactivateScope(_ scopeID: UUID) {
        guard let state = scopeStates.removeValue(forKey: scopeID) else { return }

        reconcileScope(scopeID, oldWatched: state.watchedEmails, newWatched: [])

        scopeSubjects[scopeID]?.send(completion: .finished)
        scopeSubjects.removeValue(forKey: scopeID)
    }

    private func reconcileScope(_ scopeID: UUID, oldWatched: Set<String>, newWatched: Set<String>) {
        let removed = oldWatched.subtracting(newWatched)
        let added = newWatched.subtracting(oldWatched)

        for email in removed {
            removeScope(scopeID, from: email)
        }

        for email in added {
            addScope(scopeID, to: email)
        }
    }

    private func addScope(_ scopeID: UUID, to email: String) {
        emailToScopes[email, default: []].insert(scopeID)
        emailRefCounts[email, default: 0] += 1

        if emailSubscriptions[email] == nil {
            startListening(email: email)
        }
    }

    private func removeScope(_ scopeID: UUID, from email: String) {
        if var scopes = emailToScopes[email] {
            scopes.remove(scopeID)
            if scopes.isEmpty {
                emailToScopes.removeValue(forKey: email)
            } else {
                emailToScopes[email] = scopes
            }
        }

        guard let currentRefCount = emailRefCounts[email] else { return }
        let nextRefCount = currentRefCount - 1

        if nextRefCount <= 0 {
            emailRefCounts.removeValue(forKey: email)
            emailSubscriptions[email]?.cancel()
            emailSubscriptions.removeValue(forKey: email)
            userProfileRepository.stopListenUserProfile(email: email)
        } else {
            emailRefCounts[email] = nextRefCount
        }
    }

    private func startListening(email: String) {
        let cancellable = userProfileRepository
            .userProfilePublisher(email: email)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("⚠️ ChatProfileSyncManager profile publisher error:", error)
                    }
                },
                receiveValue: { [weak self] profile in
                    self?.handleProfileUpdate(profile, email: email)
                }
            )

        emailSubscriptions[email] = cancellable
    }

    private func handleProfileUpdate(_ profile: UserProfile, email: String) {
        let local = LocalUser(
            email: email,
            nickname: profile.nickname ?? "",
            profileImagePath: profile.thumbPath
        )

        cachedProfiles[email] = local

        do {
            _ = try grdbManager.upsertLocalUser(
                email: email,
                nickname: local.nickname,
                profileImagePath: local.profileImagePath
            )
        } catch {
            print("⚠️ ChatProfileSyncManager local profile upsert failed:", error)
        }

        let scopes = emailToScopes[email] ?? []
        guard !scopes.isEmpty else { return }

        for scopeID in scopes {
            scopeSubjects[scopeID]?.send([email])
        }
    }

    private func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
