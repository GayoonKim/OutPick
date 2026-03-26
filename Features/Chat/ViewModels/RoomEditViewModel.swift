//
//  RoomEditViewModel.swift
//  OutPick
//
//  Created by Codex on 3/27/26.
//

import Foundation
import UIKit
import Combine

@MainActor
final class RoomEditViewModel {
    struct State {
        var roomName: String
        var roomDescription: String
        var roomNameCount: Int
        var roomDescriptionCount: Int
        var isSubmitEnabled: Bool
        var isSubmitting: Bool
    }

    enum Event {
        case headerImageUpdated(UIImage)
        case showAlert(title: String, message: String)
        case didComplete(updatedRoom: ChatRoom)
    }

    let room: ChatRoom

    @Published private(set) var state: State

    var eventPublisher: AnyPublisher<Event, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    private let useCase: RoomEditUseCaseProtocol
    private let eventSubject = PassthroughSubject<Event, Never>()
    private var selectedImagePair: DefaultMediaProcessingService.ImagePair?
    private var isImageRemoved = false
    private var headerImageTask: Task<Void, Never>?
    private var submitTask: Task<Void, Never>?

    init(room: ChatRoom, useCase: RoomEditUseCaseProtocol) {
        self.room = room
        self.useCase = useCase
        self.state = State(
            roomName: room.roomName,
            roomDescription: room.roomDescription,
            roomNameCount: room.roomName.count,
            roomDescriptionCount: room.roomDescription.count,
            isSubmitEnabled: false,
            isSubmitting: false
        )
    }

    deinit {
        Self.cleanupTemporaryFileIfNeeded(for: selectedImagePair)
        headerImageTask?.cancel()
        submitTask?.cancel()
    }

    func loadHeaderImageIfNeeded() {
        guard Self.hasRemoteImage(in: room) else { return }

        headerImageTask?.cancel()
        headerImageTask = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await self.useCase.loadHeaderImage(for: self.room)
                guard !Task.isCancelled else { return }
                self.eventSubject.send(.headerImageUpdated(image))
            } catch {
                print("[RoomEdit] header image load failed: \(error)")
            }
        }
    }

    func updateRoomName(_ text: String) {
        state.roomName = text
        state.roomNameCount = text.count
        recomputeState()
    }

    func clearRoomName() {
        updateRoomName("")
    }

    func updateRoomDescription(_ text: String) {
        state.roomDescription = text
        state.roomDescriptionCount = text.count
        recomputeState()
    }

    func selectImage(_ pair: DefaultMediaProcessingService.ImagePair) {
        headerImageTask?.cancel()
        Self.cleanupTemporaryFileIfNeeded(for: selectedImagePair)
        selectedImagePair = pair
        isImageRemoved = false

        if let previewImage = UIImage(data: pair.thumbData) {
            eventSubject.send(.headerImageUpdated(previewImage))
        }

        recomputeState()
    }

    func removeImage() {
        headerImageTask?.cancel()
        Self.cleanupTemporaryFileIfNeeded(for: selectedImagePair)
        selectedImagePair = nil

        guard hasCustomImage else {
            isImageRemoved = false
            recomputeState()
            return
        }

        isImageRemoved = true
        recomputeState()
    }

    func submit() {
        guard !state.isSubmitting else { return }

        let trimmedName = state.roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = state.roomDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            eventSubject.send(.showAlert(title: "방 이름 입력", message: "방 이름을 입력해주세요."))
            recomputeState()
            return
        }

        guard state.isSubmitEnabled else { return }

        state.isSubmitting = true
        state.isSubmitEnabled = false

        let imagePair = selectedImagePair
        let isImageRemoved = isImageRemoved

        submitTask?.cancel()
        submitTask = Task { [weak self] in
            guard let self else { return }
            do {
                let updatedRoom = try await self.useCase.execute(
                    room: self.room,
                    imagePair: imagePair,
                    isImageRemoved: isImageRemoved,
                    roomName: trimmedName,
                    roomDescription: trimmedDescription
                )
                self.state.isSubmitting = false
                self.recomputeState()
                self.eventSubject.send(.didComplete(updatedRoom: updatedRoom))
            } catch is CancellationError {
                self.state.isSubmitting = false
                self.recomputeState()
            } catch {
                self.state.isSubmitting = false
                self.recomputeState()
                self.eventSubject.send(.showAlert(
                    title: "방 수정 실패",
                    message: error.localizedDescription
                ))
            }
        }
    }

    var shouldShowDeleteAction: Bool {
        hasCustomImage
    }

    private var hasCustomImage: Bool {
        if selectedImagePair != nil {
            return true
        }

        return Self.hasRemoteImage(in: room) && !isImageRemoved
    }

    private func recomputeState() {
        let trimmedName = state.roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = state.roomDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalName = room.roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalDescription = room.roomDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        let hasValidName = !trimmedName.isEmpty
        let nameChanged = trimmedName != originalName
        let descriptionChanged = trimmedDescription != originalDescription
        let imageChanged = selectedImagePair != nil || (isImageRemoved && Self.hasRemoteImage(in: room))

        state.isSubmitEnabled = !state.isSubmitting && hasValidName && (nameChanged || descriptionChanged || imageChanged)
    }

    private static func hasRemoteImage(in room: ChatRoom) -> Bool {
        room.coverImagePath != nil
    }

    nonisolated private static func cleanupTemporaryFileIfNeeded(for pair: DefaultMediaProcessingService.ImagePair?) {
        guard let pair else { return }
        try? FileManager.default.removeItem(at: pair.originalFileURL)
    }
}
