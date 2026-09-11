//
//  SimpleImageViewerVC.swift
//  OutPick
//
//  Created by 김가윤 on 9/27/25.
//

import UIKit
import Kingfisher

struct ImageViewerPage {
    let initialImage: UIImage?
    let thumbnailImage: UIImage?
    let thumbnailPath: String?
    let originalPath: String?
    let shouldAlwaysResolveThumbnail: Bool
    let isAnimated: Bool

    init(
        initialImage: UIImage? = nil,
        thumbnailImage: UIImage? = nil,
        thumbnailPath: String?,
        originalPath: String?,
        shouldAlwaysResolveThumbnail: Bool = false,
        isAnimated: Bool = false
    ) {
        self.initialImage = initialImage
        self.thumbnailImage = thumbnailImage
        self.thumbnailPath = thumbnailPath
        self.originalPath = originalPath
        self.shouldAlwaysResolveThumbnail = shouldAlwaysResolveThumbnail
        self.isAnimated = isAnimated
    }
}

// MARK: - SimpleImageViewerVC
// Image viewer with paging, initial offset, and progressive loading support.
class SimpleImageViewerVC: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    typealias ProgressivePage = ImageViewerPage
    typealias CachedImageProvider = (String) async -> UIImage?
    typealias LoadImageProvider = (String, Int) async -> UIImage?
    typealias LoadImageDataProvider = (String, Int) async -> Data?

    private let pages: [ProgressivePage]
    let startIndex: Int
    private let cachedImageProvider: CachedImageProvider?
    private let loadImageProvider: LoadImageProvider?
    private let loadImageDataProvider: LoadImageDataProvider?
    private let photoLibrarySaver: PhotoLibrarySaving
    private let onClose: (() -> Void)?
    private let onReport: ((SimpleImageViewerVC) -> Void)?
    private let thumbnailMaxBytes = ChatPhotoSizePolicy.maximumFileBytes
    private let originalMaxBytes = ChatPhotoSizePolicy.maximumFileBytes
    private let swipeDownDismissTranslationThreshold: CGFloat = 120
    private let swipeDownDismissVelocityThreshold: CGFloat = 900
    private let swipeDownVerticalDominanceRatio: CGFloat = 1.5
    private let minimumZoomEpsilon: CGFloat = 0.001
    private let scrollView = UIScrollView()
    private var imageViews: [AnimatedImageView] = []
    private var pageZoomScrolls: [UIScrollView] = []
    private var pageLoadTasks: [Int: Task<Void, Never>] = [:]
    private var pageLoadRoles: [Int: PageLoadRole] = [:]
    private var lastReportedPage: Int = -1
    private var didSetInitialOffset = false
    private var chrome: ImageViewerChromeView!
    private var isChromeVisible = true
    private var isSaving = false
    private var viewerClosed = false
    private var requestIDs: [Int: UUID] = [:]
    private var loadedPages: Set<Int> = []
    private var failedPages: Set<Int> = []
    private let statusButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    private var pageCount: Int {
        pages.count
    }

    private enum PageLoadRole: Equatable {
        case demand
        case warmup
    }

    init(
        pages: [ProgressivePage],
        startIndex: Int,
        cachedImageProvider: CachedImageProvider?,
        loadImageProvider: LoadImageProvider?,
        loadImageDataProvider: LoadImageDataProvider? = nil,
        photoLibrarySaver: PhotoLibrarySaving,
        onClose: (() -> Void)? = nil,
        onReport: ((SimpleImageViewerVC) -> Void)? = nil
    ) {
        self.pages = pages
        self.startIndex = startIndex
        self.cachedImageProvider = cachedImageProvider
        self.loadImageProvider = loadImageProvider
        self.loadImageDataProvider = loadImageDataProvider
        self.photoLibrarySaver = photoLibrarySaver
        self.onClose = onClose
        self.onReport = onReport
        super.init(nibName: nil, bundle: nil)
        modalPresentationCapturesStatusBarAppearance = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        cancelAllPageLoadTasks()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Set initial page offset before the view is on screen to avoid flashing page 0.
        if !didSetInitialOffset {
            view.layoutIfNeeded()
            let pageWidth = scrollView.bounds.width
            let safeStart = max(0, min(startIndex, max(0, pageCount - 1)))
            let x = CGFloat(safeStart) * pageWidth
            scrollView.setContentOffset(CGPoint(x: x, y: 0), animated: false)
            didSetInitialOffset = true
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        scrollView.delegate = self
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // Build pages: each page has its own zooming UIScrollView containing an imageView.
        pageZoomScrolls.removeAll()
        imageViews.removeAll()

        var previousTrailing: NSLayoutXAxisAnchor = scrollView.leadingAnchor
        for index in 0..<pageCount {
            let zsv = UIScrollView()
            zsv.delegate = self
            zsv.minimumZoomScale = 1.0
            zsv.maximumZoomScale = 3.0
            zsv.bouncesZoom = true
            zsv.showsVerticalScrollIndicator = false
            zsv.showsHorizontalScrollIndicator = false
            zsv.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(zsv)

            NSLayoutConstraint.activate([
                zsv.topAnchor.constraint(equalTo: scrollView.topAnchor),
                zsv.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
                zsv.leadingAnchor.constraint(equalTo: previousTrailing),
                zsv.widthAnchor.constraint(equalTo: view.widthAnchor),
                zsv.heightAnchor.constraint(equalTo: view.heightAnchor)
            ])

            let iv = AnimatedImageView()
            iv.contentMode = .scaleAspectFit
            iv.clipsToBounds = true
            iv.autoPlayAnimatedImage = false
            iv.framePreloadCount = 3
            iv.needsPrescaling = true
            iv.runLoopMode = .default
            iv.translatesAutoresizingMaskIntoConstraints = false
            zsv.addSubview(iv)

            NSLayoutConstraint.activate([
                iv.topAnchor.constraint(equalTo: zsv.contentLayoutGuide.topAnchor),
                iv.bottomAnchor.constraint(equalTo: zsv.contentLayoutGuide.bottomAnchor),
                iv.leadingAnchor.constraint(equalTo: zsv.contentLayoutGuide.leadingAnchor),
                iv.trailingAnchor.constraint(equalTo: zsv.contentLayoutGuide.trailingAnchor),
                iv.widthAnchor.constraint(equalTo: zsv.frameLayoutGuide.widthAnchor),
                iv.heightAnchor.constraint(equalTo: zsv.frameLayoutGuide.heightAnchor)
            ])

            if let initialImage = pages[index].initialImage ?? pages[index].thumbnailImage {
                iv.image = initialImage
            }

            pageZoomScrolls.append(zsv)
            imageViews.append(iv)
            previousTrailing = zsv.trailingAnchor
        }

        previousTrailing.constraint(equalTo: scrollView.trailingAnchor).isActive = true

        setupChromeUI()
        setupGestures()

        if pageCount > 0 {
            let safeStart = max(0, min(startIndex, pageCount - 1))
            scheduleProgressiveLoads(around: safeStart)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        let index = currentIndex()
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.view.layoutIfNeeded()
            self.scrollView.setContentOffset(CGPoint(x: CGFloat(index) * self.scrollView.bounds.width, y: 0), animated: false)
        })
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        hideChrome(animated: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateAnimatedPlayback(activeIndex: currentIndex())
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        imageViews.forEach { $0.stopAnimating() }
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            viewerClosed = true
            cancelAllPageLoadTasks()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView, pageCount > 0 else { return }
        let page = Int(round(scrollView.contentOffset.x / max(1, scrollView.bounds.width)))
        let clamped = min(max(0, page), pageCount - 1)
        renderChrome(index: clamped)
        renderLoadStatus(index: clamped)

        if clamped != lastReportedPage {
            for (i, zsv) in pageZoomScrolls.enumerated() where i != clamped {
                if abs(zsv.zoomScale - 1.0) > 0.001 {
                    zsv.setZoomScale(1.0, animated: false)
                }
            }
            scheduleProgressiveLoads(around: clamped)
            updateAnimatedPlayback(activeIndex: clamped)
            lastReportedPage = clamped
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        if let idx = pageZoomScrolls.firstIndex(of: scrollView) {
            return imageViews[idx]
        }
        return nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let v = touch.view else { return true }
        if v is UIControl { return false }
        if chrome != nil && v.isDescendant(of: chrome) { return false }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let idx = currentIndex()
        guard idx >= 0, idx < pageZoomScrolls.count else { return false }

        let currentZoomScroll = pageZoomScrolls[idx]
        guard abs(currentZoomScroll.zoomScale - currentZoomScroll.minimumZoomScale) <= minimumZoomEpsilon else {
            return false
        }

        let velocity = pan.velocity(in: view)
        guard velocity.y > 0 else { return false }
        return abs(velocity.y) > abs(velocity.x) * swipeDownVerticalDominanceRatio
    }

    private func currentIndex() -> Int {
        guard pageCount > 0 else { return 0 }
        let w = max(1, scrollView.bounds.width)
        let page = Int(round(scrollView.contentOffset.x / w))
        return min(max(0, page), pageCount - 1)
    }

    @objc private func closeTapped() {
        closeViewer()
    }

    @objc private func handleSwipeDownDismiss(_ gr: UIPanGestureRecognizer) {
        guard gr.state == .ended else { return }

        let translation = gr.translation(in: view)
        let velocity = gr.velocity(in: view)
        guard translation.y > 0,
              abs(translation.y) > abs(translation.x) * swipeDownVerticalDominanceRatio,
              translation.y >= swipeDownDismissTranslationThreshold || velocity.y >= swipeDownDismissVelocityThreshold else {
            return
        }

        closeViewer()
    }

    private func closeViewer() {
        viewerClosed = true
        cancelAllPageLoadTasks()
        if let onClose {
            onClose()
            return
        }
        dismiss(animated: true)
    }

    @objc private func handleToggleChrome() {
        if isChromeVisible {
            hideChrome(animated: true)
        } else {
            showChrome(animated: true)
        }
    }

    @objc private func handleDoubleTap(_ gr: UITapGestureRecognizer) {
        let idx = currentIndex()
        guard idx >= 0 && idx < pageZoomScrolls.count else { return }
        let zsv = pageZoomScrolls[idx]
        let iv = imageViews[idx]
        let point = gr.location(in: iv)

        let current = zsv.zoomScale
        let target: CGFloat = current >= 1.99 ? 1.0 : 2.0
        let size = CGSize(width: zsv.bounds.width / target, height: zsv.bounds.height / target)
        let origin = CGPoint(x: point.x - size.width / 2.0, y: point.y - size.height / 2.0)
        let rect = CGRect(origin: origin, size: size)
        zsv.zoom(to: rect, animated: true)
    }

    private func showChrome(animated: Bool) { setChromeVisible(true, animated: animated) }
    private func hideChrome(animated: Bool) { setChromeVisible(false, animated: animated) }

    private func setChromeVisible(_ visible: Bool, animated: Bool) {
        isChromeVisible = visible
        chrome.isUserInteractionEnabled = visible
        chrome.accessibilityElementsHidden = !visible
        UIView.animate(withDuration: animated && !UIAccessibility.isReduceMotionEnabled ? 0.22 : 0, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
            self.chrome.alpha = visible ? 1 : 0
        }
    }

    private func renderChrome(index: Int? = nil) {
        chrome?.render(index: index ?? currentIndex(), count: pageCount, saving: isSaving)
    }

    @objc private func saveTapped() {
        guard !isSaving, !viewerClosed, pages.indices.contains(currentIndex()) else { return }
        let index = currentIndex()
        let page = pages[index]
        let displayed = currentImage(at: index)
        isSaving = true
        renderChrome()
        Task { [weak self] in
            guard let self else { return }
            var image = displayed
            if image == nil { image = await self.loadOriginalNetwork(for: page) }
            if image == nil { image = await self.loadThumbnail(for: page) }
            var result = "저장 실패"
            if let image {
                do {
                    try await self.photoLibrarySaver.saveImage(image)
                    result = "저장 완료"
                } catch { }
            }
            self.isSaving = false
            guard !self.viewerClosed else { return }
            self.renderChrome()
            self.showToast(result)
        }
    }

    @objc private func reportTapped() {
        onReport?(self)
    }

    private func showToast(_ text: String) {
        let label = PaddingLabel()
        label.text = text
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -76)
        ])
        label.alpha = 0
        UIView.animate(withDuration: 0.18, animations: { label.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.25, delay: 1.2, options: [.curveEaseInOut]) {
                label.alpha = 0
            } completion: { _ in
                label.removeFromSuperview()
            }
        }
    }

    private func setupChromeUI() {
        chrome = ImageViewerChromeView(hasReport: onReport != nil)
        chrome.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chrome)
        NSLayoutConstraint.activate([
            chrome.topAnchor.constraint(equalTo: view.topAnchor), chrome.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            chrome.leadingAnchor.constraint(equalTo: view.leadingAnchor), chrome.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        chrome.closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        chrome.saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        chrome.reportButton.addTarget(self, action: #selector(reportTapped), for: .touchUpInside)
        renderChrome(index: max(0, min(startIndex, pageCount - 1)))
        statusButton.translatesAutoresizingMaskIntoConstraints = false
        statusButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        statusButton.tintColor = OutPickTheme.ColorToken.textPrimary
        statusButton.backgroundColor = OutPickTheme.ColorToken.backgroundBase.withAlphaComponent(0.85)
        statusButton.addTarget(self, action: #selector(retryCurrentPage), for: .touchUpInside)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = OutPickTheme.ColorToken.accent
        view.addSubview(statusButton)
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            statusButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -80),
            statusButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            statusButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor), spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        statusButton.isHidden = true
    }

    private func renderLoadStatus(index: Int? = nil) {
        guard isViewLoaded, chrome != nil, !viewerClosed else { return }
        let index = index ?? currentIndex()
        let loading = requestIDs[index] != nil
        statusButton.isHidden = !failedPages.contains(index) && !(loading && currentImage(at: index) != nil)
        statusButton.isEnabled = failedPages.contains(index)
        statusButton.setTitle(failedPages.contains(index) ? "불러오지 못했어요 · 다시 시도" : "불러오는 중…", for: .normal)
        if loading && currentImage(at: index) == nil { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    @objc private func retryCurrentPage() {
        let index = currentIndex()
        guard pages.indices.contains(index) else { return }
        cancelPageLoadTask(for: index)
        startProgressiveLoad(for: index, page: pages[index], role: .demand)
    }

    private func setupGestures() {
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.delegate = self
        doubleTap.delaysTouchesBegan = false
        doubleTap.delaysTouchesEnded = false
        view.addGestureRecognizer(doubleTap)

        let toggleTap = UITapGestureRecognizer(target: self, action: #selector(handleToggleChrome))
        toggleTap.numberOfTapsRequired = 1
        toggleTap.cancelsTouchesInView = false
        toggleTap.delegate = self
        toggleTap.delaysTouchesBegan = false
        toggleTap.delaysTouchesEnded = false
        toggleTap.require(toFail: doubleTap)
        view.addGestureRecognizer(toggleTap)

        let swipeDownDismiss = UIPanGestureRecognizer(target: self, action: #selector(handleSwipeDownDismiss(_:)))
        swipeDownDismiss.cancelsTouchesInView = false
        swipeDownDismiss.delegate = self
        view.addGestureRecognizer(swipeDownDismiss)
    }

    private func scheduleProgressiveLoads(around index: Int) {
        guard !pages.isEmpty else { return }
        let current = max(0, min(index, pages.count - 1))
        let lower = max(0, index - 2)
        let upper = min(pages.count - 1, index + 2)
        guard lower <= upper else { return }

        for taskIndex in Array(pageLoadTasks.keys) where taskIndex < lower || taskIndex > upper {
            cancelPageLoadTask(for: taskIndex)
        }

        if pageLoadRoles[current] != .demand {
            cancelPageLoadTask(for: current)
        }
        if pageLoadTasks[current] == nil && !loadedPages.contains(current) && !failedPages.contains(current) {
            startProgressiveLoad(for: current, page: pages[current], role: .demand)
        }

        for i in lower...upper where i != current && pageLoadTasks[i] == nil && !loadedPages.contains(i) && !failedPages.contains(i) {
            startProgressiveLoad(for: i, page: pages[i], role: .warmup)
        }
    }

    private func startProgressiveLoad(
        for index: Int,
        page: ProgressivePage,
        role: PageLoadRole
    ) {
        let requestID = UUID()
        requestIDs[index] = requestID
        failedPages.remove(index)
        let task = Task(priority: role == .demand ? .userInitiated : .utility) { [weak self] in
            guard let self else { return }
            func isCurrent() -> Bool { !Task.isCancelled && !self.viewerClosed && self.requestIDs[index] == requestID }
            var original = await self.loadOriginalCached(for: page)
            guard isCurrent() else { return }
            if original == nil {
                if self.shouldResolveThumbnail(for: index, page: page), let thumbnail = await self.loadThumbnail(for: page) {
                    guard isCurrent() else { return }
                    self.setImage(thumbnail, at: index)
                }
                guard isCurrent() else { return }
                if role == .warmup { try? await Task.sleep(nanoseconds: 150_000_000) }
                guard isCurrent() else { return }
                original = await self.loadOriginalNetwork(for: page)
            }
            guard isCurrent() else { return }
            if let original { self.setImage(original, at: index) }
            let hasOriginalPath = !(page.originalPath ?? "").isEmpty
            if original != nil || (!hasOriginalPath && self.currentImage(at: index) != nil) {
                self.loadedPages.insert(index)
            } else {
                self.failedPages.insert(index)
            }
            self.requestIDs[index] = nil
            self.clearPageLoadTask(for: index)
            self.renderLoadStatus()
        }
        pageLoadTasks[index] = task
        pageLoadRoles[index] = role
        renderLoadStatus()
    }

    private func loadOriginalCached(
        for page: ProgressivePage
    ) async -> UIImage? {
        guard !page.isAnimated else { return nil }
        return await cachedImageFromPath(page.originalPath)
    }

    private func loadOriginalNetwork(
        for page: ProgressivePage
    ) async -> UIImage? {
        if page.isAnimated {
            return await loadAnimatedImage(for: page)
        }
        if let cached = await loadOriginalCached(for: page) {
            return cached
        }
        return await loadImageFromPath(page.originalPath, maxBytes: originalMaxBytes)
    }

    private func loadAnimatedImage(for page: ProgressivePage) async -> UIImage? {
        guard let data = await loadImageDataFromPath(page.originalPath, maxBytes: originalMaxBytes) else {
            return nil
        }
        return Self.makeAnimatedImage(from: data)
    }

    private func loadThumbnail(
        for page: ProgressivePage
    ) async -> UIImage? {
        if let image = page.thumbnailImage {
            return image
        }
        if let cached = await cachedImageFromPath(page.thumbnailPath) {
            return cached
        }
        return await loadImageFromPath(page.thumbnailPath, maxBytes: thumbnailMaxBytes)
    }

    @MainActor
    private func shouldResolveThumbnail(for index: Int, page: ProgressivePage) -> Bool {
        if page.shouldAlwaysResolveThumbnail {
            return true
        }
        return currentImage(at: index) == nil
    }

    private func cachedImageFromPath(_ path: String?) async -> UIImage? {
        guard let path, !path.isEmpty else { return nil }
        if let local = loadLocalImage(from: path) {
            return local
        }

        if let cachedImageProvider,
           let cached = await cachedImageProvider(path) {
            return cached
        }

        return nil
    }

    private func loadImageFromPath(_ path: String?, maxBytes: Int) async -> UIImage? {
        guard let path, !path.isEmpty else { return nil }
        if let local = loadLocalImage(from: path) {
            return local
        }

        if let loadImageProvider,
           let loaded = await loadImageProvider(path, maxBytes) {
            return loaded
        }

        return nil
    }

    private func loadImageDataFromPath(_ path: String?, maxBytes: Int) async -> Data? {
        guard let path, !path.isEmpty else { return nil }
        if let fileURL = localFileURL(from: path) {
            return try? Data(contentsOf: fileURL, options: [.mappedIfSafe])
        }
        return await loadImageDataProvider?(path, maxBytes)
    }

    static func makeAnimatedImage(from data: Data) -> UIImage? {
        KingfisherWrapper<UIImage>.animatedImage(
            data: data,
            options: ImageCreatingOptions(preloadAll: false, onlyFirstFrame: false)
        )
    }

    private func localFileURL(from path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("file://") {
            return URL(string: path)
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private func loadLocalImage(from path: String?) -> UIImage? {
        guard let fileURL = localFileURL(from: path),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }

    @MainActor
    private func setImage(_ image: UIImage, at index: Int) {
        guard index >= 0, index < imageViews.count else { return }
        imageViews[index].image = image
        renderLoadStatus()
        updateAnimatedPlayback(activeIndex: currentIndex())
    }

    @MainActor
    private func updateAnimatedPlayback(activeIndex: Int) {
        for (index, imageView) in imageViews.enumerated() {
            if index == activeIndex, index < pages.count, pages[index].isAnimated {
                imageView.startAnimating()
            } else {
                imageView.stopAnimating()
            }
        }
    }

    @MainActor
    private func currentImage(at index: Int) -> UIImage? {
        guard index >= 0, index < imageViews.count else { return nil }
        return imageViews[index].image
    }

    @MainActor
    private func clearPageLoadTask(for index: Int) {
        pageLoadTasks[index] = nil
        pageLoadRoles[index] = nil
    }

    private func cancelPageLoadTask(for index: Int) {
        requestIDs[index] = nil
        pageLoadTasks[index]?.cancel()
        pageLoadTasks[index] = nil
        pageLoadRoles[index] = nil
    }

    private func cancelAllPageLoadTasks() {
        requestIDs.removeAll()
        pageLoadTasks.values.forEach { $0.cancel() }
        pageLoadTasks.removeAll()
        pageLoadRoles.removeAll()
    }

    // Simple padding label for toast
    private final class PaddingLabel: UILabel {
        private let inset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: inset)) }
        override var intrinsicContentSize: CGSize {
            let s = super.intrinsicContentSize
            return CGSize(width: s.width + inset.left + inset.right, height: s.height + inset.top + inset.bottom)
        }
    }
}
