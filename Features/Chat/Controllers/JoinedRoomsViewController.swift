//
//  JoinedRoomViewController.swift
//  OutPick
//
//  Created by 김가윤 on 9/28/25.
//

import UIKit
import FirebaseFirestore

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
    
    let viewModel: JoinedRoomsViewModel
    // roomID -> unread count
    private var unreadCounts: [String: Int64] = [:]
    
    var roomImages: [String:UIImage] = [:]
    private var lastReadSeqObserver: NSObjectProtocol?

    // MARK: - Navigation callbacks (Coordinator)
    var onOpenRoom: ((ChatRoom) -> Void)?
    var onCreateRoom: (() -> Void)?
    var onSearchRoom: (() -> Void)?
    
    init(viewModel: JoinedRoomsViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        let db = Firestore.firestore()
        let roomRepository = FirebaseChatRoomRepository(db: db)
        let userProfileRepository = UserProfileRepository(db: db)
        let joinedRoomsStore = ChatDependencyContainer.requireJoinedRoomsStore()
        let useCase = JoinedRoomsUseCase(
            roomRepository: roomRepository,
            userProfileRepository: userProfileRepository,
            joinedRoomsStore: joinedRoomsStore
        )
        self.viewModel = JoinedRoomsViewModel(useCase: useCase)
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupViews()
        configureDataSource()
        bindViewModel()
        bindNotifications()
        viewModel.notifyCurrentState()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.start()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.stop()
    }

    deinit {
        if let lastReadSeqObserver {
            NotificationCenter.default.removeObserver(lastReadSeqObserver)
        }
    }

    private func bindViewModel() {
        viewModel.onStateChanged = { [weak self] state in
            guard let self else { return }
            self.unreadCounts = state.unreadCounts
            self.applyRooms(state.rooms, animated: true)
            Task { await self.syncRoomImages(for: state.rooms) }
        }
    }

    private func bindNotifications() {
        lastReadSeqObserver = NotificationCenter.default.addObserver(
            forName: .chatRoomLastReadSeqDidFlush,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let roomID = notification.userInfo?["roomID"] as? String, !roomID.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.viewModel.refreshUnreadCount(roomID: roomID)
            }
        }
    }

    @MainActor
    private func syncRoomImages(for rooms: [ChatRoom]) async {
        let pairs: [(String, String)] = rooms.compactMap { room in
            guard let roomID = room.ID,
                  let thumbPath = room.thumbPath,
                  !thumbPath.isEmpty else { return nil }
            return (roomID, thumbPath)
        }

        let fetched: [String: UIImage] = await withTaskGroup(of: (String, UIImage?).self, returning: [String: UIImage].self) { group in
            for (roomID, imagePath) in pairs {
                if roomImages[roomID] != nil { continue }
                group.addTask {
                    let image = try? await KingFisherCacheManager.shared.loadOrFetchImage(
                        forKey: imagePath,
                        fetch: {
                            try await FirebaseImageStorageRepository.shared.fetchImageFromStorage(image: imagePath, location: .roomImage)
                        }
                    )
                    return (roomID, image)
                }
            }

            var dict: [String: UIImage] = [:]
            for await (roomID, image) in group {
                if let image {
                    dict[roomID] = image
                }
            }
            return dict
        }

        if fetched.isEmpty { return }
        await MainActor.run {
            self.roomImages.merge(fetched) { current, _ in current }
            self.applyRooms(self.dataSource.snapshot().itemIdentifiers, animated: false)
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
        snapshot.reloadItems(rooms)
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
        if let onCreateRoom {
            onCreateRoom()
            return
        }

        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let chatRoomCreateVC = storyboard.instantiateViewController(identifier: "chatRoomCreateVC") as? RoomCreateViewController else { return }
        chatRoomCreateVC.modalPresentationStyle = .fullScreen
        
        ChatModalTransitionManager.present(chatRoomCreateVC, from: self)
    }
    
    @objc private func searchBtnTapped() {
        if let onSearchRoom {
            onSearchRoom()
            return
        }

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

        if let onOpenRoom {
            onOpenRoom(room)
            return
        }
        
        let chatRoomVC = ChatViewController(provider: ChatDependencyContainer.provider)
        if let repositories = ChatDependencyContainer.firebaseRepositories {
            chatRoomVC.injectedFirebaseRepositories = repositories
        }
        chatRoomVC.room = room
        chatRoomVC.configureDefaultViewModelIfNeeded()
        chatRoomVC.isRoomSaving = false
        chatRoomVC.modalPresentationStyle = .fullScreen
        ChatModalTransitionManager.present(chatRoomVC, from: self)

    }

    func collectionView(_ collectionView: UICollectionView, trailingSwipeActionsConfigurationForItemAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let room = dataSource.itemIdentifier(for: indexPath), let id = room.ID else { return nil }
        let leave = UIContextualAction(style: .destructive, title: "나가기") { [weak self] _, _, completion in
            if let onLeaveRoom = self?.onLeaveRoom {
                onLeaveRoom(id)
            } else {
                self?.viewModel.leave(room: room)
            }
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
        unreadContainer.alpha = 0
        unreadContainer.accessibilityLabel = nil
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
            unreadContainer.alpha = 1
            unreadLabel.text = unreadCount > 99 ? "99+" : "\(unreadCount)"
            unreadContainer.accessibilityLabel = "읽지 않은 메시지 \(unreadLabel.text!)개"
        } else {
            unreadContainer.isHidden = true
            unreadContainer.alpha = 0
            unreadLabel.text = nil
            unreadContainer.accessibilityLabel = nil
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
