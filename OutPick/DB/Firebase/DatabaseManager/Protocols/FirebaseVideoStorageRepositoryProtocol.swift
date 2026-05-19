//
//  FirebaseVideoStorageRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 2/19/26.
//

import Foundation

protocol FirebaseVideoStorageRepositoryProtocol {
    func putVideoFileToStorage(
        localURL: URL,
        path: String,
        contentType: String,
        onProgress: @escaping (Double) -> Void
    ) async throws

    func putVideoDataToStorage(data: Data, path: String, contentType: String) async throws
    func setDataFallbackLimitMB(_ mb: Int)
}
