//
//  ChatRoomRealtimeUseCase.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import Foundation

protocol ChatRoomRealtimeUseCaseProtocol {
    func openMessageStream(
        roomID: String,
        baselineSeq: Int64
    ) async throws -> ChatRoomRealtimeSession
}

final class ChatRoomRealtimeUseCase: ChatRoomRealtimeUseCaseProtocol {
    private let repository: ChatRoomRealtimeRepositoryProtocol

    init(repository: ChatRoomRealtimeRepositoryProtocol = SocketChatRoomRealtimeRepository()) {
        self.repository = repository
    }

    func openMessageStream(
        roomID: String,
        baselineSeq: Int64
    ) async throws -> ChatRoomRealtimeSession {
        try await repository.openMessageStream(
            roomID: roomID,
            baselineSeq: baselineSeq
        )
    }
}

@MainActor
final class ChatRoomRealtimeSubscription {
    typealias OpenSession = () async throws -> ChatRoomRealtimeSession
    typealias MessageHandler = (ChatMessage) async -> Void
    typealias DeletionHandler = (ChatDeletionSocketEvent) async -> Void
    typealias FailureHandler = (Error) -> Void
    typealias FinishHandler = (ChatRoomRealtimeSubscription) -> Void

    let roomID: String

    private let openSession: OpenSession
    private let onMessage: MessageHandler
    private let onDeletion: DeletionHandler
    private let onFailure: FailureHandler
    private let onFinish: FinishHandler

    private var task: Task<Void, Never>?
    private var session: ChatRoomRealtimeSession?
    private var isStopped = true

    init(
        roomID: String,
        openSession: @escaping OpenSession,
        onMessage: @escaping MessageHandler,
        onDeletion: @escaping DeletionHandler = { _ in },
        onFailure: @escaping FailureHandler = { _ in },
        onFinish: @escaping FinishHandler = { _ in }
    ) {
        self.roomID = roomID
        self.openSession = openSession
        self.onMessage = onMessage
        self.onDeletion = onDeletion
        self.onFailure = onFailure
        self.onFinish = onFinish
    }

    deinit {
        task?.cancel()
        if let session {
            Task {
                await session.close()
            }
        }
    }

    func start() {
        guard task == nil else { return }

        isStopped = false
        task = Task { [weak self] in
            await self?.consumeMessages()
        }
    }

    func stop() {
        isStopped = true

        let session = session
        self.session = nil
        task?.cancel()
        task = nil

        guard let session else { return }
        Task {
            await session.close()
        }
    }

    private func consumeMessages() async {
        do {
            let openedSession = try await openSession()

            if Task.isCancelled || isStopped {
                await openedSession.close()
                return
            }

            session = openedSession

            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    guard let self else { return }
                    for await message in openedSession.messages {
                        if Task.isCancelled { break }
                        await self.onMessage(message)
                    }
                }
                group.addTask { [weak self] in
                    guard let self else { return }
                    for await event in openedSession.deletionEvents {
                        if Task.isCancelled { break }
                        await self.onDeletion(event)
                    }
                }
                await group.waitForAll()
            }

            await openedSession.close()
        } catch {
            if !Task.isCancelled && !isStopped {
                onFailure(error)
            }
        }

        guard !isStopped else { return }
        session = nil
        task = nil
        onFinish(self)
    }
}
