import AVKit
import Combine
import UIKit

/// AVKit 기본 조작도 재개·seek 전에 같은 URL/미디어 경계를 거치게 한다.
final class ChatExpiryVideoPlayer: AVPlayer {
    var allowRate: (@MainActor (Float) -> Bool)?
    var allowSeek: (@MainActor (CMTime) -> Bool)?
    var isRestoring = false

    // AVKit은 seekQueue에서도 조작한다. 경계 검사와 실제 조작을 함께 메인 액터로 전달한다.
    private func performControl(_ operation: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { operation() }
        } else {
            DispatchQueue.main.async { operation() }
        }
    }

    override var rate: Float {
        get { super.rate }
        set { performControl { if self.isRestoring || self.allowRate?(newValue) != false { super.rate = newValue } } }
    }
    override func play() {
        performControl { if self.isRestoring || self.allowRate?(1) != false { super.play() } }
    }
    override func pause() {
        performControl { if self.isRestoring || self.allowRate?(0) != false { super.pause() } }
    }
    override func playImmediately(atRate rate: Float) {
        performControl { if self.isRestoring || self.allowRate?(rate) != false { super.playImmediately(atRate: rate) } }
    }
    override func seek(to time: CMTime) {
        performControl { if self.isRestoring || self.allowSeek?(time) != false { super.seek(to: time) } }
    }
    override func seek(to time: CMTime, completionHandler: @escaping @Sendable (Bool) -> Void) {
        performControl {
            if self.isRestoring || self.allowSeek?(time) != false { super.seek(to: time, completionHandler: completionHandler) }
            else { completionHandler(false) }
        }
    }
    override func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) {
        performControl {
            if self.isRestoring || self.allowSeek?(time) != false { super.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter) }
        }
    }
    override func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime,
                       completionHandler: @escaping @Sendable (Bool) -> Void) {
        performControl {
            if self.isRestoring || self.allowSeek?(time) != false {
                super.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter, completionHandler: completionHandler)
            } else { completionHandler(false) }
        }
    }
}

@MainActor
final class ChatVideoPlaybackSession {
    enum State: Equatable {
        case ready, refreshing, expired, closed
        case failed(ChatVideoPlaybackError)
    }

    let player = ChatExpiryVideoPlayer()
    private(set) var asset: ChatVideoPlaybackAsset?
    private(set) var state: State = .ready { didSet { onState?(state) } }
    var onState: ((State) -> Void)?
    private let resolver: any ChatVideoPlaybackResolving
    private let now: () -> Date
    private var expiryTimer: Timer?
    private var urlTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var revision = UUID()
    private var subscriptions = Set<AnyCancellable>()
    private var statusObserver: NSKeyValueObservation?
    private var position = CMTime.zero
    private var intendedRate: Float = 0

    init(asset: ChatVideoPlaybackAsset?, resolver: any ChatVideoPlaybackResolving, now: @escaping () -> Date = Date.init) {
        self.asset = asset
        self.resolver = resolver
        self.now = now
        player.allowRate = { [weak self] rate in
            self?.allowRate(rate) ?? false
        }
        player.allowSeek = { [weak self] time in
            self?.allowSeek(time) ?? false
        }
        resolver.invalidations.sink { [weak self] path in
            guard let self, path == nil || path == self.asset?.sourcePath else { return }
            self.stop(as: .closed)
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.checkBoundaries() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)
            .sink { [weak self] event in
                guard let self, let item = event.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.intendedRate = 0
            }.store(in: &subscriptions)
        // 만료 진입 화면은 URL·파일 없이 안내만 표시한다.
        guard let asset else { state = .expired; return }
        if validateMedia() {
            installItem(url: asset.url)
            scheduleBoundaries()
        }
    }

    var canSave: Bool { asset != nil && state != .expired && state != .closed && resolver.isSessionValid }

    func start() { player.play() }
    func close() { stop(as: .closed) }

    func retry() {
        guard case .failed(let error) = state,
              error == .temporarilyUnavailable || error == .invalidResponse,
              validateMedia() else { return }
        beginRefresh()
    }

    func checkBoundaries() {
        guard validateMedia() else { return }
        if isURLExpired, intendedRate > 0, state == .ready { beginRefresh() }
        scheduleBoundaries()
    }

    private var isURLExpired: Bool { asset?.urlExpiresAt.map { $0 <= now() } ?? false }

    @discardableResult
    private func validateMedia() -> Bool {
        guard state != .closed, state != .expired, let asset else { return false }
        guard resolver.isSessionValid else { stop(as: .closed); return false }
        if let expiry = asset.resource?.mediaExpiresAt, expiry <= now() { stop(as: .expired); return false }
        if let lease = asset.fileLease, !lease.isValid { stop(as: .closed); return false }
        return true
    }

    private func allowRate(_ rate: Float) -> Bool {
        guard validateMedia() else { return false }
        intendedRate = rate
        if state == .refreshing { return false }
        if case .failed = state { return rate == 0 }
        if rate > 0, isURLExpired { beginRefresh(); return false }
        return true
    }

    private func allowSeek(_ time: CMTime) -> Bool {
        guard validateMedia() else { return false }
        if state == .refreshing { position = time; return false }
        if case .failed = state { position = time; return false }
        if isURLExpired {
            position = time
            beginRefresh(preservePosition: true)
            return false
        }
        return true
    }

