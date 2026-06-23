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
