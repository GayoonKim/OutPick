//
//  JoinedRoomViewController.swift
//  OutPick
//
//  Created by 김가윤 on 9/28/25.
//

import UIKit
import FirebaseFirestore
import Combine

class JoinedRoomsViewController: UIViewController, ChatModalAnimatable {
    
    private lazy var customNavigationBar: CustomNavigationBarView = {
        let navBar = CustomNavigationBarView()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        
        return navBar
    }()
    
    private let joinedRoomListCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        let collectionV = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionV.backgroundColor = .systemBackground
        collectionV.alwaysBounceVertical = true
        collectionV.keyboardDismissMode = .onDrag
        collectionV.register(JoinedRoomCell.self, forCellWithReuseIdentifier: JoinedRoomCell.reuseID)
        
        return collectionV
    }()
    
    private var currentJoined: Set<String> = []
    // roomID → unread count
    private var unreadCounts: [String: Int64] = [:]
    
    var roomImages: [String:UIImage] = [:]
    private var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupViews()
        configureDataSource()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setjoinedRooms()
        bindRoomChangePublisher()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancellables.removeAll()
    }
    
    @MainActor
    private func refreshRoomCell(id: String) {
        var snapshot = dataSource.snapshot()
        guard let item = snapshot.itemIdentifiers.first(where: { $0.ID == id }) else { return }
        snapshot.reconfigureItems([item])
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func bindRoomChangePublisher() {
        // 실시간 방 업데이트 관련
        FirebaseManager.shared.roomChangePublisher
            .removeDuplicates(by: { lhs, rhs in
              lhs.ID == rhs.ID && lhs.seq == rhs.seq  // (예시) 같은 방 & 같은 최신 seq면 중복으로 간주
            })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedRoom in
                guard let self = self else { return }
                Task { @MainActor in
                    self.applyIncrementalRoomUpdate(updatedRoom)
                }
            }
            .store(in: &cancellables)

        Task { [weak self] in
            guard let self = self else { return }
            // actor hop로 publisher를 안전하게 가져옴
            let pub = await FirebaseManager.shared.joinedRoomStore.publisher
            // 구독/보관은 MainActor에서 안전하게 수행
            await MainActor.run {
                pub
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] joined in
                        guard let self = self else { return }
                        self.currentJoined = joined
                    }
                    .store(in: &self.cancellables)
            }
        }
    }
    
    /// 방 정보(old → new) 변경점을 비교하고 필요한 UI/동기화만 수행
    @MainActor
    func applyIncrementalRoomUpdate(_ updated: ChatRoom) {
        guard let id = updated.ID else { return }
        var snapshot = dataSource.snapshot()

        if !snapshot.itemIdentifiers.contains(where: { $0.ID == id }) {
            // 새로 참여(추가)
            snapshot.appendItems([updated], toSection: Section.main)
            dataSource.apply(snapshot, animatingDifferences: true)
            // 새 방도 미읽음 계산 시작
            Task { await self.updateUnread(for: id, lastMessageSeqHint: updated.seq) }
            return
        }

        // 1) 기존 아이템 제거
        guard let old = snapshot.itemIdentifiers.first(where: { $0.ID == id }) else { return }
        snapshot.deleteItems([old])

        // 2) 업데이트된 아이템을 '정렬 기준'에 맞춰 올바른 위치에 삽입
        //    현재 스냅샷(= old 제거된 상태)의 아이템 + updated 로 정렬 배열 만들기
        var itemsForOrder = snapshot.itemIdentifiers
        itemsForOrder.append(updated)
        let ordered = itemsForOrder.sorted {
            ($0.lastMessageAt ?? $0.createdAt) > ($1.lastMessageAt ?? $1.createdAt)
        }

        // updated의 올바른 위치를 찾아 삽입
        if let pos = ordered.firstIndex(where: { $0.ID == id }) {
            if pos < ordered.count - 1 {
                let next = ordered[pos + 1]
                snapshot.insertItems([updated], beforeItem: next)
            } else {
                snapshot.appendItems([updated], toSection: .main)
            }
        } else {
            // 안전망: 못 찾으면 맨 앞에 추가
            snapshot.insertItems([updated], beforeItem: snapshot.itemIdentifiers.first!)
        }

        // 3) 적용
        dataSource.apply(snapshot, animatingDifferences: true)

        // 4) UI 반영 후 미읽음 계산 kick-off (네트워크는 메인에서 기다리지 않음)
        Task { await self.updateUnread(for: id, lastMessageSeqHint: updated.seq) }
    }
    
    private func updateUnread(for roomID: String, lastMessageSeqHint: Int64?) async {
        do {
            let lastRead = try await FirebaseManager.shared.fetchLastReadSeq(for: roomID)
            let latest: Int64
            if let hint = lastMessageSeqHint {
                latest = hint
            } else {
                latest = try await FirebaseManager.shared.fetchLatestSeq(for: roomID)
            }
            let unread = max(Int64(0), latest - lastRead)
            await MainActor.run {
                self.unreadCounts[roomID] = unread
                self.refreshRoomCell(id: roomID)
            }
        } catch {
            print("⚠️ updateUnread 실패(roomID: \(roomID)):", error)
        }
    }
    
    private func setjoinedRooms() {
        guard let profile = LoginManager.shared.currentUserProfile else { return }
        let joinedRoomIDs = profile.joinedRooms
        
        Task {
            do {
                let rooms = try await FirebaseManager.shared.fetchRoomsWithIDs(byIDs: joinedRoomIDs)
                
                // 병렬 이미지 로딩
                async let imagesDict: [String: UIImage] = withTaskGroup(of: (String, UIImage?).self) { group in
                    for room in rooms {

                        guard let imagePath = room.thumbPath else { continue }
                        let key = room.ID ?? room.roomName // capture simple Sendable values only
                        group.addTask {
                            let image = try? await KingFisherCacheManager.shared.loadOrFetchImage(
                                forKey: imagePath,
                                fetch: { try await FirebaseStorageManager.shared.fetchImageFromStorage(image: imagePath, location: .roomImage) }
                            )
                            return (key, image)
                        }
                    }
                    var dict: [String: UIImage] = [:]
                    for await (key, img) in group {
                        if let img = img { dict[key] = img }
                    }
                    return dict
                }
                
                // 최종 반영
                let dict = await imagesDict
                print(#function, "✅ 성공", dict)
                await MainActor.run {
                    self.roomImages = dict
                    self.applyRooms(rooms)
                }
                
                // 초기 진입 시 각 방 미읽음 계산 kick-off (비동기)
                for room in rooms {
                    if let id = room.ID {
                        let hint = room.seq
                        Task { [weak self] in
                            guard let self = self else { return }
                            await self.updateUnread(for: id, lastMessageSeqHint: hint)
                        }
                    }
                }
            } catch {
                print("❌ setJoinedRooms 실패:", error)
                await MainActor.run { self.applyRooms([]) }
            }
        }
    }
 
    @MainActor
    private func setupViews() {
        self.view.addSubview(joinedRoomListCollectionView)
        joinedRoomListCollectionView.translatesAutoresizingMaskIntoConstraints = false
        joinedRoomListCollectionView.delegate = self

        NSLayoutConstraint.activate([
            joinedRoomListCollectionView.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor),
            joinedRoomListCollectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            joinedRoomListCollectionView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            joinedRoomListCollectionView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
    }
    
    private func configureDataSource() {
        dataSource = DataSourceType(collectionView: joinedRoomListCollectionView) { [weak self] (collectionView, indexPath, room) -> UICollectionViewCell? in
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: JoinedRoomCell.reuseID, for: indexPath) as? JoinedRoomCell else { return UICollectionViewCell() }
            guard let self = self,
                  let roomID = room.ID else { return cell }
            
            cell.configure(
                title: room.roomName,
                participantCount: room.participants.count,
                lastMessageText: room.lastMessage,
                lastMessageDate: room.lastMessageAt,
                img: roomImages[roomID],
                unreadCount: unreadCounts[roomID] ?? 0
            )
            
            return cell
        }

        // Initial empty snapshot
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    /// Public API to update rooms
    func applyRooms(_ rooms: [ChatRoom], animated: Bool = false) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(rooms, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: animated)
    }
    
    @MainActor
    private func setupNavigationBar() {
        customNavigationBar.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(customNavigationBar)
        
        let constraints: [NSLayoutConstraint] = [
            customNavigationBar.topAnchor.constraint(equalTo: self.view.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ]
        NSLayoutConstraint.activate(constraints)
        
        customNavigationBar.configureForRoomList(target: self, onSearch: #selector(searchBtnTapped), onCreate:  #selector(createRoomBtnTapped))
    }
    
    @objc private func createRoomBtnTapped() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let chatRoomCreateVC = storyboard.instantiateViewController(identifier: "chatRoomCreateVC") as? RoomCreateViewController else { return }
        chatRoomCreateVC.modalPresentationStyle = .fullScreen
        
        ChatModalTransitionManager.present(chatRoomCreateVC, from: self)
    }
    
    @objc private func searchBtnTapped() {
        let searchVC = RoomSearchViewController()
        searchVC.modalPresentationStyle = .fullScreen
        ChatModalTransitionManager.present(searchVC, from: self)
    }
    
    // MARK: Diffable DataSource
    enum Section: Hashable { case main }
    typealias Item = ChatRoom
    typealias DataSourceType = UICollectionViewDiffableDataSource<Section, Item>
    var dataSource: DataSourceType!
    
    // MARK: - Callbacks / Providers
    var onSelectRoom: ((String) -> Void)?
    var onLeaveRoom: ((String) -> Void)?
}

extension JoinedRoomsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let room = dataSource.itemIdentifier(for: indexPath) else { return }
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let chatRoomVC = storyboard.instantiateViewController(withIdentifier: "chatRoomVC") as? ChatViewController else { return }
        chatRoomVC.room = room
        chatRoomVC.isRoomSaving = false
        chatRoomVC.modalPresentationStyle = .fullScreen
        ChatModalTransitionManager.present(chatRoomVC, from: self)

    }

    func collectionView(_ collectionView: UICollectionView, trailingSwipeActionsConfigurationForItemAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let room = dataSource.itemIdentifier(for: indexPath), let id = room.ID else { return nil }
        let leave = UIContextualAction(style: .destructive, title: "나가기") { [weak self] _, _, completion in
            self?.onLeaveRoom?(id)
            completion(true)
        }
        
        let config = UISwipeActionsConfiguration(actions: [leave])
        config.performsFirstActionWithFullSwipe = true
        return config
    }
}

