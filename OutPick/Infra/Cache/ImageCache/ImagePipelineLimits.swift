import Foundation

/// QA 시작값이다. 최적값이 아니며 모든 값은 자원 인스턴스를 만들 때 주입할 수 있다.
struct ImagePipelineLimits: Sendable {
    var downloads = 6
    var decodes = 2
    // SDK 다운로드 중 파일 기록을 제외한 앱 관리 I/O의 제한이다.
    var diskOperations = 2
    var diskWrites = 1
    var decodeBytes = 16 * 1024 * 1024
    var writeBytes = 16 * 1024 * 1024
}

final class ImageWorkContext: @unchecked Sendable {
    @TaskLocal static var current: ImageWorkContext?
    private let lock = NSLock()
    private var storedPriority: ImageRequestPriority
    init(_ priority: ImageRequestPriority) { storedPriority = priority }
    var priority: ImageRequestPriority {
        lock.lock()
        defer { lock.unlock() }
        return storedPriority
    }
    func update(_ priority: ImageRequestPriority) {
        lock.lock()
        storedPriority = priority
        lock.unlock()
    }
}
