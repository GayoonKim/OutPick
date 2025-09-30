//
//  ChatRoomSettingViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit
import Combine
import GRDB
import Kingfisher
import FirebaseFirestore
import FirebaseStorage


class ChatRoomSettingCollectionView: UICollectionViewController, UIGestureRecognizerDelegate, UINavigationControllerDelegate/*, ChatModalAnimatable*/ {
    private lazy var floatingLeaveButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "rectangle.portrait.and.arrow.right")
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        let b = UIButton(configuration: config)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.tintColor = .label // 아이콘만, 배경 없이
        b.accessibilityLabel = "나가기"
        b.addTarget(self, action: #selector(didTapFloatingLeave), for: .touchUpInside)
        return b
    }()

    private lazy var floatingNoticeButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "bell")
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        let b = UIButton(configuration: config)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.tintColor = .label // 아이콘만, 배경 없이
        b.accessibilityLabel = "알림"
        b.addTarget(self, action: #selector(didTapFloatingNotice), for: .touchUpInside)
        return b
    }()
    
    var interactiveTransition: UIPercentDrivenInteractiveTransition?
    
    private var roomInfo: ChatRoom
    private var images: [UIImage]
    private var lastRoomCoverKey: String? = nil
    private var coverPrefetchTask: Task<Void, Never>? = nil
    private var localUsers: [LocalUser] = []
    /// 방 전체 참여자 수 (표시/로딩 판단)
    private var participantsTotalCount: Int = 0
    /// 페이지네이션 상태
    private let participantsPageSize: Int = 50
    private var participantsNextOffset: Int = 0
    private var participantsIsLoading: Bool = false
    private var participantsHasMore: Bool = true
    private var loadedParticipantEmails: Set<String> = []
    /// 끝 근처에서 선로딩을 트리거할 임계값(px)
    private let participantsBottomPrefetchThreshold: CGFloat = 600
    
    private lazy var customNavigationBar: CustomNavigationBarView = {
        let navBar = CustomNavigationBarView()
        navBar.backgroundColor = .clear
        navBar.translatesAutoresizingMaskIntoConstraints = false
        
        return navBar
    }()
    
    enum Section: Int, CaseIterable {
        case roomInfoSection
        case mediaSection
        case participantsSection
    }
    
    enum Item: Hashable {
        case roomInfoItem(ChatRoom)
        case mediaItem([UIImage])
        case participantsItem([LocalUser])
    }
    
    typealias DataSourceType = UICollectionViewDiffableDataSource<Section, Item>
    var dataSource: DataSourceType!
    
    private var cancellables = Set<AnyCancellable>()
    
    var onRoomUpdated: ((ChatRoom) -> Void)?
    
    /// (옵션) 갤러리 오픈을 상위 컨테이너(ChatViewController)로 위임하고 싶을 때 설정
    /// 파라미터로 넘겨지는 VC를 push/present 하는 책임은 호스트가 맡는다.
    var onRequestOpenGallery: ((UIViewController) -> Void)?
    
    init(room: ChatRoom, profiles: [UserProfile], images: [UIImage]) {
        self.roomInfo = room
        self.localUsers = profiles.map { LocalUser(email: $0.email ?? "", nickname: $0.nickname ?? "", profileImagePath: $0.thumbPath) }
        self.images = images
        let layout = Self.configureLayout(self.roomInfo, localUsers: self.localUsers, images: self.images)
        super.init(collectionViewLayout: layout)
        
        Task { @MainActor in
            self.updateMediaSection()
            loadInitialMedia()
            self.loadInitialParticipants()
            self.bindRoomInfoPublisher()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        print("💧 ChatViewController deinit")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = .secondarySystemBackground
        
        configureCollectionView()
        applyInitialSnapshot()
        configureBottomButtons()
    }
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateInsetsForBottomButtons()
    }
    private func configureBottomButtons() {
        let guide = view.safeAreaLayoutGuide
        view.addSubview(floatingLeaveButton)
        view.addSubview(floatingNoticeButton)

        NSLayoutConstraint.activate([
            floatingLeaveButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            floatingLeaveButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12),
            floatingLeaveButton.heightAnchor.constraint(equalToConstant: 44),

            floatingNoticeButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            floatingNoticeButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12),
            floatingNoticeButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        updateInsetsForBottomButtons()
    }

    @objc private func didTapFloatingLeave() {
        leaveRoomTapped()
    }

    @objc private func didTapFloatingNotice() {
        noticeTapped()
    }

    private func updateInsetsForBottomButtons() {
        let buttonHeight: CGFloat = 44
        let verticalMargin: CGFloat = 12
        let safeBottom = view.safeAreaInsets.bottom
        let neededBottom = buttonHeight + verticalMargin * 2 + safeBottom
        collectionView.contentInset.bottom = max(collectionView.contentInset.bottom, neededBottom)
        collectionView.verticalScrollIndicatorInsets.bottom = max(collectionView.verticalScrollIndicatorInsets.bottom, neededBottom)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancellables.removeAll()
        coverPrefetchTask?.cancel()
    }
    
    /// 참여자 Top-50을 우선 로드하고, 총 인원/오프셋 상태를 초기화
    private func loadInitialParticipants() {
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let roomID = self.roomInfo.ID ?? ""
                let (page, total) = try GRDBManager.shared.fetchLocalUsersPage(roomID: roomID,
                                                                               offset: 0,
                                                                               limit: participantsPageSize)
                print(#function, "🔹 로드된 참여자 수: \(page.count), 총 인원: \(total)")
                await MainActor.run {
                    self.participantsTotalCount = total
                    self.participantsNextOffset = page.count
                    self.participantsHasMore = total > page.count
                    self.loadedParticipantEmails = Set(page.map { $0.email })
                    self.localUsers = page
                    self.updateParticipantsSection(with: self.localUsers)
                }
                await self.prefetchProfileAvatars(for: page, topCount: page.count)
            } catch {
                print("❌ 초기 참여자 로드 실패:", error)
            }
        }
    }
    
    /// 아래로 스크롤 시 추가 페이지 로드
    private func loadMoreParticipantsIfNeeded() {
        guard participantsHasMore, !participantsIsLoading else { return }
        participantsIsLoading = true
        let roomID = self.roomInfo.ID ?? ""
        let currentOffset = participantsNextOffset
        Task { [weak self] in
            guard let self = self else { return }
            defer { self.participantsIsLoading = false }
            do {
                let (page, total) = try GRDBManager.shared.fetchLocalUsersPage(roomID: roomID,
                                                                               offset: currentOffset,
                                                                               limit: participantsPageSize)
                // dedupe by email
                let deduped = page.filter { !self.loadedParticipantEmails.contains($0.email) }
                if !deduped.isEmpty {
                    await MainActor.run {
                        self.participantsTotalCount = total
                        self.participantsNextOffset += deduped.count
                        self.participantsHasMore = self.participantsNextOffset < total
                        self.loadedParticipantEmails.formUnion(deduped.map { $0.email })
                        self.localUsers.append(contentsOf: deduped)
                        self.updateParticipantsSection(with: self.localUsers)
                    }
                    await self.prefetchProfileAvatars(for: deduped, topCount: deduped.count)
                } else {
                    await MainActor.run {
                        self.participantsTotalCount = total
                        self.participantsHasMore = self.participantsNextOffset < total
                    }
                }
            } catch {
                print("❌ 참여자 추가 로드 실패:", error)
            }
        }
    }
    
    // MARK: - Media (imageIndex) – Initial load & pagination
    // MARK: Media pagination state (imageIndex-backed)
    private var imageIndexItems: [ImageIndexMeta] = []
    private let mediaPageSize: Int = 60
    private var mediaIsLoading: Bool = false
    private var mediaHasMore: Bool = true
    // Video index items (for pagination anchors)
    private var videoIndexItems: [VideoIndexMeta] = []
    /// 현재 materialized된 썸네일과 1:1로 대응하는 메타 순서(이미지/비디오 혼합)
    private var mediaUnifiedOrder: [MediaThumbMeta] = []

    // Unified lightweight meta for images & videos (for materialization & merge ordering)
    private struct MediaThumbMeta: Hashable {
        let sentAt: Date
        let messageID: String
        let idx: Int
        let thumbKey: String?
        let originalKey: String?
        let thumbURL: String?
        let originalURL: String?
        let localThumb: String?
        let isVideo: Bool
    }
    
    private func loadInitialMedia() {
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let roomID = self.roomInfo.ID ?? ""

                // Fetch first pages for images & videos
                let imageTotal = try GRDBManager.shared.countImageIndex(inRoom: roomID)
                let videoTotal = try GRDBManager.shared.countVideoIndex(inRoom: roomID)
                let imgPage = try GRDBManager.shared.fetchLatestImageIndex(inRoom: roomID, limit: mediaPageSize)
                let vidPage = try GRDBManager.shared.fetchLatestVideoIndex(inRoom: roomID, limit: mediaPageSize)

                self.imageIndexItems = imgPage
                self.videoIndexItems = vidPage
                
                print(#function, "Loaded \(imageTotal) images, \(videoTotal) videos")

                // Merge & cap to page size
                var unified: [MediaThumbMeta] = imgPage.map { m in
                    MediaThumbMeta(sentAt: m.sentAt, messageID: m.messageID, idx: m.idx,
                                   thumbKey: m.thumbKey, originalKey: m.originalKey,
                                   thumbURL: m.thumbURL, originalURL: m.originalURL,
                                   localThumb: m.localThumb, isVideo: false)
                }
                unified.append(contentsOf: vidPage.map { v in
                    MediaThumbMeta(sentAt: v.sentAt, messageID: v.messageID, idx: v.idx,
                                   thumbKey: v.thumbKey, originalKey: v.originalKey,
                                   thumbURL: v.thumbURL, originalURL: v.originalURL,
                                   localThumb: v.localThumb, isVideo: true)
                })
                unified.sort { (a, b) in
                    if a.sentAt != b.sentAt { return a.sentAt > b.sentAt }
                    if a.messageID != b.messageID { return a.messageID > b.messageID }
                    return a.idx < b.idx
                }
                if unified.count > self.mediaPageSize { unified = Array(unified.prefix(self.mediaPageSize)) }
                
                print(#function, "unified: \(unified)")

                let materialized = await self.materializeMediaThumbs(for: unified)
                await MainActor.run {
                    self.mediaUnifiedOrder = unified
                    self.images = materialized
                    // either stream having remainder implies more
                    self.mediaHasMore = (self.imageIndexItems.count < imageTotal) || (self.videoIndexItems.count < videoTotal)
                    self.updateMediaSection()
                }
            } catch {
                print("❌ 초기 미디어 로드 실패:", error)
            }
        }
    }

    private func loadMoreMediaIfNeeded() {
        guard mediaHasMore, !mediaIsLoading else { return }
        mediaIsLoading = true
        let roomID = self.roomInfo.ID ?? ""

        Task { [weak self] in
            guard let self = self else { return }
            defer { self.mediaIsLoading = false }
            do {
                // Anchors for images & videos
                let imgAnchor = self.imageIndexItems.last
                let vidAnchor = self.videoIndexItems.last

                var newImgs: [ImageIndexMeta] = []
                var newVids: [VideoIndexMeta] = []

                if let a = imgAnchor {
                    newImgs = try GRDBManager.shared.fetchOlderImageIndex(
                        inRoom: roomID,
                        beforeSentAt: a.sentAt,
                        beforeMessageID: a.messageID,
                        limit: self.mediaPageSize
                    )
                }
                if let a = vidAnchor {
                    newVids = try GRDBManager.shared.fetchOlderVideoIndex(
                        inRoom: roomID,
                        beforeSentAt: a.sentAt,
                        beforeMessageID: a.messageID,
                        limit: self.mediaPageSize
                    )
                }

                if newImgs.isEmpty && newVids.isEmpty {
                    self.mediaHasMore = false
                    return
                }

                // Dedup across both streams
                var existingKeys = Set(self.imageIndexItems.map { "i:\($0.messageID)#\($0.idx)" })
                existingKeys.formUnion(self.videoIndexItems.map { "v:\($0.messageID)#\($0.idx)" })

                let filteredImgs = newImgs.filter { existingKeys.insert("i:\($0.messageID)#\($0.idx)").inserted }
                let filteredVids = newVids.filter { existingKeys.insert("v:\($0.messageID)#\($0.idx)").inserted }

                self.imageIndexItems.append(contentsOf: filteredImgs)
                self.videoIndexItems.append(contentsOf: filteredVids)

                var unified: [MediaThumbMeta] = filteredImgs.map { m in
                    MediaThumbMeta(sentAt: m.sentAt, messageID: m.messageID, idx: m.idx,
                                   thumbKey: m.thumbKey, originalKey: m.originalKey,
                                   thumbURL: m.thumbURL, originalURL: m.originalURL,
                                   localThumb: m.localThumb, isVideo: false)
                }
                unified.append(contentsOf: filteredVids.map { v in
                    MediaThumbMeta(sentAt: v.sentAt, messageID: v.messageID, idx: v.idx,
                                   thumbKey: v.thumbKey, originalKey: v.originalKey,
                                   thumbURL: v.thumbURL, originalURL: v.originalURL,
                                   localThumb: v.localThumb, isVideo: true)
                })

                guard !unified.isEmpty else { return }

                unified.sort { (a, b) in
                    if a.sentAt != b.sentAt { return a.sentAt > b.sentAt }
                    if a.messageID != b.messageID { return a.messageID > b.messageID }
                    return a.idx < b.idx
                }

                let materialized = await self.materializeMediaThumbs(for: unified)
                await MainActor.run {
                    self.mediaUnifiedOrder.append(contentsOf: unified)
                    self.images.append(contentsOf: materialized)
                    self.updateMediaSection()
                }

                // Recompute hasMore via totals
                do {
                    let imageTotal = try GRDBManager.shared.countImageIndex(inRoom: roomID)
                    let videoTotal = try GRDBManager.shared.countVideoIndex(inRoom: roomID)
                    self.mediaHasMore = (self.imageIndexItems.count < imageTotal) || (self.videoIndexItems.count < videoTotal)
                } catch {
                    self.mediaHasMore = !(filteredImgs.isEmpty && filteredVids.isEmpty)
                }
            } catch {
                print("❌ 미디어 추가 로드 실패:", error)
            }
        }
    }

    /// MediaThumbMeta → UIImage 배열로 소재화 (캐시 우선, 로컬 파일 폴백, URL 최후)
    private func materializeMediaThumbs(for metas: [MediaThumbMeta]) async -> [UIImage] {
        guard !metas.isEmpty else { return [] }
        var result = [UIImage]()
        result.reserveCapacity(metas.count)

        print(#function, "metas.count: \(metas)")
        await withTaskGroup(of: UIImage?.self) { group in
            for meta in metas {
                group.addTask { [isVideo = meta.isVideo, thumbKey = meta.thumbKey ?? meta.thumbURL, originalKey = meta.originalKey ?? meta.originalURL, localThumb = meta.localThumb, thumbURL = meta.thumbURL, originalURL = meta.originalURL] in
                    // 1) 캐시 키 우선
                    
                    if let key = thumbKey {
                        print(#function, "1. thumbKey: \(key)")
                    }
                    if let key = thumbKey, !key.isEmpty, let img = await KingFisherCacheManager.shared.loadImage(named: key) {
                        
                        return await isVideo ? self.drawPlayBadge(on: img) : img
                    }
                    if let key = originalKey, !key.isEmpty, let img = await KingFisherCacheManager.shared.loadImage(named: key) {
                        print(#function, "2. thumbKey: \(thumbKey ?? "nil"), originalKey: \(originalKey ?? "nil")")
                        return await isVideo ? self.drawPlayBadge(on: img) : img
                    }

                    // 2) 로컬 파일(썸네일 경로) 폴백
                    if let local = localThumb, !local.isEmpty {
                        var path = local
                        if local.hasPrefix("file://") { path = URL(string: local)?.path ?? local }
                        if FileManager.default.fileExists(atPath: path), let img = UIImage(contentsOfFile: path) {
                            print(#function, "3. thumbKey: \(thumbKey ?? "nil"), originalKey: \(originalKey ?? "nil")")
                            return await isVideo ? self.drawPlayBadge(on: img) : img
                        }
                    }

                    // 3) URL 최후 폴백 (thumbURL → originalURL)
                    if let urlStr = thumbURL ?? originalURL, let url = URL(string: urlStr) {
                        do {
                            let (data, _) = try await URLSession.shared.data(from: url)
                            if let img = UIImage(data: data) {
                                // 캐시 저장 (키가 있으면 그 키로 저장)
                                if let k = thumbKey ?? originalKey { KingFisherCacheManager.shared.storeImage(img, forKey: k) }
                                print(#function, "4. thumbKey: \(thumbKey ?? "nil"), originalKey: \(originalKey ?? "nil")")
                                return await isVideo ? self.drawPlayBadge(on: img) : img
                            }
                        } catch { return nil }
                    }

                    return nil
                }
            }
            for await img in group { if let img { result.append(img) } }
        }
        for r in result {
            print(#function, "\(#file): \(r)")
        }
        return result
    }

    /// 비디오 썸네일 위에 재생 아이콘을 오버레이 (top-level, thread-safe use)
    private func drawPlayBadge(on image: UIImage) -> UIImage {
        let scale = image.scale
        let size = image.size
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        image.draw(in: CGRect(origin: .zero, size: size))

        let minSide = min(size.width, size.height)
        let circleDiameter = minSide * 0.28
        let circleRect = CGRect(
            x: (size.width - circleDiameter)/2,
            y: (size.height - circleDiameter)/2,
            width: circleDiameter,
            height: circleDiameter
        )

        // 반투명 원 배경
        let circlePath = UIBezierPath(ovalIn: circleRect)
        UIColor.black.withAlphaComponent(0.35).setFill()
        circlePath.fill()

        // 플레이 삼각형
        let triSide = circleDiameter * 0.5
        let triHeight = triSide * sqrt(3)/2
        let center = CGPoint(x: circleRect.midX, y: circleRect.midY)
        let triPath = UIBezierPath()
        triPath.move(to: CGPoint(x: center.x - triSide*0.25, y: center.y - triHeight/2))
        triPath.addLine(to: CGPoint(x: center.x - triSide*0.25, y: center.y + triHeight/2))
        triPath.addLine(to: CGPoint(x: center.x + triSide*0.5,  y: center.y))
        triPath.close()
        UIColor.white.withAlphaComponent(0.9).setFill()
        triPath.fill()

        let composed = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return composed ?? image
    }

    private func bindRoomInfoPublisher() {
        FirebaseManager.shared.roomChangePublisher
            .receive(on: DispatchQueue.main)
            .filter{ [weak self] updatedRoom in
                guard let self = self else { return false }
                
                return updatedRoom.ID == self.roomInfo.ID
            }
            .sink { [weak self] updatedRoom in
                guard let self = self  else { return }
                
                guard self.isViewLoaded, self.view.window != nil else {
                    print("⚠️ UI 없음. 업데이트 무시")
                    return
                }
                
                self.roomInfo = updatedRoom
                self.updateRoomInfoSection()
                
            }
            .store(in: &cancellables)
    }
    
    
    private static func configureLayout(_ room: ChatRoom, localUsers: [LocalUser], images: [UIImage]) -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { (sectionIndex: Int, environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in
            switch Section(rawValue: sectionIndex)! {
                
            case .roomInfoSection:
                
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
                
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                
                return section
                
            case .mediaSection:
                let height: CGFloat = images.count > 0 ? 130 : 44
                
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(height))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(height))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
                
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10)
                
                return section
                
            case .participantsSection:
                let count = localUsers.count
                let rowCount = ceil(Double(count) / 1.0) // 한 줄에 1명 보여주는 구성일 경우
                let itemHeight: CGFloat = 53
                let spacing: CGFloat = 5
                let headerHeight: CGFloat = 40 // "대화상대 (n명)" 라벨
                let showAllButtonHeight: CGFloat = count > 50 ? 44 : 0
                
                let totalHeight = CGFloat(rowCount) * itemHeight +
                CGFloat(max(0, rowCount - 1)) * spacing +
                headerHeight + showAllButtonHeight
                
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(totalHeight))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(totalHeight))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
                
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 16, trailing: 10)
                return section
            }
        }
    }
    
    private func configureDataSource() -> DataSourceType {
        dataSource = DataSourceType(collectionView: collectionView) { (collectionView, indexPath, item) -> UICollectionViewCell? in
            switch item {
            case let .roomInfoItem(room):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatRoomInfoCell.reuseIdentifier, for: indexPath) as! ChatRoomInfoCell
                cell.configureCell(room: room)
                
                cell.editButtonTapped = { [weak self] in
                    guard let self = self else { return }
                    
                    let editVC = RoomEditViewController(room: self.roomInfo)
                    editVC.modalPresentationStyle = .fullScreen
                    
                    editVC.onCompleteEdit = { [weak self] pickedImage, pickedImageData, isRemoved, newName, newDesc in
                        guard let self = self else { return }
                        let updated = try await FirebaseManager.shared.editRoom(
                            room: self.roomInfo,
                            pickedImage: pickedImage,
                            imageData: pickedImageData,
                            isRemoved: isRemoved,
                            newName: newName,
                            newDesc: newDesc
                        )

                        await MainActor.run {
                            // 즉시 로컬 상태 갱신 (퍼블리셔도 발행되지만, 낙관적 UI 업데이트)
                            self.roomInfo = updated
                            self.updateRoomInfoSection()
                        }
                    }
                    
                    self.present(editVC, animated: true, completion: nil)
                }
                
                return cell
                
            case let .mediaItem(images):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatRoomMediaCollectionViewCell.reuseIdentifier, for: indexPath) as! ChatRoomMediaCollectionViewCell
                cell.configureCell(for: images)
                cell.onOpenGallery = { [weak self] in
                    guard let self = self else { return }
                    self.openGallery()
                }
                return cell
                
            case let .participantsItem(localUsers):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ParticipantsSectionParticipantCell.reuseIdentifier, for: indexPath) as! ParticipantsSectionParticipantCell
                cell.configureCell(localUsers)

                return cell
            }
        }
        return dataSource
    }
    
    private func pushOrPresent(_ vc: UIViewController) {
        vc.modalPresentationStyle = .fullScreen
        // 우선 부모가 있으면 부모가 모달 오픈 (child → parent 경유가 안전)
        if let host = self.parent {
            host.present(vc, animated: true)
            return
        }
        // 최후 폴백: 자기 자신에서 present
        self.present(vc, animated: true)
    }

    private func openGallery() {
        let items = buildGalleryItems()
        guard !items.isEmpty else { return }
        print(#function, "items: \(items)")
        let vc = MediaGalleryViewController(items: items)
        vc.modalPresentationStyle = .fullScreen
        pushOrPresent(vc)
    }

    /// 현재 materialize된 썸네일(`images`)과 메타(`mediaUnifiedOrder`)를 1:1 정렬로 묶어 갤러리 아이템을 생성
    private func buildGalleryItems() -> [MediaGalleryViewController.GalleryItem] {
        let count = min(self.images.count, self.mediaUnifiedOrder.count)
        guard count > 0 else { return [] }
        var items: [MediaGalleryViewController.GalleryItem] = []
        items.reserveCapacity(count)
        for i in 0..<count {
            let meta = self.mediaUnifiedOrder[i]
            let img = self.images[i]
            let id = "\(meta.messageID)#\(meta.idx)"
            let urlString = meta.originalURL?.isEmpty == false ? meta.originalURL : meta.thumbURL
            items.append(.init(
                id: id,
                image: img,
                isVideo: meta.isVideo,
                sentAt: meta.sentAt,
                urlString: urlString
            ))
        }
        return items
    }
    
    private func applyInitialSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        
        snapshot.appendSections(Section.allCases)
        snapshot.appendItems([.roomInfoItem(self.roomInfo)], toSection: .roomInfoSection)
        snapshot.appendItems([.mediaItem(self.images)], toSection: .mediaSection)
        snapshot.appendItems([.participantsItem(self.localUsers)], toSection: .participantsSection)
        
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    private func updateRoomInfoSection() {
        // Compute current cover key (thumbPath 우선, 없으면 originalPath)
        let key = self.roomInfo.thumbPath?.isEmpty == false ? self.roomInfo.thumbPath : self.roomInfo.originalPath

        // Helper to perform a light reload of the single item
        func reloadRoomInfoItem() {
            guard let dataSource = self.dataSource else { return }
            var snapshot = dataSource.snapshot()
            let item: Item = .roomInfoItem(self.roomInfo)
            if snapshot.indexOfItem(item) != nil {
                snapshot.reloadItems([item])
            } else {
                snapshot.appendItems([item], toSection: .roomInfoSection)
            }
            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self = self else { return }
                if let indexPath = self.dataSource.indexPath(for: .roomInfoItem(self.roomInfo)),
                   let cell = self.collectionView.cellForItem(at: indexPath) as? ChatRoomInfoCell {
                    cell.configureCell(room: self.roomInfo)
                }
            }
        }

        // If no image key → just reload the item
        guard let key, !key.isEmpty else {
            self.lastRoomCoverKey = nil
            reloadRoomInfoItem()
            return
        }

        // If key unchanged and already cached → just reload
        let cache = KingfisherManager.shared.cache
        if key == lastRoomCoverKey, cache.isCached(forKey: key) {
            reloadRoomInfoItem()
            return
        }

        // Prefetch the cover into cache, then reload
        coverPrefetchTask?.cancel()
        coverPrefetchTask = Task { [weak self] in
            guard let self = self else { return }
            // Early exit if already cached
            if cache.isCached(forKey: key) == false {
                let ref = Storage.storage().reference(withPath: key)
                do {
                    // 3MB limit is enough for a cover thumb
                    let data = try await ref.data(maxSize: 3 * 1024 * 1024)
                    if let img = UIImage(data: data) {
                        KingFisherCacheManager.shared.storeImage(img, forKey: key)
                    }
                } catch {
                    // Best-effort: ignore caching errors and continue to reload
                    print("[RoomInfo] cover prefetch failed: \(error)")
                }
            }
            self.lastRoomCoverKey = key
            await MainActor.run {
                reloadRoomInfoItem()
            }
        }
    }
    
    private func updateMediaSection() {
        guard let dataSource = self.dataSource else {
            print("dataSource가 아직 초기화되지 않았습니다.")
            return
        }
        
        var snapshot = dataSource.snapshot()
        snapshot.deleteItems(snapshot.itemIdentifiers(inSection: .mediaSection))
        snapshot.appendItems([.mediaItem(self.images)], toSection: .mediaSection)
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self = self else { return }
            
            self.collectionView.setCollectionViewLayout(Self.configureLayout(self.roomInfo, localUsers: self.localUsers, images: self.images), animated: false)
            if let indexPath = self.dataSource.indexPath(for: .mediaItem(self.images)),
               let cell = self.collectionView.cellForItem(at: indexPath) as? ChatRoomMediaCollectionViewCell {
                cell.configureCell(for: images)
            }
        }
    }
    
    @MainActor
    private func updateParticipantsSection(with localUsers: [LocalUser]) {
        var snapshot = dataSource.snapshot()
        snapshot.deleteItems(snapshot.itemIdentifiers(inSection: .participantsSection))
        snapshot.appendItems([.participantsItem(localUsers)], toSection: .participantsSection)
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self = self else { return }
            self.collectionView.setCollectionViewLayout(Self.configureLayout(self.roomInfo, localUsers: localUsers, images: self.images), animated: false)
            if let indexPath = self.dataSource.indexPath(for: .participantsItem(localUsers)),
               let cell = self.collectionView.cellForItem(at: indexPath) as? ParticipantsSectionParticipantCell {
                cell.configureCell(localUsers)
            }
        }
    }
    
    private func leaveRoomTapped() {
        print("🚪 나가기 버튼 탭됨")
        // TODO: 실제 방 나가기 로직 연결 (확인 다이얼로그 → 서버/로컬 상태 정리)
        
        ConfirmView.presentLeave(in: self.view) { [weak self] in
            guard let self = self else { return }
            // TODO: 실제 '나가기' 처리 로직 연결
            print("✅ 나가기 확정")
            
            if self.roomInfo.creatorID == LoginManager.shared.getUserEmail {
                // Storage: Room_Images/imagePath 삭제
                // Storage: rooms/roomID 삭제
                // Storage: videos/roomID 삭제
                // Users/email/joinedRooms에서 roomID 삭제
                // Rooms/roomID 삭제
            } else {
                // Users/email/joinedRooms에서 roomID 삭제
            }
            
            self.dismiss(animated: false, completion: {
                self.navigationController?.popViewController(animated: false)
            })
        }
    }

    private func noticeTapped() {
        print("🔔 알림 버튼 탭됨")
        // TODO: 알림 설정 화면/토글 연결
    }

    private func configureCollectionView() {
        collectionView.backgroundColor = .secondarySystemBackground
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(ChatRoomInfoCell.self, forCellWithReuseIdentifier: ChatRoomInfoCell.reuseIdentifier)
        collectionView.register(ChatRoomMediaCollectionViewCell.self, forCellWithReuseIdentifier: ChatRoomMediaCollectionViewCell.reuseIdentifier)
        collectionView.register(ParticipantsSectionParticipantCell.self, forCellWithReuseIdentifier: ParticipantsSectionParticipantCell.reuseIdentifier)
        dataSource = configureDataSource()
        collectionView.dataSource = dataSource
    }

    // MARK: - Pagination Trigger via willDisplay (no scrollViewDidScroll)
    override func collectionView(_ collectionView: UICollectionView,
                                 willDisplay cell: UICollectionViewCell,
                                 forItemAt indexPath: IndexPath) {
        // 하단 근접 감지: 셀이 표시되기 직전에 한 번씩만 체크
        let distanceToBottom = collectionView.contentSize.height - collectionView.contentOffset.y - collectionView.bounds.height
        if participantsHasMore && !participantsIsLoading && distanceToBottom < participantsBottomPrefetchThreshold {
            loadMoreParticipantsIfNeeded()
        }
        
        // 보수적으로: 참가자 섹션 셀(마지막 섹션)이 표시될 때도 한번 더 체크
        if let section = Section(rawValue: indexPath.section), section == .participantsSection {
            if participantsHasMore && !participantsIsLoading {
                loadMoreParticipantsIfNeeded()
            }
        }
        
        // 미디어 섹션 하단 근접 시 추가 로드
        if let section = Section(rawValue: indexPath.section), section == .mediaSection {
            if mediaHasMore && !mediaIsLoading {
                let distanceToBottom = collectionView.contentSize.height
                                     - collectionView.contentOffset.y
                                     - collectionView.bounds.height
                if distanceToBottom < participantsBottomPrefetchThreshold {
                    loadMoreMediaIfNeeded()
                }
            }
        }
    }

    /// 닉네임 정렬 기준 Top-N 사용자 아바타를 선행 캐시 (디스크)
    /// ChatViewController에 동일 기능이 있지만, 이 뷰에서도 독립적으로 사용할 수 있도록 경량 구현을 둡니다.
    private func prefetchProfileAvatars(for users: [LocalUser], topCount: Int = 50) async {
        guard !users.isEmpty else { return }
        
        // 1) 닉네임 오름차순 정렬 → Top-N
        let sorted = users.sorted { $0.nickname.localizedCaseInsensitiveCompare($1.nickname) == .orderedAscending }
        let slice = sorted.prefix(min(topCount, sorted.count))
        
        // 2) Firebase Storage에서 이미지 데이터를 받아 Kingfisher 디스크 캐시에 저장
        await withTaskGroup(of: Void.self) { group in
            for u in slice {
                guard let path = u.profileImagePath, !path.isEmpty else { continue }
                let key = path
                
                // 이미 캐시되어 있으면 스킵
                let cache = KingfisherManager.shared.cache
                if cache.isCached(forKey: key) {
                    continue
                }
                
                group.addTask {
                    let ref = Storage.storage().reference(withPath: path)
                    do {
                        // 최대 3MB 제한 (아바타 용도로 충분)
                        let data = try await ref.data(maxSize: 3 * 1024 * 1024)
                        if let img = UIImage(data: data) {
                            KingFisherCacheManager.shared.storeImage(img, forKey: key)
                        }
                    } catch {
                        print("👤 아바타 프리패치 실패(\(u.email)):", error)
                    }
                }
            }
            await group.waitForAll()
        }
    }
}
