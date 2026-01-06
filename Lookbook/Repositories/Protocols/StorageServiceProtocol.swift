//
//  StorageServiceProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 12/17/25.
//

import Foundation
import FirebaseStorage

/// `StorageServiceProtocol`은 Firebase Storage와의 상호작용을 추상화하여
/// 업로드, 다운로드, 삭제 및 메타데이터 수정을 위한 메서드를 정의합니다.
/// 이미지 전용 메서드를 제공해 API 명확성과 재사용성을 높이며,
/// 필요 시 병렬 다운로드를 통해 여러 이미지를 효율적으로 가져올 수 있습니다.
protocol StorageServiceProtocol {
    // MARK: - 업로드
    /// 이미지 데이터를 지정된 경로에 업로드하고 업로드된 스토리지 경로(path)를 반환합니다.
    ///
    /// - Note: Firestore에는 보통 다운로드 URL보다 스토리지 경로(path)를 저장하는 편이 안정적입니다.
    func uploadImage(data: Data, to path: String) async throws -> String

    /// 로컬 비디오 파일을 지정된 경로에 업로드하고 업로드된 스토리지 경로(path)를 반환합니다.
    ///
    /// - Note: Firestore에는 보통 다운로드 URL보다 스토리지 경로(path)를 저장하는 편이 안정적입니다.
    func uploadVideo(fileURL: URL, to path: String) async throws -> String

    /// 여러 이미지 데이터를 지정된 폴더 경로에 업로드하고 업로드된 스토리지 경로(path) 배열을 반환합니다.
    ///
    /// - Note: 반환되는 배열은 입력 데이터의 순서와 동일합니다.
    func uploadImages(_ datas: [Data], to folderPath: String) async throws -> [String]

    // MARK: - 다운로드 (범용)
    /// 지정된 경로의 파일을 메모리에 다운로드합니다.
    /// 파일 형식에 관계없이 사용할 수 있으며, 반환된 데이터는 상위 계층에서 적절히 처리해야 합니다.
    func downloadData(from path: String, maxSize: Int) async throws -> Data
    /// 지정된 경로의 파일을 로컬 파일 시스템으로 다운로드합니다.
    /// 대용량 파일이나 오프라인 캐시가 필요한 경우에 사용되며, 같은 위치에 파일이 존재하면 덮어씁니다.
    func downloadFile(from path: String, to localURL: URL) async throws

    // MARK: - 다운로드 (이미지 전용)
    /// 이미지 파일을 메모리에 다운로드합니다. 반환된 데이터는 UIImage(data:)로 변환해 사용합니다.
    func downloadImage(from path: String, maxSize: Int) async throws -> Data
    /// 여러 이미지 파일을 병렬로 다운로드합니다. 반환 배열의 순서는 입력된 경로 순서를 따릅니다.
    func downloadImages(_ paths: [String], maxSize: Int) async throws -> [Data]

    // MARK: - 삭제 및 업데이트
    /// 지정된 경로의 파일을 삭제합니다. 삭제된 파일은 일시적으로 복구 가능할 수 있습니다.
    func deleteFile(at path: String) async throws
    /// 지정된 경로의 파일을 새 데이터로 교체하고 교체된 스토리지 경로(path)를 반환합니다.
    ///
    /// - Note: 내부적으로 동일 경로로 재업로드하여 파일을 덮어씁니다.
    func updateFile(data: Data, at path: String) async throws -> String
    /// 지정된 경로의 파일에 대한 메타데이터를 업데이트합니다. 지정하지 않은 속성은 유지됩니다.
    func updateMetadata(for path: String,
                        metadata: StorageMetadata) async throws -> StorageMetadata
}
