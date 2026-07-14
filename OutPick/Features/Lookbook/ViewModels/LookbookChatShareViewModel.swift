//
//  LookbookChatShareViewModel.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import Foundation

@MainActor
final class LookbookChatShareViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case empty
        case failed(String)
    }

    struct Completion: Equatable, Identifiable {
        let roomID: String
        let roomName: String
        let messageID: String

        var id: String { "\(roomID):\(messageID)" }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var sharedContent: LookbookSharedContent?
    @Published private(set) var rooms: [ChatRoom] = []
    @Published private(set) var isSending: Bool = false
    @Published private(set) var sendErrorMessage: String?
    @Published private(set) var completion: Completion?
    @Published var selectedRoomID: String?

    private let target: LookbookShareTarget
    private let makeSharedContentUseCase: any MakeLookbookSharedContentUseCaseProtocol
    private let loadRoomsUseCase: any LoadShareableJoinedRoomsUseCaseProtocol
    private let shareUseCase: any ShareLookbookContentToChatUseCaseProtocol
    private var didLoad = false

    init(
        target: LookbookShareTarget,
        makeSharedContentUseCase: any MakeLookbookSharedContentUseCaseProtocol,
        loadRoomsUseCase: any LoadShareableJoinedRoomsUseCaseProtocol,
        shareUseCase: any ShareLookbookContentToChatUseCaseProtocol
    ) {
        self.target = target
        self.makeSharedContentUseCase = makeSharedContentUseCase
        self.loadRoomsUseCase = loadRoomsUseCase
        self.shareUseCase = shareUseCase
    }

    var selectedRoom: ChatRoom? {
        guard let selectedRoomID else { return nil }
        return rooms.first { $0.id == selectedRoomID }
    }

    var canSend: Bool {
        selectedRoom != nil && sharedContent != nil && isSending == false
    }

    func loadIfNeeded() async {
        guard didLoad == false else { return }
        didLoad = true
        phase = .loading
        sendErrorMessage = nil

        do {
            async let contentTask = makeSharedContentUseCase.execute(target: target)
            async let roomsTask = loadRoomsUseCase.execute(limit: 50)
            let (content, loadedRooms) = try await (contentTask, roomsTask)
            sharedContent = content
            rooms = loadedRooms
            selectedRoomID = nil
            phase = loadedRooms.isEmpty ? .empty : .ready
        } catch {
            phase = .failed("공유할 채팅방을 준비하지 못했어요.")
        }
    }

    func retryLoad() async {
        didLoad = false
        rooms = []
        selectedRoomID = nil
        sharedContent = nil
        completion = nil
        await loadIfNeeded()
    }

    func send() async {
        guard let sharedContent, let selectedRoom else { return }
        isSending = true
        sendErrorMessage = nil
        completion = nil
        defer { isSending = false }

        do {
            let result = try await shareUseCase.execute(
                sharedContent: sharedContent,
                to: selectedRoom
            )
            completion = Completion(
                roomID: result.roomID,
                roomName: selectedRoom.roomName,
                messageID: result.messageID
            )
        } catch {
            sendErrorMessage = "공유하지 못했어요."
        }
    }
}
