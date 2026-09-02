import Foundation
import Combine
import UIKit

enum ChatRoomRoleSessionSource: Equatable, Sendable {
    case none
    case cache
    case server
    case mutation
}

struct ChatRoomRoleSessionState: Equatable, Sendable {
    let roomID: String
    var status: ChatRoomAccessStatus
    var role: ChatRoomMemberRole?
    var source: ChatRoomRoleSessionSource
    var isObserving: Bool

    var isManagementEnabled: Bool {
        guard status == .member, isObserving else { return false }
        guard source == .server || source == .mutation else { return false }
        return role == .owner || role == .moderator
    }
}

@MainActor
final class ChatRoomRoleSession {
    @Published private(set) var state: ChatRoomRoleSessionState

    private let userID: String
    private let observeUseCase: ObserveChatRoomRoleUseCaseProtocol
    private let notificationCenter: NotificationCenter
    private var observation: ChatRoomRoleObservationCancelling?
    private var observationGeneration: UUID?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var isStarted = false
    private var isForeground = true

    init(
        roomID: String,
        userID: String,
        cachedRole: ChatRoomMemberRole?,
        observeUseCase: ObserveChatRoomRoleUseCaseProtocol,
        notificationCenter: NotificationCenter = .default
    ) {
        self.userID = userID
        self.observeUseCase = observeUseCase
        self.notificationCenter = notificationCenter
        self.state = ChatRoomRoleSessionState(
            roomID: roomID,
            status: cachedRole == nil ? .joinable : .member,
            role: cachedRole,
            source: cachedRole == nil ? .none : .cache,
            isObserving: false
        )
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        bindLifecycle()
        startObservationIfNeeded()
    }

    func stop() {
        isStarted = false
        stopObservation()
        lifecycleObservers.forEach(notificationCenter.removeObserver)
        lifecycleObservers.removeAll()
    }

    func applyConfirmedCurrentRole(_ role: ChatRoomMemberRole?) {
        state.status = role == nil ? .joinable : .member
        state.role = role
        state.source = .mutation
        state.isObserving = isForeground && observation != nil
    }

    private func bindLifecycle() {
        guard lifecycleObservers.isEmpty else { return }
        let background = notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isForeground = false
                self?.stopObservation()
            }
        }
        let foreground = notificationCenter.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isForeground = true
                self?.startObservationIfNeeded()
            }
        }
        lifecycleObservers = [background, foreground]
    }

    private func startObservationIfNeeded() {
        guard isStarted, isForeground, observation == nil else { return }
        let normalizedRoomID = state.roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRoomID.isEmpty,
              !normalizedRoomID.contains("/"),
              !normalizedUserID.isEmpty,
              !normalizedUserID.contains("/") else {
            state.isObserving = false
            return
        }
        state.isObserving = true
        let generation = UUID()
        observationGeneration = generation
        observation = observeUseCase.observe(
            roomID: state.roomID,
            userID: userID,
            onUpdate: { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.isStarted, self.isForeground,
                          self.observationGeneration == generation else { return }
                    self.apply(snapshot)
                }
            },
            onError: { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.observationGeneration == generation else { return }
                    self.state.isObserving = false
                }
            }
        )
    }

    private func stopObservation() {
        observationGeneration = nil
        observation?.cancel()
        observation = nil
        state.isObserving = false
        state.source = state.role == nil ? .none : .cache
    }

    private func apply(_ snapshot: ChatRoomRoleSnapshot) {
        guard snapshot.roomID == state.roomID else { return }
        state.status = snapshot.status
        if snapshot.status == .member {
            state.role = snapshot.role ?? state.role ?? .member
        } else {
            state.role = nil
        }
        state.source = snapshot.source == .cache ? .cache : .server
        state.isObserving = true
    }

    deinit {
        observation?.cancel()
        lifecycleObservers.forEach(notificationCenter.removeObserver)
    }
}
