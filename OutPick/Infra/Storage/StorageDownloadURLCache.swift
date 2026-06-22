//
//  StorageDownloadURLCache.swift
//  OutPick
//
//  Created by Codex on 6/19/26.
//

import Foundation
import FirebaseStorage

protocol StorageDownloadURLResolving {
    func url(for path: String) async throws -> URL
}

/// Firebase Storage path를 downloadURL로 변환한 결과를 앱 실행 중 메모리에 캐시한다.
actor StorageDownloadURLCache: StorageDownloadURLResolving {
    static let shared = StorageDownloadURLCache()

    private var cache: [String: URL] = [:]

    private init() {}

    func url(for path: String) async throws -> URL {
        if let cached = cache[path] {
            return cached
        }

        let ref = Storage.storage().reference(withPath: path)
        let url = try await withCheckedThrowingContinuation { continuation in
            ref.downloadURL { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(
                        throwing: error ?? NSError(
                            domain: "Storage",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "downloadURL failed"]
                        )
                    )
                }
            }
        }
        cache[path] = url
        return url
    }
}