    private func beginRefresh(preservePosition: Bool = false) {
        guard validateMedia(), state != .refreshing, let resource = asset?.resource else { return }
        if state == .ready, !preservePosition { position = player.currentTime() }
        if !position.isNumeric { position = .zero }
        state = .refreshing
        let token = UUID()
        revision = token
        urlTimer?.invalidate()
        player.isRestoring = true
        player.pause()
        player.isRestoring = false
        statusObserver = nil
        player.currentItem?.cancelPendingSeeks()
        player.replaceCurrentItem(with: nil)
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let next = try await resolver.playbackAsset(for: resource, forceRefresh: true)
                guard !Task.isCancelled, revision == token, validateMedia() else {
                    await next.fileLease?.release()
                    return
                }
                let previousLease = asset?.fileLease
                asset = next
                await previousLease?.release()
                guard revision == token, validateMedia() else { return }
                installItem(url: next.url)
            } catch {
                guard revision == token, state != .closed, state != .expired else { return }
                if !resolver.isSessionValid || error is CancellationError { stop(as: .closed); return }
                if error as? ChatVideoPlaybackError == .expired { stop(as: .expired); return }
                fail(error as? ChatVideoPlaybackError ?? .temporarilyUnavailable)
            }
        }
    }

    private func installItem(url: URL) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
            Task { @MainActor in
                guard let self, let item, self.player.currentItem === item, self.validateMedia() else { return }
                switch item.status {
                case .readyToPlay:
                    if self.state == .refreshing { self.restorePosition() }
                case .failed:
                    if self.state == .ready, self.isURLExpired { self.beginRefresh() }
                    else { self.fail(.temporarilyUnavailable) }
                default: break
                }
            }
        }
    }

    private func restorePosition() {
        let token = revision
        let target = position
        player.isRestoring = true
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] succeeded in
            Task { @MainActor in
                guard let self, self.revision == token, self.state == .refreshing, self.validateMedia() else { return }
                guard succeeded else { self.fail(.temporarilyUnavailable); return }
                if CMTimeCompare(target, self.position) != 0 { self.restorePosition(); return }
                self.state = .ready
                self.player.isRestoring = true
                self.player.rate = self.intendedRate
                self.player.isRestoring = false
                self.scheduleBoundaries()
            }
        }
        player.isRestoring = false
    }

    private func fail(_ error: ChatVideoPlaybackError) {
        player.isRestoring = true
        player.pause()
        player.isRestoring = false
        state = .failed(error)
        urlTimer?.invalidate()
        // 실패 후 자동 재발급은 없다. 미디어 만료 타이머는 계속 유지한다.
    }

    private func scheduleBoundaries() {
        expiryTimer?.invalidate()
        urlTimer?.invalidate()
        expiryTimer = nil
        urlTimer = nil
        guard state != .closed, state != .expired, let asset else { return }
        if let expiry = asset.resource?.mediaExpiresAt {
            expiryTimer = Timer.scheduledTimer(withTimeInterval: max(0.01, expiry.timeIntervalSince(now())), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkBoundaries() }
            }
            if let expiryTimer { RunLoop.main.add(expiryTimer, forMode: .common) }
        }
        if let expiry = asset.urlExpiresAt, expiry > now(), state == .ready {
            urlTimer = Timer.scheduledTimer(withTimeInterval: max(0.01, expiry.timeIntervalSince(now())), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkBoundaries() }
            }
            if let urlTimer { RunLoop.main.add(urlTimer, forMode: .common) }
        }
    }

    private func stop(as finalState: State) {
        guard state != .closed, state != .expired else { return }
        revision = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        expiryTimer?.invalidate()
        urlTimer?.invalidate()
        statusObserver = nil
        player.isRestoring = true
        player.pause()
        player.currentItem?.cancelPendingSeeks()
        player.replaceCurrentItem(with: nil)
        player.isRestoring = false
        let lease = asset?.fileLease
        asset = nil
        state = finalState
        if let lease { Task { await lease.release() } }
    }

    deinit {
        refreshTask?.cancel()
        expiryTimer?.invalidate()
        urlTimer?.invalidate()
        let lease = asset?.fileLease
        if let lease { Task { await lease.release() } }
    }
}

final class ChatVideoPlaybackStatusView: UIStackView {
    private let expiredImageView = UIImageView(image: UIImage(systemName: "photo"))
    private let label = UILabel()
    private let retryButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    var onRetry: (() -> Void)?
    var onClose: (() -> Void)?

    init() {
        super.init(frame: .zero)
        axis = .vertical
        alignment = .center
        spacing = 16
        expiredImageView.tintColor = .secondaryLabel
        expiredImageView.contentMode = .scaleAspectFit
        expiredImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            expiredImageView.widthAnchor.constraint(equalToConstant: 64),
            expiredImageView.heightAnchor.constraint(equalToConstant: 64)
        ])
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        retryButton.setTitle("다시 시도", for: .normal)
        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
        closeButton.setTitle("닫기", for: .normal)
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        [expiredImageView, label, retryButton, closeButton].forEach(addArrangedSubview)
        isHidden = true
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func render(_ state: ChatVideoPlaybackSession.State) {
        isHidden = state == .ready || state == .closed
        retryButton.isHidden = true
        expiredImageView.isHidden = state != .expired
        switch state {
        case .expired: label.text = "미디어 저장 기간이 만료되었어요."
        case .refreshing: label.text = "동영상을 불러오는 중입니다"
        case .failed(let error):
            label.text = error.errorDescription
            retryButton.isHidden = error != .temporarilyUnavailable && error != .invalidResponse
        case .ready, .closed: label.text = nil
        }
    }

    func attach(to view: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(self)
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centerYAnchor.constraint(equalTo: view.centerYAnchor),
            leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }
}
