//
//  PhotoLibrarySaver.swift
//  OutPick
//
//  Created by Codex on 6/24/26.
//

import Foundation
import Photos
import UIKit

protocol PhotoLibrarySaving {
    func saveImage(_ image: UIImage) async throws
    func saveVideo(fileURL: URL) async throws
    func saveOriginal(_ lease: ChatOriginalFileLease, isVideo: Bool) async throws
}

extension PhotoLibrarySaving {
    func saveOriginal(_ lease: ChatOriginalFileLease, isVideo: Bool) async throws {
        throw PhotoLibrarySaveError.saveFailed
    }
}

enum PhotoLibrarySaveError: LocalizedError, Equatable {
    case permissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "사진 앱 저장 권한이 필요합니다."
        case .saveFailed:
            return "사진 앱에 저장하지 못했습니다."
        }
    }
}

final class DefaultPhotoLibrarySaver: PhotoLibrarySaving {
    private let requestPermission: () async -> Bool
    private let submitOriginal: (PhotoLibraryPreparedResource, Bool) async throws -> Void

    // 기본 앱 경로는 Photos를 그대로 사용하고, 테스트만 권한·제출 완료 경계를 제어한다.
    init(
        requestPermission: (() async -> Bool)? = nil,
        submitOriginal: ((PhotoLibraryPreparedResource, Bool) async throws -> Void)? = nil
    ) {
        self.requestPermission = requestPermission ?? Self.requestPhotoAddPermission
        self.submitOriginal = submitOriginal ?? Self.submitOriginalToPhotos
    }

    func saveOriginal(_ lease: ChatOriginalFileLease, isVideo: Bool) async throws {
        try Task.checkCancellation()
        guard lease.isValid else { throw CancellationError() }
        let granted = await requestPermission()
        try Task.checkCancellation()
        guard lease.isValid else { throw CancellationError() }
        guard granted else { throw PhotoLibrarySaveError.permissionDenied }
        let prepared = try PhotoLibraryPreparedResource(fileURL: lease.fileURL, isVideo: isVideo)
        defer { prepared.cleanup() }
        try Task.checkCancellation()
        guard lease.beginPhotoLibrarySubmission() else { throw CancellationError() }

        try await submitOriginal(prepared, isVideo)
    }

    private static func submitOriginalToPhotos(_ prepared: PhotoLibraryPreparedResource, isVideo: Bool) async throws {
        // performChanges 호출이 제출 경계다. 여기부터 완료 콜백까지는 화면 닫힘·만료·Task 취소와 무관하게 처리한다.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(
                    with: isVideo ? .video : .photo, fileURL: prepared.fileURL, options: prepared.options
                )
            }) { success, error in
                if let error {
                    #if DEBUG
                    let failure = error as NSError
                    print("[MediaQA] event=originalSaveFailed video=\(isVideo) domain=\(failure.domain) code=\(failure.code)")
                    #endif
                    continuation.resume(throwing: error)
                }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: PhotoLibrarySaveError.saveFailed) }
            }
        }
    }

    func saveImage(_ image: UIImage) async throws {
        let granted = await requestPermission()
        guard granted else { throw PhotoLibrarySaveError.permissionDenied }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoLibrarySaveError.saveFailed)
                }
            }
        }
    }

    func saveVideo(fileURL: URL) async throws {
        let granted = await requestPermission()
        guard granted else { throw PhotoLibrarySaveError.permissionDenied }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoLibrarySaveError.saveFailed)
                }
            }
        }
    }

    private static func requestPhotoAddPermission() async -> Bool {
        if #available(iOS 14, *) {
            let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            if status == .authorized || status == .limited {
                return true
            }
            let nextStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return nextStatus == .authorized || nextStatus == .limited
        } else {
            let status = PHPhotoLibrary.authorizationStatus()
            if status == .authorized {
                return true
            }
            let nextStatus = await withCheckedContinuation { (continuation: CheckedContinuation<PHAuthorizationStatus, Never>) in
                PHPhotoLibrary.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            return nextStatus == .authorized
        }
    }
}
