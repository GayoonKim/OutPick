import Foundation
import UIKit

/// 경로는 현재 pipeline의 저장 위치·고정 decoder 안에서 해석한다.
/// thumb/detail은 기존 경로로 구분하며 새 서버 버전 필드를 요구하지 않는다.
struct ImageRequest: Hashable, Sendable {
    enum Work: Hashable, Sendable {
        case cache
        // maxBytes는 다운로드 허용량이다. 기존 캐시 히트 계약에는 적용하지 않는다.
        case load(maxBytes: Int)
        // 원본 비저장 요청은 같은 경로의 썸네일/캐시 요청과 합치지 않는다.
        case transient(maxBytes: Int)
    }

    let path: String
    let work: Work
    var cacheKey: String { "imageCache|\(path)" }
    var isTransient: Bool {
        if case .transient = work { return true }
        return false
    }
}

enum ImageRequestPriority: Int, Sendable {
    case prefetch
    case visible
}

struct ImageLoadValue {
    let image: UIImage?
    /// 다운로드 결과만 전달한다. disk hit는 다시 저장하지 않는다.
    let downloadedData: Data?
    let payload: ImageCachePayload?
    let release: (@Sendable () async -> Void)?

    init(image: UIImage?, downloadedData: Data? = nil, payload: ImageCachePayload? = nil, release: (@Sendable () async -> Void)? = nil) {
        self.image = image
        self.downloadedData = downloadedData
        self.payload = payload ?? downloadedData.map(ImageCachePayload.data)
        self.release = release
    }
}

/// 서로 다른 cache owner의 무효화도 같은 디스크 객체에 역순으로 도착할 수 있다.
enum ImageCacheRevisionClock {
    private static let lock = NSLock()
    private static var value: UInt64 = 0

    static func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
