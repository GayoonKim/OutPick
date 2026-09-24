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
    func saveOriginal(_ lease: ChatOriginalFileLease, isVideo: Bool) async throws {
        let cancellation = ChatOriginalValidity()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard lease.isValid else { throw CancellationError() }
            let granted = await requestPhotoAddPermission()
            try Task.checkCancellation()
            guard lease.isValid else { throw CancellationError() }
            guard granted else { throw PhotoLibrarySaveError.permissionDenied }
            let prepared = try PhotoLibraryPreparedResource(fileURL: lease.fileURL, isVideo: isVideo)
            defer { prepared.cleanup() }
            try Task.checkCancellation()
            guard lease.isValid else { throw CancellationError() }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges({
                    // Photos가 실제 change block을 실행할 때까지 닫기·세대 변경을 재확인한다.
                    guard cancellation.isValid, lease.isValid else { return }
                    PHAssetCreationRequest.forAsset().addResource(
                        with: isVideo ? .video : .photo, fileURL: prepared.fileURL, options: prepared.options
                    )
                }) { success, error in
                    if !cancellation.isValid || !lease.isValid { continuation.resume(throwing: CancellationError()) }
                    else if let error {
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
        } onCancel: { cancellation.invalidate() }
    }

    func saveImage(_ image: UIImage) async throws {
        let granted = await requestPhotoAddPermission()
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
        let granted = await requestPhotoAddPermission()
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

    private func requestPhotoAddPermission() async -> Bool {
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
