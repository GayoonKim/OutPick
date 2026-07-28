import Foundation
import FirebaseStorage

struct UploadedProfileAvatar: Equatable {
    let thumbPath: String
    let originalPath: String
}

protocol ProfileAvatarUploading {
    func upload(
        userID: String,
        avatar: OnboardingAvatarDraft
    ) async throws -> UploadedProfileAvatar
    func delete(paths: [String]) async throws
}

struct FirebaseProfileAvatarUploader: ProfileAvatarUploading {
    private let imageRepository: FirebaseImageStorageRepositoryProtocol
    private let storage: Storage

    init(
        imageRepository: FirebaseImageStorageRepositoryProtocol,
        storage: Storage = .storage()
    ) {
        self.imageRepository = imageRepository
        self.storage = storage
    }

    func upload(
        userID: String,
        avatar: OnboardingAvatarDraft
    ) async throws -> UploadedProfileAvatar {
        guard let thumbData = avatar.thumbnail.jpegData(compressionQuality: 0.8) else {
            throw FirebaseStorageError.FailedToUploadImage
        }
        let uploaded = try await imageRepository.uploadImage(
            sha: avatar.sha256,
            uid: userID,
            type: .profileImage,
            thumbData: thumbData,
            originalFileURL: avatar.originalFileURL,
            contentType: "image/jpeg"
        )
        return UploadedProfileAvatar(
            thumbPath: uploaded.avatarThumbPath,
            originalPath: uploaded.avatarPath
        )
    }

    func delete(paths: [String]) async throws {
        let uniquePaths = Array(Set(paths.filter { !$0.isEmpty }))
        for path in uniquePaths {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                storage.reference().child(path).delete { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        KingFisherCacheManager.shared.removeImage(forKey: path)
                        continuation.resume()
                    }
                }
            }
        }
    }
}
