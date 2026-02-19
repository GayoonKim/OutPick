//
//  FirebaseImageStorageRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 2/19/26.
//

import Foundation
import UIKit

protocol FirebaseImageStorageRepositoryProtocol {
    func uploadImage(
        sha: String,
        uid: String,
        type: ImageLocation,
        thumbData: Data,
        originalFileURL: URL,
        contentType: String
    ) async throws -> (avatarThumbPath: String, avatarPath: String)

    func uploadAndSave(
        sha: String,
        uid: String,
        type: ImageLocation,
        thumbData: Data,
        originalFileURL: URL,
        versionHint: String?,
        contentType: String
    ) async throws -> (avatarThumbPath: String, avatarPath: String)

    func uploadPairsToRoomMessage(
        _ pairs: [DefaultMediaProcessingService.ImagePair],
        roomID: String,
        messageID: String,
        cacheTTLThumbDays: Int,
        cacheTTLOriginalDays: Int,
        cleanupTemp: Bool,
        onProgress: ((Double) -> Void)?
    ) async throws -> [Attachment]

    func fetchImageFromStorage(image: String, location: ImageLocation) async throws -> UIImage
    func fetchImagesFromStorage(from imagePaths: [String], location: ImageLocation, createdDate: Date) async throws -> [UIImage]
    func prefetchImages(paths: [String], location: ImageLocation, createdDate: Date)
    func deleteImageFromStorage(path: String)
    func setDataFallbackLimitMB(_ mb: Int)
}