extension JoinedRoomsViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: collectionView.bounds.width, height: 88)
    }
}

final class JoinedRoomCell: UICollectionViewCell {
    static let reuseID = "JoinedRoomCell"

    private let container = UIView()
    private let roomImageView = UIImageView()
    private let titleLabel = UILabel()
    private let countBadge = UILabel()
    private let timeLabel = UILabel()
    private let lastMessageLabel = UILabel()

    // 기존 hStack/vStack 대신
    private let titleRow = UIStackView()
    private let leftColumn = UIStackView()
    private let rightColumn = UIStackView()

    private let unreadContainer = UIView()
    private let unreadLabel = UILabel()

    // 오른쪽 스택 정렬 전환용 제약 두 개
    private var rightCenterYConstraint: NSLayoutConstraint?
    private var rightTopConstraint: NSLayoutConstraint?
    private var rightBottomConstraint: NSLayoutConstraint?
    // 왼쪽 스택의 Y축 중앙 정렬 제약
    private var leftCenterYConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setupUI() }

    override func prepareForReuse() {
        super.prepareForReuse()
        roomImageView.image = nil
        titleLabel.text = nil
        countBadge.text = nil
        timeLabel.text = nil
        lastMessageLabel.text = nil
        unreadLabel.text = nil
        unreadContainer.isHidden = true
    }

    func configure(title: String,
                   participantCount: Int,
                   lastMessageText: String?,
                   lastMessageDate: Date?,
                   img: UIImage?,
                   unreadCount: Int64) {
        titleLabel.text = title
        countBadge.text = "· \(participantCount)명"
        timeLabel.text = relativeTimeString(from: lastMessageDate)
        lastMessageLabel.text = lastMessageText ?? ""

        // Unread 배지
        if unreadCount > 0 {
            unreadContainer.isHidden = false
            unreadLabel.text = unreadCount > 99 ? "99+" : "\(unreadCount)"
            unreadContainer.accessibilityLabel = "읽지 않은 메시지 \(unreadLabel.text!)개"
        } else {
            unreadContainer.isHidden = true
            unreadLabel.text = nil
        }
        updateRightColumnPosition(hasUnread: unreadCount > 0)

        // 이미지
        roomImageView.image = img ?? UIImage(named: "Default_Profile")
    }

    private func setupUI() {
        contentView.backgroundColor = .clear

        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 12
        container.layer.masksToBounds = true
        contentView.addSubview(container)

        roomImageView.translatesAutoresizingMaskIntoConstraints = false
        roomImageView.contentMode = .scaleAspectFill
        roomImageView.clipsToBounds = true
        roomImageView.layer.cornerRadius = 8
        roomImageView.setContentHuggingPriority(.required, for: .horizontal)
        roomImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        roomImageView.image = UIImage(systemName: "person.2.circle")

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        countBadge.font = .preferredFont(forTextStyle: .subheadline)
        countBadge.textColor = .secondaryLabel
        countBadge.adjustsFontForContentSizeCategory = true
        countBadge.setContentCompressionResistancePriority(.required, for: .horizontal)
        countBadge.setContentHuggingPriority(.required, for: .horizontal)

        timeLabel.font = .preferredFont(forTextStyle: .footnote)
        timeLabel.textColor = .tertiaryLabel
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.adjustsFontForContentSizeCategory = true

        lastMessageLabel.font = .preferredFont(forTextStyle: .subheadline)
        lastMessageLabel.textColor = .secondaryLabel
        lastMessageLabel.numberOfLines = 2
        lastMessageLabel.adjustsFontForContentSizeCategory = true

        // Unread 배지
        unreadContainer.translatesAutoresizingMaskIntoConstraints = false
        unreadContainer.backgroundColor = .orange
        unreadContainer.layer.cornerRadius = 10
        unreadContainer.isHidden = true
        unreadContainer.setContentHuggingPriority(.required, for: .horizontal)
        unreadContainer.setContentCompressionResistancePriority(.required, for: .horizontal)

        unreadLabel.translatesAutoresizingMaskIntoConstraints = false
        unreadLabel.textColor = .white
        unreadLabel.font = .preferredFont(forTextStyle: .caption2)
        unreadLabel.textAlignment = .center
        unreadLabel.adjustsFontForContentSizeCategory = true
        unreadContainer.addSubview(unreadLabel)
        NSLayoutConstraint.activate([
            unreadLabel.topAnchor.constraint(equalTo: unreadContainer.topAnchor, constant: 2),
            unreadLabel.bottomAnchor.constraint(equalTo: unreadContainer.bottomAnchor, constant: -2),
            unreadLabel.leadingAnchor.constraint(equalTo: unreadContainer.leadingAnchor, constant: 8),
            unreadLabel.trailingAnchor.constraint(equalTo: unreadContainer.trailingAnchor, constant: -8),
            unreadContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 20)
        ])

        // 제목행 (제목 + 참여자수 + spacer)
        titleRow.axis = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = 6
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleRow.addArrangedSubview(titleLabel)
        titleRow.addArrangedSubview(countBadge)
        titleRow.addArrangedSubview(spacer)

        // 왼쪽 세로 스택 (제목행 위, 마지막 메시지 아래)
        leftColumn.axis = .vertical
        leftColumn.alignment = .fill
        leftColumn.spacing = 4
        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        leftColumn.addArrangedSubview(titleRow)
        leftColumn.addArrangedSubview(lastMessageLabel)

        // 오른쪽 세로 스택 (시간 위, 배지 아래)
        rightColumn.axis = .vertical
        rightColumn.alignment = .trailing
        rightColumn.spacing = 4
        rightColumn.translatesAutoresizingMaskIntoConstraints = false
        rightColumn.addArrangedSubview(timeLabel)
        rightColumn.addArrangedSubview(unreadContainer)

        container.addSubview(roomImageView)
        container.addSubview(leftColumn)
        container.addSubview(rightColumn)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            roomImageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            roomImageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            roomImageView.widthAnchor.constraint(equalToConstant: 52),
            roomImageView.heightAnchor.constraint(equalToConstant: 52),

            leftColumn.leadingAnchor.constraint(equalTo: roomImageView.trailingAnchor, constant: 12),
            leftColumn.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor, constant: 10),
            leftColumn.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -10),
            leftColumn.trailingAnchor.constraint(lessThanOrEqualTo: rightColumn.leadingAnchor, constant: -8),

            rightColumn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12)
        ])

        // 오른쪽 스택을 roomImageView의 Y축에 맞춤
        rightCenterYConstraint = rightColumn.centerYAnchor.constraint(equalTo: roomImageView.centerYAnchor)
        rightCenterYConstraint?.isActive = true
        // 왼쪽 스택도 roomImageView의 Y축에 맞춤
        leftCenterYConstraint = leftColumn.centerYAnchor.constraint(equalTo: roomImageView.centerYAnchor)
        leftCenterYConstraint?.isActive = true
    }

    private func updateRightColumnPosition(hasUnread: Bool) {
        // 단순화: 항상 roomImageView의 Y축에 정렬
        rightTopConstraint?.isActive = false
        rightBottomConstraint?.isActive = false
        rightCenterYConstraint?.isActive = true
        layoutIfNeeded()
    }

    private func relativeTimeString(from date: Date?) -> String {
        guard let date = date else { return "" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "방금 전" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)분 전" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)시간 전" }
        let days = hours / 24
        if days < 7 { return "\(days)일 전" }
        let weeks = days / 7
        if weeks < 5 { return "\(weeks)주 전" }
        let months = days / 30
        if months < 12 { return "\(months)개월 전" }
        let years = days / 365
        return "\(years)년 전"
    }
}
