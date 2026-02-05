//
//  SecondProfileViewModel.swift
//  OutPick
//

import Foundation
import UIKit

@MainActor
final class SecondProfileViewModel {

    struct State: Equatable {
        var nickname: String = ""
        var nicknameCountText: String = "0 / 20"
        var isCompleteEnabled: Bool = false

        var isSaving: Bool = false
        var errorMessage: String? = nil

        // 이미지
        var isDefaultImage: Bool = true
        var selectedThumb: UIImage? = nil
        var selectedOriginalFileURL: URL? = nil
        var selectedSHA: String? = nil
    }

    private(set) var state: State {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?

    private let repository: UserProfileRepositoryProtocol
    private let draft: UserProfileDraft

    private let onBack: () -> Void
    private let onCompleted: (UserProfile) -> Void

    init(
        repository: UserProfileRepositoryProtocol,
        draft: UserProfileDraft,
        onBack: @escaping () -> Void,
        onCompleted: @escaping (UserProfile) -> Void
    ) {
        self.repository = repository
        self.draft = draft
        self.onBack = onBack
        self.onCompleted = onCompleted
        self.state = State()
        recompute()
    }

    func backTapped() {
        onBack()
    }

    func setNickname(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(trimmed.prefix(20))
        state.nickname = limited
        state.nicknameCountText = "\(limited.count) / 20"
        recompute()
    }

    func clearImage() {
        state.isDefaultImage = true
        state.selectedThumb = nil
        state.selectedOriginalFileURL = nil
        state.selectedSHA = nil
        recompute()
    }

    /// VC가 PHPicker에서 만든 결과를 전달
    func setPickedImage(thumb: UIImage?, originalFileURL: URL?, sha: String?) {
        state.isDefaultImage = (thumb == nil || originalFileURL == nil)
        state.selectedThumb = thumb
        state.selectedOriginalFileURL = originalFileURL
        state.selectedSHA = sha
        recompute()
    }

    func completeTapped() {
        guard state.isCompleteEnabled, !state.isSaving else { return }
        Task { await saveProfile() }
    }

    private func recompute() {
        state.isCompleteEnabled = !state.nickname.isEmpty && !state.isSaving
    }

    private func saveProfile() async {
        state.errorMessage = nil
        state.isSaving = true
        recompute()

        do {
            // 1) 이메일 확보
            let email = LoginManager.shared.getUserEmail
            if email.isEmpty {
                // 여기 정책은 프로젝트 상황에 맞춰 조정
                throw FirebaseError.FailedToSaveProfile
            }

            // 2) 닉네임 중복 체크(Repository API 사용)
            let duplicated = try await repository.checkDuplicate(
                strToCompare: state.nickname,
                fieldToCompare: "nickname",
                collectionName: "Users"
            )
            if duplicated {
                state.errorMessage = "이미 사용 중인 닉네임이에요."
                state.isSaving = false
                recompute()
                return
            }

            // 3) 프로필 도메인 생성
            var profile = UserProfile(
                deviceID: UIDevice.current.identifierForVendor?.uuidString,
                email: email,
                gender: draft.gender,
                birthdate: draft.birthdate,
                nickname: state.nickname,
                thumbPath: nil,
                originalPath: nil,
                joinedRooms: [],
                createdAt: Date()
            )

            // 4) 이미지 업로드(선택)
            if !state.isDefaultImage,
               let sha = state.selectedSHA,
               let fileURL = state.selectedOriginalFileURL,
               let thumbImage = state.selectedThumb,
               let thumbData = thumbImage.jpegData(compressionQuality: 0.8) {

                let uploaded = try await FirebaseStorageManager.shared.uploadImage(
                    sha: sha,
                    uid: email,
                    type: .ProfileImage,               // 프로젝트 enum에 맞게 변경 필요
                    thumbData: thumbData,
                    originalFileURL: fileURL,
                    contentType: "image/jpeg"
                )
                profile.thumbPath = uploaded.avatarThumbPath
                profile.originalPath = uploaded.avatarPath
            }

            // 5) LoginManager에 현재 프로필 세팅 + Firestore 저장
            LoginManager.shared.setCurrentUserProfile(profile)
            try await repository.saveUserProfileToFirestore(email: email)

            state.isSaving = false
            recompute()

            onCompleted(profile)

        } catch {
            state.errorMessage = "프로필 저장에 실패했어요."
            state.isSaving = false
            recompute()
        }
    }
}
