//
//  FirebaseStorageService.swift
//  OutPick
//
//  Created by 김가윤 on 12/17/25.
//

import Foundation
import FirebaseStorage
#if canImport(UIKit)
import UIKit
#endif


/// Firebase Storage를 이용하여 `StorageServiceProtocol`을 구현한 클래스입니다.
///
/// 이 서비스는 Firebase Storage SDK를 감싸고 파일 업로드, 다운로드, 삭제,
/// 메타데이터 수정 등을 비동기 메서드로 제공합니다. 모든 메서드는
/// `StorageReference`의 콜백 기반 API를 Swift Concurrency를 이용해
/// `async`/`await` 형태로 변환하므로, ViewModel 같은 비동기 컨텍스트에서
/// 편리하게 사용할 수 있습니다.
final class FirebaseStorageService: StorageServiceProtocol {
    private let storage: Storage
    
    /// 주어진 `Storage` 인스턴스를 사용하여 서비스를 초기화합니다.
    /// - Parameter storage: 사용할 Firebase Storage 인스턴스. 기본값은
    ///   `Storage.storage()`입니다.
    init(storage: Storage = Storage.storage()) {
        self.storage = storage
    }
    
    // MARK: - 업로드 관련 메서드
    
    /// 주어진 경로에 이미지 데이터를 업로드하고 업로드된 스토리지 경로(path)를 반환합니다.
    ///
    /// - Note: Firestore에는 보통 다운로드 URL보다 스토리지 경로(path)를 저장하는 편이 안정적입니다.
    /// - Parameters:
    ///   - data: 업로드할 이미지 데이터.
    ///   - path: 스토리지 버킷 내 저장할 경로.
    /// - Returns: 업로드된 자산의 스토리지 경로(path).
    func uploadImage(data: Data, to path: String) async throws -> String {
        let ref = storage.reference(withPath: path)
        // 비동기 업로드 수행 (메타데이터는 nil로 전달)
        _ = try await ref.putDataAsync(data, metadata: nil)
        return path
    }
    
    /// 로컬 비디오 파일을 업로드하고 업로드된 스토리지 경로(path)를 반환합니다.
    /// - Parameters:
    ///   - fileURL: 업로드할 로컬 비디오 파일의 URL.
    ///   - path: 스토리지 버킷 내 대상 경로.
    /// - Returns: 업로드된 자산의 스토리지 경로(path).
    func uploadVideo(fileURL: URL, to path: String) async throws -> String {
        let ref = storage.reference(withPath: path)
        _ = try await ref.putFileAsync(from: fileURL, metadata: nil)
        return path
    }
    
    /// 여러 이미지를 지정된 폴더 경로에 업로드하고 업로드된 스토리지 경로(path) 배열을 반환합니다.
    ///
    /// 각 업로드 작업은 `TaskGroup`을 사용하여 병렬로 수행됩니다. 충돌을 피하기 위해 각 파일은 `UUID`를 이용해 고유 이름을 생성합니다.
    /// 반환되는 경로 배열은 입력 데이터의 순서와 동일하게 정렬됩니다.
    /// - Parameters:
    ///   - datas: 업로드할 이미지 데이터 배열.
    ///   - folderPath: 이미지가 저장될 스토리지 버킷 내 폴더 경로.
    /// - Returns: 업로드된 이미지에 대한 스토리지 경로(path) 배열.
    func uploadImages(_ datas: [Data], to folderPath: String) async throws -> [String] {
        return try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, data) in datas.enumerated() {
                group.addTask {
                    let uniqueID = UUID().uuidString
                    let path = "\(folderPath)/\(uniqueID)"
                    let uploadedPath = try await self.uploadImage(data: data, to: path)
                    return (index, uploadedPath)
                }
            }

            // 한국어 주석: 입력 순서 보장을 위해 인덱스 기반으로 결과를 채웁니다.
            var results = Array(repeating: "", count: datas.count)
            for try await (index, path) in group {
                results[index] = path
            }
            return results
        }
    }
    
    // MARK: - 다운로드 관련 메서드
    
    /// 지정된 경로의 파일에서 원시 데이터를 다운로드합니다.
    ///
    /// - Parameters:
    ///   - path: 다운로드할 스토리지 경로.
    ///   - maxSize: 다운로드할 최대 바이트 수.
    /// - Returns: 다운로드된 데이터.
    func downloadData(from path: String, maxSize: Int) async throws -> Data {
        let ref = storage.reference(withPath: path)
        // Use the async version of data(maxSize:)
        let data = try await ref.data(maxSize: Int64(maxSize))
        return data
    }
    
    /// Storage에서 파일을 로컬 URL로 다운로드합니다.
    ///
    /// 이 메서드는 지정한 로컬 URL에 파일을 기록합니다. 같은 위치에 파일이
    /// 존재하면 덮어쓰기 합니다.
    /// - Parameters:
    ///   - path: 다운로드할 스토리지 경로.
    ///   - localURL: 데이터가 저장될 로컬 파일 URL.
    func downloadFile(from path: String, to localURL: URL) async throws {
        let ref = storage.reference(withPath: path)
        // Use async version of write
        _ = try await ref.writeAsync(toFile: localURL)
    }

    /// 이미지 파일을 메모리에 다운로드합니다.
    ///
    /// 이 메서드는 `downloadData(from:maxSize:)`를 호출하여 이미지 데이터를 가져옵니다. 반환된
    /// `Data`는 UI 계층에서 `UIImage(data:)` 또는 SwiftUI의 `Image`로 변환해 사용할 수 있습니다.
    /// - Parameters:
    ///   - path: 다운로드할 이미지의 저장 경로.
    ///   - maxSize: 다운로드할 최대 바이트 수.
    /// - Returns: 다운로드된 이미지 데이터.
    func downloadImage(from path: String, maxSize: Int) async throws -> Data {
        return try await downloadData(from: path, maxSize: maxSize)
    }
    
