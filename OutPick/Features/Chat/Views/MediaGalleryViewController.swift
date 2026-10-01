//
//  MediaGalleryViewController.swift
//  OutPick
//
//  Created by 김가윤 on 9/28/25.
//

import UIKit

// MARK: - Media Gallery
class MediaGalleryViewController: UICollectionViewController {
    struct GalleryItem: Hashable {
        let id: String
        let image: UIImage
        let isVideo: Bool
        let sentAt: Date
        let thumbnailPath: String?
        let originalPath: String?
        let videoPath: String?
        let generationThumb: String?
        let generationOriginal: String?
        let mediaExpiresAt: Date?
        var playbackResource: ChatVideoPlaybackResource? = nil

        var isExpired: Bool {
            guard let mediaExpiresAt else { return true }
            return ChatMediaExpiryPolicy.isExpired(mediaExpiresAt, now: Date())
        }
    }
    
    private enum Section: Hashable { case day(Date) }
    private enum Item: Hashable { case thumb(GalleryItem) }

    private typealias DS = UICollectionViewDiffableDataSource<Section, Item>
    private var dataSource: DS!
    // Top bar (center title + close button)
    private let topBar = UIView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    var cachedImageProvider: ((ChatMediaCacheResource) async -> UIImage?)?
    var loadImageProvider: ((ChatMediaCacheResource, Int) async -> UIImage?)?
    private let photoLibrarySaver: PhotoLibrarySaving
    private let videoResolver: ChatVideoPlaybackResolving
    private let originalFiles: (any ChatOriginalFileLoading)?
    private var items: [GalleryItem]
    private var expiryTimer: Timer?

    init(
        items: [GalleryItem],
        photoLibrarySaver: PhotoLibrarySaving,
        videoResolver: ChatVideoPlaybackResolving,
        originalFiles: (any ChatOriginalFileLoading)? = nil
    ) {
        self.items = Self.uniqueItems(items.filter { !$0.isExpired })
        self.photoLibrarySaver = photoLibrarySaver
        self.videoResolver = videoResolver
        self.originalFiles = originalFiles
        let layout = MediaGalleryViewController.makeLayout()
        super.init(collectionViewLayout: layout)
        self.title = "미디어"
        configureDataSource()
        collectionView.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        collectionView.register(GalleryThumbCell.self, forCellWithReuseIdentifier: GalleryThumbCell.reuseID)
        collectionView.register(GalleryHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: GalleryHeaderView.reuseID)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTopBar()
        scheduleExpiryTimer()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        removeExpiredItems()
        scheduleExpiryTimer()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        expiryTimer?.invalidate()
        expiryTimer = nil
    }

