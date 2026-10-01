import Foundation

protocol ChatOriginalFileTransport: Sendable {
    /// 취소 요청만으로 반환하지 않고 실제 쓰기 종료 후 반환한다. 목적지 소유권은 store에 있다.
    func download(_ resource: ChatOriginalResource, to destination: URL) async throws
}

final class FirebaseChatOriginalFileTransport: ChatOriginalFileTransport, @unchecked Sendable {
    private let repository: FirebaseImageStorageRepositoryProtocol
    private let signedDownloads: ChatMediaSignedDownloadService?

    init(repository: FirebaseImageStorageRepositoryProtocol, signedDownloads: ChatMediaSignedDownloadService? = nil) {
        self.repository = repository; self.signedDownloads = signedDownloads
    }

    func download(_ resource: ChatOriginalResource, to destination: URL) async throws {
        try Task.checkCancellation()
        if let signedDownloads, !resource.path.hasPrefix("/"), !resource.path.hasPrefix("file://") {
            try await signedDownloads.file(resource: resource, maxBytes: resource.maximumBytes, to: destination)
            return
        }
        if resource.path.hasPrefix("/") || resource.path.hasPrefix("file://") {
            let source = resource.path.hasPrefix("/") ? URL(fileURLWithPath: resource.path) : URL(string: resource.path)!
            let bytes = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes > 0, bytes <= resource.maximumBytes else { throw ImageCachePipelineError.imageTooLarge }
            // outbox 원본을 이동하거나 삭제하지 않고 이 저장소 소유의 사본을 만든다.
            try FileManager.default.copyItem(at: source, to: destination)
            try Task.checkCancellation()
            return
        }
        if let url = URL(string: resource.path), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            let (temporary, response) = try await URLSession.shared.download(from: url)
            defer { try? FileManager.default.removeItem(at: temporary) }
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
            let bytes = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes > 0, bytes <= resource.maximumBytes else { throw ImageCachePipelineError.imageTooLarge }
            try FileManager.default.moveItem(at: temporary, to: destination)
            return
        }
        // 채팅 Storage 원본은 사진/GIF/영상 모두 같은 SDK 파일 완료·취소 경계를 사용한다.
        try await repository.fetchImageFileFromStorage(
            image: resource.path, location: .roomImage, maxBytes: resource.maximumBytes, to: destination
        )
    }
}
