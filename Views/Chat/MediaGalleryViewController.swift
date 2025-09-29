//
//  MediaGalleryViewController.swift
//  OutPick
//
//  Created by 김가윤 on 9/28/25.
//

import UIKit
import Photos
import AVKit
import FirebaseStorage

// MARK: - Media Gallery
class MediaGalleryViewController: UICollectionViewController {
    struct GalleryItem: Hashable {
        let id: String
        let image: UIImage
        let isVideo: Bool
        let sentAt: Date
        let urlString: String?   // 원본(우선) 또는 썸네일 URL 문자열
    }
    
    private enum Section: Hashable { case day(Date) }
    private enum Item: Hashable { case thumb(GalleryItem) }

    private typealias DS = UICollectionViewDiffableDataSource<Section, Item>
    private var dataSource: DS!
    // Top bar (center title + close button)
    private let topBar = UIView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    /// (옵션) Firebase Storage 경로("rooms/.../file") → 다운로드 URL로 해석하는 비동기 해결기 주입 지점
    /// 주입이 없으면 내부에서 FirebaseStorage.downloadURL()을 사용
    var downloadURLResolver: ((String) async throws -> URL)?

    init(items: [GalleryItem]) {
        self.items = items
        let layout = MediaGalleryViewController.makeLayout()
        super.init(collectionViewLayout: layout)
        self.title = "미디어"
        configureDataSource()
        collectionView.backgroundColor = .systemBackground
        collectionView.register(GalleryThumbCell.self, forCellWithReuseIdentifier: GalleryThumbCell.reuseID)
        collectionView.register(GalleryHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: GalleryHeaderView.reuseID)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTopBar()
    }

    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1/3), heightDimension: .fractionalWidth(1/3))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = NSDirectionalEdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(300))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item, item, item])

        let section = NSCollectionLayoutSection(group: group)
        let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(36))
        let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize,
                                                                 elementKind: UICollectionView.elementKindSectionHeader,
                                                                 alignment: .top)
        section.boundarySupplementaryItems = [header]
        return UICollectionViewCompositionalLayout(section: section)
    }

    private func setupTopBar() {
        // Bar appearance
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.backgroundColor = .systemBackground
        view.addSubview(topBar)

        // Title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "미디어"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label
        topBar.addSubview(titleLabel)

        // Close button
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: cfg), for: .normal)
        closeButton.tintColor = .label
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        // Larger hit area
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        topBar.addSubview(closeButton)

        // Bottom separator
        let sep = UIView()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.backgroundColor = .separator
        topBar.addSubview(sep)

        // Layout
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: guide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            closeButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),

            sep.heightAnchor.constraint(equalToConstant: 0.5),
            sep.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: topBar.bottomAnchor)
        ])

        // Ensure content isn't hidden under the bar
        collectionView.contentInset.top += 44
        collectionView.scrollIndicatorInsets.top += 44
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func configureDataSource() {
        let calendar = Calendar.current
        var byDay: [Date: [GalleryItem]] = [:]
        for i in self.items {
            let day = calendar.startOfDay(for: i.sentAt)
            byDay[day, default: []].append(i)
        }
        let sortedDays = byDay.keys.sorted(by: { $0 > $1 })

        dataSource = DS(collectionView: collectionView) { (cv, indexPath, item) -> UICollectionViewCell? in
            switch item {
            case let .thumb(g):
                let cell = cv.dequeueReusableCell(withReuseIdentifier: GalleryThumbCell.reuseID, for: indexPath) as! GalleryThumbCell
                cell.configure(image: g.image, isVideo: g.isVideo)
                return cell
            }
        }
        dataSource.supplementaryViewProvider = { [weak self] (cv, kind, indexPath) in
            guard kind == UICollectionView.elementKindSectionHeader else { return nil }
            let view = cv.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: GalleryHeaderView.reuseID, for: indexPath) as! GalleryHeaderView
            if let section = self?.dataSource.snapshot().sectionIdentifiers[indexPath.section] {
                switch section {
                case let .day(d):
                    view.configure(date: d)
                }
            }
            return view
        }

        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        for d in sortedDays {
            snap.appendSections([.day(d)])
            let itemsForDay = (byDay[d] ?? []).map { Item.thumb($0) }
            snap.appendItems(itemsForDay, toSection: .day(d))
        }
        dataSource.apply(snap, animatingDifferences: false)

    }
    private let items: [GalleryItem]
}

final class GalleryThumbCell: UICollectionViewCell {
    static let reuseID = "GalleryThumbCell"
    private let imageView = UIImageView()
    private let playBadge = UIImageView(image: UIImage(systemName: "play.fill"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])