    deinit {
        expiryTimer?.invalidate()
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
        topBar.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        view.addSubview(topBar)

        // Title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "미디어"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = OutPickTheme.ColorToken.textPrimary
        topBar.addSubview(titleLabel)

        // Close button
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        var closeConfiguration = UIButton.Configuration.plain()
        closeConfiguration.image = UIImage(systemName: "xmark", withConfiguration: cfg)
        closeConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        closeButton.configuration = closeConfiguration
        closeButton.tintColor = OutPickTheme.ColorToken.accent
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        topBar.addSubview(closeButton)

        // Bottom separator
        let sep = UIView()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.backgroundColor = OutPickTheme.ColorToken.borderSubtle
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
        collectionView.verticalScrollIndicatorInsets.top += 44
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
                guard !g.isExpired else { return nil }
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
    private static func uniqueItems(_ items: [GalleryItem]) -> [GalleryItem] {
        var knownIDs = Set<String>()
        var knownContentKeys = Set<String>()

        return items.filter { item in
            guard knownIDs.insert(item.id).inserted else { return false }

            let mediaKind = item.isVideo ? "video" : "image"
            let paths = [item.videoPath, item.originalPath, item.thumbnailPath]
            let contentKeys = Set(paths.compactMap { canonicalPath($0) }.map { "\(mediaKind)#path:\($0)" })
            if !contentKeys.isEmpty {
                guard knownContentKeys.isDisjoint(with: contentKeys) else { return false }
                knownContentKeys.formUnion(contentKeys)
            }

            return true
        }
    }

    private func removeExpiredItems() {
        let validItems = items.filter { !$0.isExpired }
        guard validItems.count != items.count else { return }
        items = validItems
        configureDataSource()
    }

    private func scheduleExpiryTimer() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        guard isViewLoaded, view.window != nil,
              let expiry = items.compactMap(\.mediaExpiresAt).filter({ $0 > Date() }).min() else { return }
        expiryTimer = Timer.scheduledTimer(withTimeInterval: max(0.01, expiry.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            guard let self else { return }
            self.removeExpiredItems()
            self.scheduleExpiryTimer()
        }
        if let expiryTimer { RunLoop.main.add(expiryTimer, forMode: .common) }
    }

    private static func canonicalPath(_ path: String?) -> String? {
        guard let rawPath = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else { return nil }

        if rawPath.hasPrefix("file://"),
           let url = URL(string: rawPath),
           url.isFileURL {
            return url.standardizedFileURL.path
        }

        if rawPath.hasPrefix("/") {
            return URL(fileURLWithPath: rawPath).standardizedFileURL.path
        }

        return rawPath
    }
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
        label.textColor = OutPickTheme.ColorToken.textSecondary
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
        guard !g.isExpired else { removeExpiredItems(); return }

        Task { [weak self] in
            guard let self = self else { return }
            if g.isVideo {
                if let resource = g.playbackResource {
                    do {
                        let playbackAsset = try await self.videoResolver.playbackAsset(for: resource, forceRefresh: false)
                        guard !g.isExpired, self.videoResolver.isSessionValid, self.viewIfLoaded?.window != nil,
                              self.presentedViewController == nil else {
                            await playbackAsset.fileLease?.release()
                            self.removeExpiredItems()
                            return
                        }
                        await MainActor.run {
                            guard !g.isExpired else { self.removeExpiredItems(); return }
                            let pvc = VideoPlayerOverlayVC(
                                playbackAsset: playbackAsset,
                                videoResolver: self.videoResolver,
                                photoLibrarySaver: self.photoLibrarySaver
                            )
                            pvc.modalPresentationStyle = .fullScreen
                            self.present(pvc, animated: true)
                        }
                    } catch {
                        await MainActor.run {
                            let alert = UIAlertController(title: "재생할 수 없음",
                                                          message: (error as? ChatVideoPlaybackError)?.errorDescription ?? "동영상을 불러오지 못했습니다.",
                                                          preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "확인", style: .default))
                            self.present(alert, animated: true)
                        }
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

            let thumbnailPath = g.thumbnailPath
            let originalPath = self.originalFiles == nil ? (g.originalPath ?? g.thumbnailPath) : g.originalPath
            await MainActor.run {
                let page = ImageViewerPage(
                    initialImage: g.image,
                    thumbnailPath: thumbnailPath,
                    originalPath: originalPath,
                    isAnimated: URL(string: originalPath ?? "")?.pathExtension.lowercased() == "gif",
                    generationThumb: g.generationThumb,
                    generationOriginal: g.generationOriginal,
                    mediaExpiresAt: g.mediaExpiresAt
                )
                let viewer = SimpleImageViewerVC(
                    pages: [page],
                    startIndex: 0,
                    cachedImageProvider: { [weak self] path in
                        guard let self else { return nil }
                        return await self.cachedImageProvider?(Self.cacheResource(path: path, item: g))
                    },
                    loadImageProvider: { [weak self] path, maxBytes in
                        guard let self else { return nil }
                        return await self.loadImageProvider?(Self.cacheResource(path: path, item: g), maxBytes)
                    },
                    photoLibrarySaver: self.photoLibrarySaver,
                    originalFiles: self.originalFiles
                )
                viewer.modalPresentationCapturesStatusBarAppearance = true
                viewer.modalPresentationStyle = .fullScreen
                self.present(viewer, animated: true)
            }
        }
    }

    private static func cacheResource(path: String, item: GalleryItem) -> ChatMediaCacheResource {
        let generation = path == item.originalPath ? item.generationOriginal : item.generationThumb
        return .attachment(path: path, generation: generation, mediaExpiresAt: item.mediaExpiresAt)
    }
}
