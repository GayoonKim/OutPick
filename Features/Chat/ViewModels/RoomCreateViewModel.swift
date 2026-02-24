//
//  RoomCreateViewModel.swift
//  OutPick
//
//  Created by Codex on 2/25/26.
//

import Foundation
import Combine

@MainActor
final class RoomCreateViewModel {
    struct State: Equatable {
        var roomName: String = ""
        var roomDescription: String = ""
        var roomNameCount: Int = 0
        var roomDescriptionCount: Int = 0
        var isCreateEnabled: Bool = false
        var isSubmitting: Bool = false
    }

    enum Event {
        case showAlert(title: String, message: String)
        case presentCreatedRoom(room: ChatRoom)
        case roomSaveCompleted(ChatRoom)
        case roomSaveFailed(RoomCreationError)
    }

    private let createRoomUseCase: CreateRoomUseCaseProtocol
    private var selectedImagePair: DefaultMediaProcessingService.ImagePair?
    private var submitTask: Task<Void, Never>?
    private let eventSubject = PassthroughSubject<Event, Never>()

    @Published private(set) var state: State

    var eventPublisher: AnyPublisher<Event, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    init(createRoomUseCase: CreateRoomUseCaseProtocol) {
        self.createRoomUseCase = createRoomUseCase
        self.state = State()
    }

    func updateRoomName(_ text: String) {
        state.roomName = text
        state.roomNameCount = text.count
        recomputeCreateEnabled()
    }

    func updateRoomDescription(_ text: String) {
        state.roomDescription = text
        state.roomDescriptionCount = text.count
        recomputeCreateEnabled()
    }

    func updateSelectedImagePair(_ pair: DefaultMediaProcessingService.ImagePair?) {
        selectedImagePair = pair
    }

    func submit() {
        guard !state.isSubmitting else { return }

        let trimmedName = state.roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = state.roomDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedDescription.isEmpty else {
            eventSubject.send(.showAlert(title: "정보 부족", message: "방 이름과 설명을 입력해주세요."))
            recomputeCreateEnabled()
            return
        }

        state.isSubmitting = true
        state.isCreateEnabled = false

        let imagePair = selectedImagePair
        submitTask?.cancel()
        submitTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.createRoomUseCase.execute(
                    roomName: trimmedName,
                    roomDescription: trimmedDescription,
                    imagePair: imagePair
                ) { [weak self] event in
                    guard let self else { return }
                    self.handleUseCaseEvent(event)
                }
            } catch is CancellationError {
                self.state.isSubmitting = false
                self.recomputeCreateEnabled()
            } catch let error as RoomCreationError {
                switch error {
                case .duplicateName:
                    self.eventSubject.send(.showAlert(
                        title: "중복된 방 이름",
                        message: "이미 존재하는 방 이름입니다. 다른 이름을 선택해 주세요."
                    ))
                case .saveFailed:
                    self.eventSubject.send(.showAlert(
                        title: "저장 실패",
                        message: "채팅방 생성에 실패했습니다. 다시 시도해주세요."
                    ))
                case .imageUploadFailed:
                    self.eventSubject.send(.showAlert(
                        title: "이미지 업로드 실패",
                        message: "방 이미지 업로드에 실패했습니다. 다시 시도해주세요."
                    ))
                }
                self.state.isSubmitting = false
                self.recomputeCreateEnabled()
            } catch {
                self.eventSubject.send(.showAlert(title: "오류", message: "방 생성 중 오류가 발생했습니다."))
                self.state.isSubmitting = false
                self.recomputeCreateEnabled()
            }
        }
    }

    private func handleUseCaseEvent(_ event: CreateRoomUseCaseEvent) {
        switch event {
        case .presentCreatedRoom(let room):
            eventSubject.send(.presentCreatedRoom(room: room))
            state.isSubmitting = false
            recomputeCreateEnabled()

        case .roomSaveCompleted(let room):
            eventSubject.send(.roomSaveCompleted(room))

        case .roomSaveFailed(let error):
            state.isSubmitting = false
            recomputeCreateEnabled()
            eventSubject.send(.roomSaveFailed(error))
        }
    }

    private func recomputeCreateEnabled() {
        let hasName = !state.roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasDescription = !state.roomDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        state.isCreateEnabled = !state.isSubmitting && hasName && hasDescription
    }
}