        playBadge.translatesAutoresizingMaskIntoConstraints = false
        playBadge.tintColor = .white
        playBadge.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        playBadge.layer.cornerRadius = 14
        playBadge.clipsToBounds = true
        playBadge.isHidden = true
        contentView.addSubview(playBadge)
        NSLayoutConstraint.activate([
            playBadge.widthAnchor.constraint(equalToConstant: 28),
            playBadge.heightAnchor.constraint(equalToConstant: 28),
            playBadge.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            playBadge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(image: UIImage, isVideo: Bool) {
        imageView.image = image
        playBadge.isHidden = !isVideo
    }
}

final class GalleryHeaderView: UICollectionReusableView {
    static let reuseID = "GalleryHeaderView"
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .secondaryLabel
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(date: Date) {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.timeZone = TimeZone(identifier: "Asia/Seoul")
        df.dateFormat = "yyyy.MM.dd (E)"
        label.text = df.string(from: date)
    }
}

extension MediaGalleryViewController {
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        guard case let .thumb(g) = item else { return }

        Task { [weak self] in
            guard let self = self else { return }
            if g.isVideo {
                if let s = g.urlString, let url = await self.resolveURL(from: s) {
                    await MainActor.run {
                        let pvc = VideoPlayerOverlayVC(url: url)
                        pvc.modalPresentationStyle = .fullScreen
                        self.present(pvc, animated: true)
                    }
                } else {
                    await MainActor.run {
                        let alert = UIAlertController(title: "재생할 수 없음",
                                                      message: "이 동영상의 경로를 다운로드 URL로 변환할 수 없습니다.",
                                                      preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "확인", style: .default))
                        self.present(alert, animated: true)
                    }
                }
                return
            }

            // 이미지
            if let s = g.urlString, let url = await self.resolveURL(from: s) {
                await MainActor.run {
                    let viewer = SimpleImageViewerVC(urls: [url], startIndex: 0)
                    viewer.modalPresentationCapturesStatusBarAppearance = true
                    viewer.modalPresentationStyle = .fullScreen
                    self.present(viewer, animated: true)
                }
            } else {
                await MainActor.run {
                    let local = LocalImageViewerVC(image: g.image)
                    local.modalPresentationCapturesStatusBarAppearance = true
                    local.modalPresentationStyle = .fullScreen
                    self.present(local, animated: true)
                }
            }
        }
    }

    private func resolveURL(from s: String) async -> URL? {
        // 이미 http/https/file 이면 그대로 사용
        if let u = URL(string: s), let scheme = u.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) {
            return u
        }
        // 외부 주입 해결기 우선 사용
        if let resolver = downloadURLResolver {
            return try? await resolver(s)
        }
        // 폴백: Firebase Storage 경로라 가정하고 downloadURL 호출
        do { return try await storageDownloadURL(forPath: s) } catch { return nil }
    }

    private func storageDownloadURL(forPath path: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            Storage.storage().reference(withPath: path).downloadURL { url, err in
                if let url = url { cont.resume(returning: url) }
                else { cont.resume(throwing: err ?? URLError(.badURL)) }
            }
        }
    }
}

// MARK: - Local single image viewer (fallback)
final class LocalImageViewerVC: UIViewController, UIScrollViewDelegate {
    private let image: UIImage
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let closeButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)

    init(image: UIImage) {
        self.image = image
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
            // Scroll view fills the screen
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // Image view defines the content size via intrinsicContentSize (image size) and pins to contentLayoutGuide
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor)
        ])

        // 더블탭 1x↔2x 토글 줌 (핀치와 공존)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 1
        doubleTap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(doubleTap)

        // 상단 우측 닫기(X) 버튼
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        let xcfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: xcfg), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        closeButton.layer.cornerRadius = 18
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        // 하단 좌측 저장 버튼
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        let scfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        saveButton.setImage(UIImage(systemName: "square.and.arrow.down", withConfiguration: scfg), for: .normal)
        saveButton.setTitle("  저장", for: .normal)
        saveButton.tintColor = .white
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        saveButton.layer.cornerRadius = 18
        saveButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
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
        let tapPoint = gr.location(in: imageView) // rect 좌표는 zoom 대상(viewForZooming)의 좌표계 기준
        let minScale = scrollView.minimumZoomScale
