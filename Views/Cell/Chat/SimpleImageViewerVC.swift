//
//  SimpleImageViewerVC.swift
//  OutPick
//
//  Created by 김가윤 on 9/27/25.
//

import UIKit
import Kingfisher
import Photos

// MARK: - SimpleImageViewerVC
// Image viewer with paging, initial offset, etc.
class SimpleImageViewerVC: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let urls: [URL]
    let startIndex: Int
    private let scrollView = UIScrollView()
    private var imageViews: [UIImageView] = []
    private var pageZoomScrolls: [UIScrollView] = []
    private var lastReportedPage: Int = -1
    private var pageControl: UIPageControl!
    private var closeButton: UIButton!
    private var didSetInitialOffset = false

    private var topBar: UIView!
    private var bottomBar: UIView!
    private var isChromeVisible = false
    private var didInitializeChromeTransforms = false
    private var saveButton: UIButton!

    init(urls: [URL], startIndex: Int) {
        self.urls = urls
        self.startIndex = startIndex
        super.init(nibName: nil, bundle: nil)
        modalPresentationCapturesStatusBarAppearance = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Set initial page offset before the view is on screen to avoid flashing page 0
        if !didSetInitialOffset {
            view.layoutIfNeeded()
            let pageWidth = scrollView.bounds.width
            let x = CGFloat(startIndex) * pageWidth
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
        // Build pages: each page has its own zooming UIScrollView containing an imageView
        pageZoomScrolls.removeAll()
        imageViews.removeAll()

        var previousTrailing: NSLayoutXAxisAnchor = scrollView.leadingAnchor
        for url in urls {
            // Zoom scroll per page
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

            // Image view inside zoom scroll
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFit
            iv.clipsToBounds = true
            iv.translatesAutoresizingMaskIntoConstraints = false
            zsv.addSubview(iv)

            // Constrain to contentLayoutGuide for proper zooming content size
            NSLayoutConstraint.activate([
                iv.topAnchor.constraint(equalTo: zsv.contentLayoutGuide.topAnchor),
                iv.bottomAnchor.constraint(equalTo: zsv.contentLayoutGuide.bottomAnchor),
                iv.leadingAnchor.constraint(equalTo: zsv.contentLayoutGuide.leadingAnchor),
                iv.trailingAnchor.constraint(equalTo: zsv.contentLayoutGuide.trailingAnchor),
                iv.widthAnchor.constraint(equalTo: zsv.frameLayoutGuide.widthAnchor),
                iv.heightAnchor.constraint(equalTo: zsv.frameLayoutGuide.heightAnchor)
            ])

            iv.kf.setImage(with: url, options: [.backgroundDecode, .transition(.none)])

            pageZoomScrolls.append(zsv)
            imageViews.append(iv)
            previousTrailing = zsv.trailingAnchor
        }
        // Finish paging content size
        previousTrailing.constraint(equalTo: scrollView.trailingAnchor).isActive = true
        // Top & Bottom bars (slide-in chrome)
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
        // Page Control (inside bottom bar)
        pageControl = UIPageControl()
        pageControl.numberOfPages = urls.count
        pageControl.currentPage = startIndex
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(pageControl)
        NSLayoutConstraint.activate([
            pageControl.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            pageControl.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor)
        ])
        // Save Button (left of page control)
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
        // Close Button (inside top bar)
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
        // Double-tap to zoom on current page
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.delegate = self
        doubleTap.delaysTouchesBegan = false
        doubleTap.delaysTouchesEnded = false
        view.addGestureRecognizer(doubleTap)

        // Single tap anywhere to toggle chrome (requires double-tap to fail)
        let toggleTap = UITapGestureRecognizer(target: self, action: #selector(handleToggleChrome))
        toggleTap.numberOfTapsRequired = 1
        toggleTap.cancelsTouchesInView = false
        toggleTap.delegate = self
        toggleTap.delaysTouchesBegan = false
        toggleTap.delaysTouchesEnded = false
        toggleTap.require(toFail: doubleTap)
        view.addGestureRecognizer(toggleTap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Initialize bars hidden (slide out) once, based on actual measured sizes
        if !didInitializeChromeTransforms {
            didInitializeChromeTransforms = true
            topBar.transform = CGAffineTransform(translationX: 0, y: -topBar.bounds.height)
            bottomBar.transform = CGAffineTransform(translationX: 0, y: bottomBar.bounds.height)
            topBar.alpha = 0
            bottomBar.alpha = 0
            isChromeVisible = false
        }
    }

    // Remove viewDidAppear offset logic; offset is set in viewWillAppear
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Initial offset has already been set in viewWillAppear.
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === self.scrollView {
            let page = Int(round(scrollView.contentOffset.x / max(1, scrollView.bounds.width)))
            let clamped = min(max(0, page), urls.count - 1)
            pageControl.currentPage = clamped
            if clamped != lastReportedPage {
                // Reset zoom on non-visible pages to avoid carrying zoom state across pages
                for (i, zsv) in pageZoomScrolls.enumerated() where i != clamped {
                    if abs(zsv.zoomScale - 1.0) > 0.001 { zsv.setZoomScale(1.0, animated: false) }
                }
                lastReportedPage = clamped
            }
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        if let idx = pageZoomScrolls.firstIndex(of: scrollView) {
            return imageViews[idx]
        }
        return nil
    }

    // Do not let the fullscreen tap recognizers consume touches inside chrome (top/bottom bars or controls)
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let v = touch.view else { return true }
        // If tapping a UIControl (e.g., UIButton) or within top/bottom bars, let the control receive the touch
        if v is UIControl { return false }
        if (topBar != nil && v.isDescendant(of: topBar)) { return false }
        if (bottomBar != nil && v.isDescendant(of: bottomBar)) { return false }
        return true
    }

    private func currentIndex() -> Int {
        let w = max(1, scrollView.bounds.width)
        let page = Int(round(scrollView.contentOffset.x / w))
        return min(max(0, page), urls.count - 1)
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
        } else { animations() }
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
        } else { animations() }
    }

    @objc private func saveTapped() {
        let idx = currentIndex()
        // 1) If image is already visible in the imageView, prefer that
        if idx < imageViews.count, let image = imageViews[idx].image {
            saveImageToLibrary(image)
            return
        }
        // 2) Otherwise, fetch from Kingfisher cache/network and then save
        let url = urls[idx]
        KingfisherManager.shared.retrieveImage(
            with: url,
            options: [.cacheOriginalImage, .backgroundDecode],
            progressBlock: nil,
            downloadTaskUpdated: nil,
            completionHandler: { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch result {
                    case .success(let value):
                        self.saveImageToLibrary(value.image)
                    case .failure:
                        self.showToast("저장 실패")
                    }
                }
            }
        )
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
                case .authorized, .limited: performSave()
                default: self.showToast("사진 접근 권한이 필요합니다")
                }
            }
        } else {
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized { performSave() }
                else { self.showToast("사진 접근 권한이 필요합니다") }
            }
        }
    }

    @objc private func saveCompletion(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async {
            if error == nil { self.showToast("저장 완료") }
            else { self.showToast("저장 실패") }
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
