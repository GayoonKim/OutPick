//
//  SimpleImageViewerVC.swift
//  OutPick
//
//  Created by 김가윤 on 9/27/25.
//

import UIKit
import Photos

// MARK: - SimpleImageViewerVC
// Image viewer with paging, initial offset, and progressive loading support.
class SimpleImageViewerVC: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    struct ProgressivePage {
        let initialImage: UIImage?
        let thumbnailImage: UIImage?
        let thumbnailPath: String?
        let originalPath: String?
        let shouldAlwaysResolveThumbnail: Bool

        init(
            initialImage: UIImage? = nil,
            thumbnailImage: UIImage? = nil,
            thumbnailPath: String?,
            originalPath: String?,
            shouldAlwaysResolveThumbnail: Bool = false
        ) {
            self.initialImage = initialImage
            self.thumbnailImage = thumbnailImage
            self.thumbnailPath = thumbnailPath
            self.originalPath = originalPath
            self.shouldAlwaysResolveThumbnail = shouldAlwaysResolveThumbnail
        }
    }

    typealias CachedImageProvider = (String) async -> UIImage?
    typealias LoadImageProvider = (String, Int) async -> UIImage?

    private let pages: [ProgressivePage]
    let startIndex: Int
    private let cachedImageProvider: CachedImageProvider?
    private let loadImageProvider: LoadImageProvider?
    private let thumbnailMaxBytes = 12 * 1024 * 1024
    private let originalMaxBytes = 60 * 1024 * 1024
    private let scrollView = UIScrollView()
    private var imageViews: [UIImageView] = []
    private var pageZoomScrolls: [UIScrollView] = []
    private var pageLoadTasks: [Int: Task<Void, Never>] = [:]
    private var lastReportedPage: Int = -1
    private var pageControl: UIPageControl!
    private var closeButton: UIButton!
    private var didSetInitialOffset = false

    private var topBar: UIView!
    private var bottomBar: UIView!
    private var isChromeVisible = false
    private var didInitializeChromeTransforms = false
    private var saveButton: UIButton!

    private var pageCount: Int {
        pages.count
    }

    init(
        pages: [ProgressivePage],
        startIndex: Int,
        cachedImageProvider: CachedImageProvider?,
        loadImageProvider: LoadImageProvider?
    ) {
        self.pages = pages
        self.startIndex = startIndex
        self.cachedImageProvider = cachedImageProvider
        self.loadImageProvider = loadImageProvider
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
        view.backgroundColor = .black
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

            let iv = UIImageView()
            iv.contentMode = .scaleAspectFit
            iv.clipsToBounds = true
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !didInitializeChromeTransforms {
            didInitializeChromeTransforms = true
            topBar.transform = CGAffineTransform(translationX: 0, y: -topBar.bounds.height)
            bottomBar.transform = CGAffineTransform(translationX: 0, y: bottomBar.bounds.height)
            topBar.alpha = 0
            bottomBar.alpha = 0
            isChromeVisible = false
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            cancelAllPageLoadTasks()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView, pageCount > 0 else { return }
        let page = Int(round(scrollView.contentOffset.x / max(1, scrollView.bounds.width)))
        let clamped = min(max(0, page), pageCount - 1)
        pageControl.currentPage = clamped

        if clamped != lastReportedPage {
            for (i, zsv) in pageZoomScrolls.enumerated() where i != clamped {
                if abs(zsv.zoomScale - 1.0) > 0.001 {
                    zsv.setZoomScale(1.0, animated: false)
                }
            }
            scheduleProgressiveLoads(around: clamped)
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
        if (topBar != nil && v.isDescendant(of: topBar)) { return false }
        if (bottomBar != nil && v.isDescendant(of: bottomBar)) { return false }
        return true
    }

    private func currentIndex() -> Int {
        guard pageCount > 0 else { return 0 }
        let w = max(1, scrollView.bounds.width)
        let page = Int(round(scrollView.contentOffset.x / w))
        return min(max(0, page), pageCount - 1)
    }

    @objc private func closeTapped() {
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

    private func showChrome(animated: Bool) {
        isChromeVisible = true
        let animations = {
            self.topBar.transform = .identity
            self.bottomBar.transform = .identity
            self.topBar.alpha = 1
            self.bottomBar.alpha = 1
        }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
                animations()
            }
        } else {
            animations()
        }
    }

    private func hideChrome(animated: Bool) {
        isChromeVisible = false
        let animations = {
            self.topBar.transform = CGAffineTransform(translationX: 0, y: -self.topBar.bounds.height)
            self.bottomBar.transform = CGAffineTransform(translationX: 0, y: self.bottomBar.bounds.height)
            self.topBar.alpha = 0
            self.bottomBar.alpha = 0
        }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn]) {
                animations()
            }
        } else {
            animations()
        }
    }

    @objc private func saveTapped() {
        let idx = currentIndex()

        if idx < imageViews.count, let image = imageViews[idx].image {
            saveImageToLibrary(image)
            return
        }

        guard idx < pages.count else {
            showToast("저장 실패")
            return
        }
        let page = pages[idx]
        Task { [weak self] in
            guard let self else { return }
            if let original = await self.loadOriginalNetwork(for: page) {
                await MainActor.run {
                    self.saveImageToLibrary(original)
                }
                return
            }
            if let thumbnail = await self.loadThumbnail(for: page) {
                await MainActor.run {
                    self.saveImageToLibrary(thumbnail)
                }
                return
            }
            await MainActor.run {
                self.showToast("저장 실패")
            }
        }
    }

    private func saveImageToLibrary(_ image: UIImage) {
        let performSave: () -> Void = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                UIImageWriteToSavedPhotosAlbum(image, self, #selector(self.saveCompletion(_:didFinishSavingWithError:contextInfo:)), nil)
            }
        }

        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                switch status {
                case .authorized, .limited:
                    performSave()
                default:
                    self.showToast("사진 접근 권한이 필요합니다")
                }
            }
        } else {
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    performSave()
                } else {
                    self.showToast("사진 접근 권한이 필요합니다")
                }
            }
        }
    }

    @objc private func saveCompletion(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async {
            if error == nil {
                self.showToast("저장 완료")
            } else {
                self.showToast("저장 실패")
            }
        }
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
            label.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -12)
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
        topBar = UIView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        view.addSubview(topBar)

        bottomBar = UIView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        view.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),

            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 56)
        ])

        pageControl = UIPageControl()
        pageControl.numberOfPages = pageCount
        pageControl.currentPage = max(0, min(startIndex, max(0, pageCount - 1)))
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(pageControl)
        NSLayoutConstraint.activate([
            pageControl.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            pageControl.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor)
        ])

        saveButton = UIButton(type: .system)
        saveButton.setImage(UIImage(systemName: "square.and.arrow.down"), for: .normal)
        saveButton.tintColor = .white
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        bottomBar.addSubview(saveButton)
        NSLayoutConstraint.activate([
            saveButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            saveButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            saveButton.widthAnchor.constraint(equalToConstant: 28),
            saveButton.heightAnchor.constraint(equalToConstant: 28)
        ])

        closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        topBar.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
            closeButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36)
        ])
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
    }

    private func scheduleProgressiveLoads(around index: Int) {
        guard !pages.isEmpty else { return }
        let lower = max(0, index - 2)
        let upper = min(pages.count - 1, index + 2)
        guard lower <= upper else { return }

        for i in lower...upper where pageLoadTasks[i] == nil {
            let page = pages[i]
            startProgressiveLoad(for: i, page: page)
        }
    }

    private func startProgressiveLoad(
        for index: Int,
        page: ProgressivePage
    ) {
        let task = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            if Task.isCancelled { return }

            if let originalCached = await self.loadOriginalCached(for: page) {
                self.setImage(originalCached, at: index)
                self.clearPageLoadTask(for: index)
                return
            }

            if Task.isCancelled { return }
            if await self.shouldResolveThumbnail(for: index, page: page),
               let thumbnail = await self.loadThumbnail(for: page) {
                self.setImage(thumbnail, at: index)
            }

            if Task.isCancelled { return }
            if let original = await self.loadOriginalNetwork(for: page) {
                self.setImage(original, at: index)
            }

            self.clearPageLoadTask(for: index)
        }

        pageLoadTasks[index] = task
    }

    private func loadOriginalCached(
        for page: ProgressivePage
    ) async -> UIImage? {
        await cachedImageFromPath(page.originalPath)
    }

    private func loadOriginalNetwork(
        for page: ProgressivePage
    ) async -> UIImage? {
        if let cached = await loadOriginalCached(for: page) {
            return cached
        }
        return await loadImageFromPath(page.originalPath, maxBytes: originalMaxBytes)
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
    }

    @MainActor
    private func currentImage(at index: Int) -> UIImage? {
        guard index >= 0, index < imageViews.count else { return nil }
        return imageViews[index].image
    }

    @MainActor
    private func clearPageLoadTask(for index: Int) {
        pageLoadTasks[index] = nil
    }

    private func cancelAllPageLoadTasks() {
        pageLoadTasks.values.forEach { $0.cancel() }
        pageLoadTasks.removeAll()
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
