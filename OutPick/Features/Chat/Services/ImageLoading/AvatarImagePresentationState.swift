import Combine
import UIKit

struct AvatarImageIdentity: Equatable {
    let userID: String
    let path: String?
    init(userID: String, path: String?) {
        self.userID = userID
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.path = trimmed?.isEmpty == false ? trimmed : nil
    }
}

/// 화면 한 곳의 표시 수명만 소유한다. 네트워크 병합과 캐시는 서비스가 담당한다.
@MainActor
final class AvatarImagePresentationState: ObservableObject {
    enum Status: Equatable { case idle, loading, loaded, failed(retryable: Bool) }
    @Published private(set) var image: UIImage?
    @Published private(set) var status: Status = .idle
    private(set) var identity: AvatarImageIdentity?
    var onImageChanged: ((UIImage?) -> Void)?
    private var task: Task<Void, Never>?
    private var revision = UUID()
    private var loader: (() async throws -> UIImage?)?
    private var displayEvents = Set<String>()

    func displayed(eventID: String) {
        guard displayEvents.insert(eventID).inserted else { return }
        resume()
    }

    func refreshFailure() {
        guard case .failed = status else { return }
        status = .idle
        resume()
    }

    deinit { task?.cancel() }

    func configure(identity: AvatarImageIdentity, start: Bool = true, initialImage: UIImage? = nil, loader: @escaping () async throws -> UIImage?) {
        if self.identity != identity {
            reset()
            self.identity = identity
        }
        self.loader = loader
        if image == nil, let initialImage {
            image = initialImage
            onImageChanged?(initialImage)
        }
        if start, status == .idle { resume() }
    }

    func resume() {
        guard identity?.path != nil, task == nil, let loader else { return }
        guard status == .idle || status == .failed(retryable: true) else { return }
        status = .loading
        let expected = UUID()
        revision = expected
        task = Task { [weak self] in
            do {
                let image = try await loader()
                try Task.checkCancellation()
                guard let self, self.revision == expected else { return }
                self.task = nil
                if let image {
                    self.image = image
                    self.status = .loaded
                    self.onImageChanged?(image)
                } else { self.status = .failed(retryable: true) }
            } catch {
                guard !Task.isCancelled, let self, self.revision == expected else { return }
                self.task = nil
                if error is CancellationError { self.status = .idle; return }
                let permanent = (error as? AvatarImageLoadingError) == .unavailable
                self.status = .failed(retryable: !permanent)
            }
        }
    }

    func suspend() {
        revision = UUID()
        task?.cancel()
        task = nil
        if status == .loading { status = .idle }
    }

    func reset() {
        suspend()
        identity = nil
        displayEvents.removeAll()
        loader = nil
        image = nil
        status = .idle
        onImageChanged?(nil)
    }
}

extension AvatarImagePresentationState {
    func configure(userID: String, path: String?, manager: AvatarImageManaging, start: Bool = true, original: Bool = false) {
        let identity = AvatarImageIdentity(userID: userID, path: path)
        let initialImage = original ? nil : identity.path.flatMap { manager.cachedAvatarImmediately(for: $0) }
        configure(identity: identity, start: start, initialImage: initialImage) {
            guard let path = identity.path else { return nil }
            if original { return try await manager.loadOriginalAvatar(for: path) }
            if let cached = await manager.cachedAvatar(for: path) { return cached }
            try Task.checkCancellation()
            return try await manager.loadAvatar(for: path, maxBytes: AvatarImageRequest.thumbnailMaximumBytes)
        }
    }
}
