//
//  LocalImageViewerVC.swift
//  OutPick
//
//  Created by Codex on 6/24/26.
//

import UIKit

// 원격 path가 없는 메모리 UIImage 전용 fallback viewer.
final class LocalImageViewerVC: UIViewController, UIScrollViewDelegate {
    private let image: UIImage
    private let photoLibrarySaver: PhotoLibrarySaving
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let closeButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)

    init(
        image: UIImage,
        photoLibrarySaver: PhotoLibrarySaving
    ) {
        self.image = image
        self.photoLibrarySaver = photoLibrarySaver
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        view.addSubview(scrollView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.image = image
        scrollView.addSubview(imageView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor)
        ])

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 1
        doubleTap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(doubleTap)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        let xcfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        var closeConfiguration = UIButton.Configuration.plain()
        closeConfiguration.image = UIImage(systemName: "xmark", withConfiguration: xcfg)
        closeConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        closeButton.configuration = closeConfiguration
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        closeButton.layer.cornerRadius = 18
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        saveButton.translatesAutoresizingMaskIntoConstraints = false
        let scfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        var saveConfiguration = UIButton.Configuration.plain()
        saveConfiguration.image = UIImage(systemName: "square.and.arrow.down", withConfiguration: scfg)
        saveConfiguration.title = "저장"
        saveConfiguration.imagePadding = 8
        saveConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        saveButton.configuration = saveConfiguration
        saveButton.tintColor = .white
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        saveButton.layer.cornerRadius = 18
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        view.addSubview(saveButton)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -12),

            saveButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 12),
            saveButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -20)
        ])
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    @objc private func handleDoubleTap(_ gr: UITapGestureRecognizer) {
        let tapPoint = gr.location(in: imageView)
        let minScale = scrollView.minimumZoomScale

        let isAtMin = abs(scrollView.zoomScale - minScale) < 0.01
        if isAtMin {
            zoom(to: tapPoint, scale: min(2.0, scrollView.maximumZoomScale), animated: true)
        } else {
            scrollView.setZoomScale(minScale, animated: true)
        }
    }

    private func zoom(to pointInImageView: CGPoint, scale: CGFloat, animated: Bool) {
        let size = scrollView.bounds.size
        let w = size.width / scale
        let h = size.height / scale
        let x = pointInImageView.x - (w / 2.0)
        let y = pointInImageView.y - (h / 2.0)
        let rect = CGRect(x: x, y: y, width: w, height: h)
        scrollView.zoom(to: rect, animated: animated)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.photoLibrarySaver.saveImage(self.image)
                await MainActor.run {
                    self.showToast("저장 완료")
                }
            } catch {
                await MainActor.run {
                    self.showToast("저장 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    private func showToast(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -40),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -24)
        ])

        label.alpha = 0
        UIView.animate(withDuration: 0.2, animations: { label.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.2, delay: 1.2, options: [], animations: { label.alpha = 0 }) { _ in
                label.removeFromSuperview()
            }
        }
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        centerContent()
    }

    private func centerContent() {
        let boundsSize = scrollView.bounds.size
        let contentSize = scrollView.contentSize
        let horizontalInset = max(0, (boundsSize.width - contentSize.width) / 2)
        let verticalInset = max(0, (boundsSize.height - contentSize.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
    }
}
