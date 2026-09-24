import Foundation

/// 캐시 파일이 교체·퇴거돼도 같은 내용을 읽도록 inode를 보존한다. 파일 내용은 복사하지 않는다.
final class ImageCacheReadLease: @unchecked Sendable {
    let url: URL
    private static let directory: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("outpick-cache-read-leases", isDirectory: true)
        // 이전 프로세스가 강제 종료되어 남긴 전용 링크만 정리한다. 프로세스당 한 번 실행한다.
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    init(source: URL) throws {
        url = Self.directory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.linkItem(at: source, to: url)
        ImageCacheMetrics.shared.mark("diskReadLease.created", key: url.path)
    }

    deinit {
        do {
            try FileManager.default.removeItem(at: url)
            ImageCacheMetrics.shared.mark("diskReadLease.released", key: url.path, outcome: "removed")
        } catch {
            ImageCacheMetrics.shared.mark("diskReadLease.released", key: url.path, outcome: "removeFailed")
        }
    }
}