#if canImport(UIKit)
    /// 지정된 경로의 이미지 파일을 다운로드한 뒤 `UIImage`로 디코딩하여 반환합니다.
    ///
    /// - Note: Storage 경로(path) 기반으로 바로 다운로드하고, UI 계층에서 바로 쓸 수 있도록 `UIImage`로 변환합니다.
    /// - Parameters:
    ///   - path: 다운로드할 이미지의 스토리지 경로.
    ///   - maxSize: 다운로드할 최대 바이트 수.
    /// - Returns: 디코딩된 `UIImage`.
    func downloadUIImage(from path: String, maxSize: Int) async throws -> UIImage {
        let data = try await downloadData(from: path, maxSize: maxSize)
        guard let image = UIImage(data: data) else {
            throw LookbookStorageError.imageDecodingFailed
        }
        return image
    }
    
#endif

    /// 여러 이미지 파일을 병렬로 다운로드합니다.
    ///
    /// 입력된 각 경로에 대해 `downloadData(from:maxSize:)`를 호출하고, Swift Concurrency의 `TaskGroup`을 사용하여
    /// 병렬로 다운로드합니다. 반환된 배열은 입력 경로의 순서와 동일하게 정렬됩니다. 다운로드 중 오류가 발생하면 해당
    /// 오류가 throw됩니다.
    /// - Parameters:
    ///   - paths: 다운로드할 이미지 경로 목록.
    ///   - maxSize: 각 이미지에서 다운로드할 최대 바이트 수.
    /// - Returns: 이미지 데이터 배열.
    func downloadImages(_ paths: [String], maxSize: Int) async throws -> [Data] {
        // Use a task group to download each image concurrently while preserving order
        return try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for (index, path) in paths.enumerated() {
                group.addTask {
                    let data = try await self.downloadData(from: path, maxSize: maxSize)
                    return (index, data)
                }
            }
            var results = Array(repeating: Data(), count: paths.count)
            for try await (index, data) in group {
                results[index] = data
            }
            return results
        }
    }
    
    // MARK: - 삭제 관련 메서드
    
    /// 지정된 경로의 파일을 삭제합니다.
    ///
    /// 소프트 삭제가 활성화된 버킷에서는 삭제된 파일이 잠시 복구 가능할 수 있습니다.
    /// 삭제 작업을 수행하고 실패 시 오류를 발생시킵니다.
    /// - Parameter path: 삭제할 파일의 스토리지 경로.
    func deleteFile(at path: String) async throws {
        let ref = storage.reference(withPath: path)
        // Swift concurrency에서 제네릭 타입을 명확하게 지정해 주어야 오류가 발생하지 않습니다.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ref.delete { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - 업데이트 관련 메서드
    
    /// 지정된 경로의 파일을 새 데이터로 교체하고, 교체된 스토리지 경로(path)를 반환합니다.
    ///
    /// 내부적으로 동일 경로로 재업로드하여 파일을 덮어씁니다.
    /// - Parameters:
    ///   - data: 새로 기록할 데이터.
    ///   - path: 교체할 파일의 스토리지 경로.
    /// - Returns: 교체된 자산의 스토리지 경로(path).
    func updateFile(data: Data, at path: String) async throws -> String {
        // 한국어 주석: 동일 경로로 재업로드하면 덮어쓰기 됩니다.
        return try await uploadImage(data: data, to: path)
    }
    
    /// 지정된 경로의 파일에 대한 메타데이터를 업데이트합니다.
    ///
    /// 제공된 metadata에 지정된 속성만 변경되며 지정하지 않은 속성은 그대로 유지됩니다.
    /// 업로드 후 `contentType`, `cacheControl`, 사용자 정의 메타데이터 등을 수정할 때 사용합니다.
    /// - Parameters:
    ///   - path: 메타데이터를 수정할 파일의 스토리지 경로.
    ///   - metadata: 적용할 새 메타데이터 값.
    /// - Returns: 갱신된 `StorageMetadata` 객체.
    func updateMetadata(for path: String, metadata: StorageMetadata) async throws -> StorageMetadata {
        let ref = storage.reference(withPath: path)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StorageMetadata, Error>) in
            ref.updateMetadata(metadata) { result in
                switch result {
                case .success(let updatedMetadata):
                    continuation.resume(returning: updatedMetadata)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Firebase API가 데이터도 오류도 반환하지 않을 때 사용되는 단순 오류 타입입니다.
private enum LookbookStorageError: Error {
    case unknown
    case imageDecodingFailed
}