//        let maxScale: CGFloat = max(2.0, min(scrollView.maximumZoomScale, 2.0)) // 목표 스케일 2x (최대치와 조화)

        let isAtMin = abs(scrollView.zoomScale - minScale) < 0.01
        if isAtMin {
            // 1x → 2x (탭 지점 중심으로)
            zoom(to: tapPoint, scale: min(2.0, scrollView.maximumZoomScale), animated: true)
        } else {
            // 그 외 → 1x로 복귀
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
        saveImageToPhotos(image)
    }

    private func saveImageToPhotos(_ image: UIImage) {
        // iOS 14+: addOnly 권한 요청이 가능. 하위버전은 일반 권한 요청.
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
                self?.handlePhotoAuthAndSave(status: status, image: image)
            }
        } else {
            PHPhotoLibrary.requestAuthorization { [weak self] status in
                self?.handlePhotoAuthAndSave(status: status, image: image)
            }
        }
    }

    private func handlePhotoAuthAndSave(status: PHAuthorizationStatus, image: UIImage) {
        let canSave: Bool
        if #available(iOS 14, *) {
            // iOS 14+: .authorized 또는 .limited 면 저장 가능
            canSave = (status == .authorized || status == .limited)
        } else {
            // iOS 13 이하: .authorized 만 허용
            canSave = (status == .authorized)
        }
        guard canSave else {
            DispatchQueue.main.async { [weak self] in
                self?.showToast("사진 보관함 접근 권한이 필요합니다")
            }
            return
        }

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.showToast("저장 완료")
                } else {
                    self?.showToast("저장 실패: \(error?.localizedDescription ?? "알 수 없는 오류")")
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

        // 자동 제거 애니메이션
        label.alpha = 0
        UIView.animate(withDuration: 0.2, animations: { label.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.2, delay: 1.2, options: [], animations: { label.alpha = 0 }) { _ in
                label.removeFromSuperview()
            }
        }
    }
    
    // LocalImageViewerVC 안에 추가
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

// MARK: - Video player with bottom-left Save button
final class VideoPlayerOverlayVC: UIViewController {
    private let url: URL
    private let playerVC = AVPlayerViewController()
    private let closeButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
        modalPresentationCapturesStatusBarAppearance = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Embed AVPlayerViewController
        addChild(playerVC)
        view.addSubview(playerVC.view)
        playerVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playerVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            playerVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            playerVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        playerVC.didMove(toParent: self)
        playerVC.player = AVPlayer(url: url)
        playerVC.showsPlaybackControls = true

        // Close (X) button — top-right
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        let xcfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: xcfg), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        closeButton.layer.cornerRadius = 18
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        // Save button — bottom-left
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        let scfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        saveButton.setImage(UIImage(systemName: "square.and.arrow.down", withConfiguration: scfg), for: .normal)
        saveButton.setTitle("  저장", for: .normal)
        saveButton.tintColor = .white
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        saveButton.layer.cornerRadius = 18
        saveButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        playerVC.player?.play()
    }

    @objc private func closeTapped() {
        playerVC.player?.pause()
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.saveVideoToPhotos(from: self.url)
                await MainActor.run { self.showToast("저장 완료") }
            } catch {
                await MainActor.run { self.showToast("저장 실패: \(error.localizedDescription)") }
            }
        }
    }

    // MARK: Saving helpers
    private func saveVideoToPhotos(from url: URL) async throws {
        let canSave = await requestPhotoAddPermission()
        guard canSave else { throw SaveError.permissionDenied }

        let fileURL: URL
        if url.isFileURL {
            fileURL = url
        } else {
            fileURL = try await downloadToTemporaryFile(from: url)
        }

        try await withCheckedThrowingContinuation { cont in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }, completionHandler: { success, error in
                if success { cont.resume(returning: ()) }
                else { cont.resume(throwing: error ?? SaveError.unknown) }
            })
        }
    }

    private func requestPhotoAddPermission() async -> Bool {
        if #available(iOS 14, *) {
            let status = await withCheckedContinuation { (cont: CheckedContinuation<PHAuthorizationStatus, Never>) in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { s in cont.resume(returning: s) }
            }
            return status == .authorized || status == .limited
        } else {
            let status = await withCheckedContinuation { (cont: CheckedContinuation<PHAuthorizationStatus, Never>) in
                PHPhotoLibrary.requestAuthorization { s in cont.resume(returning: s) }
            }
            return status == .authorized
        }
    }

    private func downloadToTemporaryFile(from url: URL) async throws -> URL {
        let (tmpURL, _) = try await URLSession.shared.download(from: url)
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmpURL, to: dest)
        return dest
    }

    // MARK: Toast
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

    enum SaveError: Error { case permissionDenied, unknown }
}
