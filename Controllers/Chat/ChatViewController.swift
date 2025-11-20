//
//  ChatViewController.swift
//  OutPick
//
//  Created by 김가윤 on 10/14/24.
//

import Foundation
import AVFoundation
import UIKit
import AVKit
import Combine
import PhotosUI
import Firebase
import Kingfisher
import FirebaseStorage
import CryptoKit
import Photos
import FirebaseFirestore

protocol ChatMessageCellDelegate: AnyObject {
    func cellDidLongPress(_ cell: ChatMessageCell)
}

class ChatViewController: UIViewController, UINavigationControllerDelegate, ChatModalAnimatable {
    
    // Paging buffer size for scroll triggers
    private var pagingBuffer = 200
    
    private var isInitialLoading = true
    
    @IBOutlet weak var sideMenuBtn: UIBarButtonItem!
    @IBOutlet weak var joinRoomBtn: UIButton!
    
    var swipeRecognizer: UISwipeGestureRecognizer!
    
    private var chatMessageCollectionView = ChatMessageCollectionView()
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var cancellables = Set<AnyCancellable>()
    private var chatCustomMemucancellables = Set<AnyCancellable>()
    
    private var lastMessageDate: Date?
    private var lastReadMessageID: String?
    
    private var isUserInCurrentRoom = false
    
    private var replyMessage: ReplyPreview?
    private var messageMap: [String: ChatMessage] = [:]
    // Preloaded thumbnails for image messages (messageID -> ordered thumbnails)
    var messageImages: [String: [UIImage]] = [:]
    // Separate prepared flags to avoid image/video race on shared messageImages
    private var preparedImageThumbMessageIDs: Set<String> = []
    private var preparedVideoThumbMessageIDs: Set<String> = []
    
    // Loading state flags for message paging
    private var isLoadingOlder = false
    private var isLoadingNewer = false
    
    private var hasMoreOlder = true
    private var hasMoreNewer = true
    
    private var avatarWarmupRoomID: String?
    
    enum Section: Hashable {
        case main
    }
    
    enum Item: Hashable {
        case message(ChatMessage)
        case dateSeparator(Date)
        case readMarker
    }
    
    enum MessageUpdateType {
        case older
        case newer
        case reload
        case initial
    }
    
    var room: ChatRoom?
    var roomID: String?
    // Firebase Storage downloadURL cache (path -> URL)
    private let storageURLCache = OPStorageURLCache()
    var isRoomSaving: Bool = false
    
    var convertImagesTask: Task<Void, Error>? = nil
    var convertVideosTask: Task<Void, Error>? = nil
    
    private var filteredMessages: [ChatMessage] = []
    private var currentFilteredMessageIndex: Int?
    private var highlightedMessageIDs: Set<String> = []
    private var currentSearchKeyword: String? = nil
    private var hasBoundRoomChange = false
    
    static var currentRoomID: String? = nil
    
    // 중복 호출 방지를 위한 최근 트리거 인덱스
    private var minTriggerDistance: Int { return 3 }
    private static var lastTriggeredOlderIndex: Int?
    private static var lastTriggeredNewerIndex: Int?
    
    private var deletionListener: ListenerRegistration?
    
    private var cellSubscriptions: [ObjectIdentifier: Set<AnyCancellable>] = [:]
    
    
    deinit {
        print("💧 ChatViewController deinit")
        convertImagesTask?.cancel()
        convertVideosTask?.cancel()
        
        deletionListener?.remove()
        deletionListener = nil
    }
    
    private lazy var containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var attachmentView: AttachmentView = {
        let view = AttachmentView()
        view.translatesAutoresizingMaskIntoConstraints = false
        
        view.onButtonTapped = { [weak self] identifier in
            guard let self = self else { return }
            self.handleAttachmentButtonTap(identifier: identifier)
        }
        
        return view
    }()
    
    private lazy var chatUIView: ChatUIView = {
        let view = ChatUIView()
        view.isHidden = true
        
        view.onButtonTapped = { [weak self] identifier in
            guard let self = self else { return }
            self.handleAttachmentButtonTap(identifier: identifier)
        }
        
        return view
    }()
    
    private lazy var customNavigationBar: CustomNavigationBarView = {
        let navBar = CustomNavigationBarView()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        
        return navBar
    }()
    
    private lazy var searchUI: ChatSearchUIView = {
        let view = ChatSearchUIView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var chatCustomMenu: ChatCustomPopUpMenu = {
        let view = ChatCustomPopUpMenu()
        view.backgroundColor = .black
        view.layer.cornerRadius = 20
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    private var highlightedCell: ChatMessageCell?
    
    private lazy var notiView: ChatNotiView = {
        let view = ChatNotiView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.isHidden = true
        
        return view
    }()
    
    private lazy var replyView: ChatReplyView = {
        let view = ChatReplyView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.isHidden = true
        
        return view
    }()
    
    private var settingPanelVC: ChatRoomSettingCollectionView?
    private lazy var dimView: UIView = {
        //        let v = UIControl(frame: .zero)
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        v.alpha = 0
        
        return v
    }()
    
    // 공지 배너 (고정/접기/만료 안내 지원)
    private lazy var announcementBanner: AnnouncementBannerView = {
        let v = AnnouncementBannerView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        v.onHeightChange = { [weak self] in
            guard let self = self else { return }
            self.adjustForBannerHeight()
        }
        
        // Long-press on the announcement banner (to show options or toggle expand)
        let bannerLongPress = UILongPressGestureRecognizer(target: self, action: #selector(handleAnnouncementBannerLongPress(_:)))
        bannerLongPress.minimumPressDuration = 0.35
        bannerLongPress.cancelsTouchesInView = true
        v.addGestureRecognizer(bannerLongPress)
        // Ensure the global long press (used for message cells) doesn't steal this interaction
        self.longPressGesture.require(toFail: bannerLongPress)
        return v
    }()
    private var baseTopInsetForBanner: CGFloat?
    
    // Delete confirm overlay
    private var confirmDimView: UIControl?
    private var confirmView: ConfirmView?
    
    private let imagesSubject = CurrentValueSubject<[UIImage], Never>([])
    private var imagesPublishser: AnyPublisher<[UIImage], Never> {
        return imagesSubject.eraseToAnyPublisher()
    }
    
    // Layout 제약 조건 저장
    private var chatConstraints: [NSLayoutConstraint] = []
    private var chatUIViewBottomConstraint: NSLayoutConstraint?
    private var chatMessageCollectionViewBottomConstraint: NSLayoutConstraint?
    private var joinConsraints: [NSLayoutConstraint] = []
    
    private var interactionController: UIPercentDrivenInteractiveTransition?
    
    private lazy var tapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture))
        gesture.delegate = self
        gesture.cancelsTouchesInView = false
        return gesture
    }()
    
    lazy var longPressGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        gesture.delegate = self
        return gesture
    }()
    
    private var searchUIBottomConstraint: NSLayoutConstraint?
    
    private var scrollTargetIndex: IndexPath?
    
    private var lastContainerViewOriginY: Double = 0
    
    enum LiveMode { case catchingUp, live }
    private var liveMode: LiveMode = .live
    private var entryTailSeq: Int64 = 0 // 방 입장 시점의 tail 스냅샷(고정)
    private var windowMaxSeq: Int64 = 0 // 현재 창(로컬+서버 로드)의 최대 seq
    
    // 실시간 버퍼(캐치업 중에는 UI 반영 보류)
    private var liveBuffer: [ChatMessage] = []
    private var liveBufferIDs: Set<String> = []
    // 마지막으로 서버에 반영한 lastReadSeq (단조 증가, 중복 쓰기 방지)
    private var lastSentLastReadSeq: Int64 = 0
    
    // MARK: - Hot user pool (실시간 프로필/닉네임 반영용)
    private struct HotUser {
        let email: String
        var lastSeenAt: Date
    }

    private var hotUsers: [HotUser] = []
    private let maxHotUsers: Int = 20
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.definesPresentationContext = true
        
        configureDataSource()
        
        setUpNotifications()
        if isRoomSaving {
            LoadingIndicator.shared.start(on: self)
            chatUIView.isHidden = false
            joinRoomBtn.isHidden = true
        } else {
            LoadingIndicator.shared.stop()
        }
        
        view.addGestureRecognizer(tapGesture)
        view.addGestureRecognizer(longPressGesture)
        
        setupCustomNavigationBar()
        decideJoinUI()
        setupAttachmentView()
        
        setupInitialMessages()
        
        bindKeyboardPublisher()
        bindSearchEvents()
        
        chatMessageCollectionView.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        BannerManager.shared.setVisibleRoom(self.room?.ID ?? "")
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        BannerManager.shared.setVisibleRoom(nil)
        
        isUserInCurrentRoom = false
        
        if let room = self.room {
            SocketIOManager.shared.unsubscribeFromMessages(for: room.ID ?? "")
            
            if ChatViewController.currentRoomID == room.ID {
                ChatViewController.currentRoomID = nil    // ✅ 나갈 때 초기화
            }
        }
        
        stopAllPrefetchers()
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
        
        convertImagesTask?.cancel()
        convertVideosTask?.cancel()
        
        deletionListener?.remove()
        deletionListener = nil
        resetHotUserPool()
        removeReadMarkerIfNeeded()
        
        // 참여하지 않은 방이면 로컬 메시지 삭제 처리 (메인 바깥에서 비동기 실행)
        if let room = self.room,
           !room.participants.contains(LoginManager.shared.getUserEmail) {
            let roomID = room.ID ?? ""
            Task(priority: .utility) {
                do {
                    try GRDBManager.shared.deleteMessages(inRoom: roomID)
                    try GRDBManager.shared.deleteImages(inRoom: roomID)
                    print("참여하지 않은 사용자의 임시 메시지/이미지 삭제 완료")
                } catch {
                    print("GRDB 메시지/이미지 삭제 실패: \(error)")
                }
            }
        }
        
        self.navigationController?.setNavigationBarHidden(false, animated: false)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        guard let room = self.room else { return }

        // 세션 종료 시: 실제 확인한 최대 위치 기록(입장 스냅샷을 넘기지 않음)
        let finalSeq = min(windowMaxSeq, entryTailSeq)
        if finalSeq > lastSentLastReadSeq { lastSentLastReadSeq = finalSeq }

        Task(priority: .utility) { [roomID = room.ID ?? "", uid = LoginManager.shared.getUserEmail, seq = finalSeq] in
            do {
                try await FirebaseManager.shared.updateLastReadSeq(roomID: roomID, userID: uid, lastReadSeq: seq)
            } catch {
                print("⚠️ viewWillDisappear lastReadSeq 기록 실패: \(error)")
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.notiView.layer.cornerRadius = 15
    }
    
    //MARK: 메시지 관련
    @MainActor
    private func setupInitialMessages() {
        Task {
            LoadingIndicator.shared.start(on: self)
            defer { LoadingIndicator.shared.stop() }

            guard let room = self.room else { return }
            let isParticipant = room.participants.contains(LoginManager.shared.getUserEmail)

            // 🔎 참여중이지 않은 사용자들을 위한 미리보기
            if !isParticipant {
                do {
                    // 서버에서 최신 메시지 페이징으로 불러오기 (로컬 DB에 저장하지 않음)
                    let previewMessages = try await FirebaseManager.shared.fetchMessagesPaged(for: room, pageSize: 100, reset: true)
                    addMessages(previewMessages, updateType: .initial)

                    // 이미지/비디오 썸네일 프리페치(셀 타깃 리로드 포함)
                    await self.prefetchThumbnails(for: previewMessages, maxConcurrent: 4)
                    await self.prefetchVideoAssets(for: previewMessages, maxConcurrent: 4)

                    // 실시간 구독/읽음 처리 없음 (미참여 사용자 미리보기)
                    self.isInitialLoading = false
                } catch {
                    print("❌ 미참여자 미리보기 로드 실패:", error)
                }
                return
            }

            do {
                // 1. GRDB 로드
                let roomID = room.ID ?? ""
                let localMessages = try await Task(priority: .userInitiated) {
                    try await GRDBManager.shared.fetchRecentMessages(inRoom: roomID, limit: 200)
                }.value
                self.lastReadMessageID = localMessages.last?.ID
                
                localMessages.forEach {
                    print("📢 로컬 메시지 로드:", $0)
                }

                let imageMessages = localMessages.filter { $0.attachments.contains { $0.type == .image } }
                for msg in imageMessages {
                    await self.cacheImagesIfNeeded(for: msg)
                }

                // 로컬 메시지의 비디오 에셋 캐싱은 표준 헬퍼로 통일
                let videoLocalMessages = localMessages.filter { $0.attachments.contains { $0.type == .video } }
                for msg in videoLocalMessages {
                    await self.cacheVideoAssetsIfNeeded(for: msg, in: roomID)
                }

                addMessages(localMessages, updateType: .initial)

                // 2. 삭제 상태 동기화
                await syncDeletedStates(localMessages: localMessages, room: room)

                // 3. Firebase에서 메시지 로드
                let serverMessages = try await FirebaseManager.shared.fetchMessagesPaged(for: room, pageSize: 300, reset: true)
                try await GRDBManager.shared.saveChatMessages(serverMessages)

                // 3-1. 초기 로드(로컬 + 서버)에서 보이는 발신자들을 LocalUser/RoomMember에 반영
                //      실시간 수신 경로에서는 handleIncomingMessage에서 upsert하지만,
                //      초기 로드 경로에서는 누락될 수 있어 보정한다.
                let combinedForUserUpsert = localMessages + serverMessages
                Task.detached(priority: .utility) { [roomID, combinedForUserUpsert] in
                    var seenSenders = Set<String>()
                    for msg in combinedForUserUpsert {
                        let email = msg.senderID
                        guard !email.isEmpty, seenSenders.insert(email).inserted else { continue }
                        do {
                            _ = try GRDBManager.shared.upsertLocalUser(
                                email: email,
                                nickname: msg.senderNickname,
                                profileImagePath: msg.senderAvatarPath
                            )
                            try GRDBManager.shared.addLocalUser(email, toRoom: roomID)
                        } catch {
                            print("⚠️ Initial LocalUser upsert/add 실패 (\(email)):", error)
                        }
                    }
                }
                
                // ===== 초기 창 기준 계산: 입장 tail 스냅샷과 창 최대 seq =====
                self.entryTailSeq = Int64(room.seq) // 입장 시점 고정 스냅샷
                let localMaxSeq  = localMessages.map(\.seq).max() ?? 0
                let serverMaxSeq = serverMessages.map(\.seq).max() ?? 0
                self.windowMaxSeq = max(localMaxSeq, serverMaxSeq)
                self.liveMode = (self.windowMaxSeq >= self.entryTailSeq) ? .live : .catchingUp
                print("[Init] entryTailSeq=", self.entryTailSeq, "windowMaxSeq=", self.windowMaxSeq, "liveMode=", self.liveMode)

                addMessages(serverMessages, updateType: .newer)
                
                // Hot user 풀 시드: 최근 로컬+서버 메시지 발신자 기준으로 최대 20명 프로필 리스너 등록
                self.seedHotUserPool(with: localMessages + serverMessages)

                // 백그라운드 프리페치 시작 (이미지 썸네일 + 비디오 썸네일/URL warm-up)
                await self.prefetchThumbnails(for: serverMessages, maxConcurrent: 4)
                await self.prefetchVideoAssets(for: serverMessages, maxConcurrent: 4)

                isUserInCurrentRoom = true
                bindMessagePublishers()
                
                
            } catch {
                print("❌ 메시지 초기화 실패:", error)
            }
            isInitialLoading = false
        }
    }
    
    @MainActor
    private func updateWindowMaxSeq(with messages: [ChatMessage]) {
        guard let mx = messages.map(\.seq).max() else { return }
        if mx > windowMaxSeq { windowMaxSeq = mx }
    }

    @MainActor
    private func drainLiveBufferIfAny() {
        guard !liveBuffer.isEmpty else { return }
        // 중복/순서 정리 후 배치 추가
        let flushed = liveBuffer.sorted { $0.seq < $1.seq }
        liveBuffer.removeAll()
        liveBufferIDs.removeAll()

        // UI 부하 완화: 소량 배치
        let chunkSize = 20
        var i = 0
        while i < flushed.count {
            let end = min(i + chunkSize, flushed.count)
            let chunk = Array(flushed[i..<end])
            addMessages(chunk, updateType: .newer)
            i = end
        }

        updateWindowMaxSeq(with: flushed)
    }
    
    @MainActor
    private func reloadVisibleMessageIfNeeded(messageID: String) {
        var snapshot = dataSource.snapshot()
        guard let item = snapshot.itemIdentifiers.first(where: { item in
            if case let .message(m) = item { return m.ID == messageID }
            return false
        }) else { return }
        snapshot.reconfigureItems([item])
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    private func prefetchThumbnails(for messages: [ChatMessage], maxConcurrent: Int = 4) async {
        guard (self.room?.ID) != nil else { return }
        let imageMessages = messages.filter { $0.attachments.contains { $0.type == .image } }
        
        var index = 0
        while index < imageMessages.count {
            let end = min(index + maxConcurrent, imageMessages.count)
            let slice = Array(imageMessages[index..<end])
            
            await withTaskGroup(of: Void.self) { group in
                for msg in slice {
                    group.addTask { [weak self] in
                        guard let self = self else { return }
                        await self.cacheImagesIfNeeded(for: msg)
//                        await MainActor.run {
                        await self.reloadVisibleMessageIfNeeded(messageID: msg.ID)
//                        }
                    }
                }
                await group.waitForAll()
            }
            index = end
        }
    }
    
    // MARK: - Video asset prefetching
    private func prefetchVideoAssets(for messages: [ChatMessage], maxConcurrent: Int = 4) async {
        guard let roomID = self.room?.ID else { return }
        let videoMessages = messages.filter { $0.attachments.contains { $0.type == .video } }
        var index = 0
        while index < videoMessages.count {
            let end = min(index + maxConcurrent, videoMessages.count)
            let slice = Array(videoMessages[index..<end])

            await withTaskGroup(of: Void.self) { group in
                for msg in slice {
                    group.addTask { [weak self] in
                        guard let self = self else { return }
                        await self.cacheVideoAssetsIfNeeded(for: msg, in: roomID)
                    }
                }
                await group.waitForAll()
            }
            index = end
        }
    }

    @MainActor
    private func syncDeletedStates(localMessages: [ChatMessage], room: ChatRoom) async {
        do {
            // 1) 로컬 200개 메시지의 ID / 삭제상태 맵
            let localIDs = localMessages.map { $0.ID }
            let localDeletionStates = Dictionary(uniqueKeysWithValues: localMessages.map { ($0.ID, $0.isDeleted) })

            // 2) 서버에서 해당 ID들의 삭제 상태만 조회 (chunked IN query)
            let serverMap = try await FirebaseManager.shared.fetchDeletionStates(roomID: room.ID ?? "", messageIDs: localIDs)

            // 3) 서버가 true인데 로컬은 false인 ID만 업데이트 대상
            let idsToUpdate: [String] = localIDs.filter { (serverMap[$0] ?? false) && ((localDeletionStates[$0] ?? false) == false) }
            guard !idsToUpdate.isEmpty else { return }

            let roomID = room.ID ?? ""

            // 4) GRDB 영속화: 원본 isDeleted + 해당 원본을 참조하는 replyPreview.isDeleted
            //    → detached(.medium)에서 두 업데이트 모두 수행, 완료 후에만 메인에서 UI 반영
            let ids = idsToUpdate
            Task.detached(priority: .medium) { [weak self] in
                guard let self = self else { return }
                do {
                    try await GRDBManager.shared.updateMessagesIsDeleted(ids, isDeleted: true, inRoom: roomID)
                    try await GRDBManager.shared.updateReplyPreviewsIsDeleted(referencing: ids, isDeleted: true, inRoom: roomID)

                    // 5) UI 배치 리로드 셋업 (백그라운드에서 계산 후 메인에서 반영)
                    let deletedMessages: [ChatMessage] = localMessages
                        .filter { ids.contains($0.ID) }
                        .map { msg in var copy = msg; copy.isDeleted = true; return copy }

                    let affectedReplies: [ChatMessage] = localMessages
                        .filter { msg in (msg.replyPreview?.messageID).map(ids.contains) ?? false }
                        .map { reply in var copy = reply; copy.replyPreview?.isDeleted = true; return copy }

                    let toReload = deletedMessages + affectedReplies
                    if !toReload.isEmpty {
                        await MainActor.run {
                            self.addMessages(toReload, updateType: .reload)
                        }
                    }
                } catch {
                    print("❌ 삭제 상태 동기화(영속화) 실패:", error)
                }
            }
            // ⬆️ fire-and-forget: 여기서 .value로 대기하지 않음
        } catch {
            print("❌ 삭제 상태 동기화 실패:", error)
        }
    }

    @MainActor
    private func removeReadMarkerIfNeeded() {
        var snapshot = dataSource.snapshot()
        if let marker = snapshot.itemIdentifiers.first(where: {
            if case .readMarker = $0 { return true }
            return false
        }) {
            snapshot.deleteItems([marker])
            dataSource.apply(snapshot, animatingDifferences: false)
        }
    }
    
    @MainActor
    private func loadOlderMessages(before messageID: String?) async {
        // Note: willDisplay cell logic already handles trigger conditions (scroll position, etc.)
        guard !isLoadingOlder, hasMoreOlder else { return }
        guard let room = self.room else { return }
        
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        
        print(#function, "✅ loading older 진행")
        do {
            let roomID = room.ID ?? ""
            
            // 1. GRDB에서 먼저 최대 100개
            let local = try await GRDBManager.shared.fetchOlderMessages(inRoom: roomID, before: messageID ?? "", limit: 100)
            var loadedMessages = local
            
            // 2. 부족분은 서버에서 채우기
            if local.count < 100 {
                let needed = 100 - local.count
                let server = try await FirebaseManager.shared.fetchOlderMessages(
                    for: room,
                    before: messageID ?? "",
                    limit: needed
                )
                
                if server.isEmpty {
                    hasMoreOlder = false   // 더 이상 이전 메시지 없음
                } else {
                    try await GRDBManager.shared.saveChatMessages(server)
                    loadedMessages.append(contentsOf: server)
                }
            }
            
            if loadedMessages.isEmpty {
                hasMoreOlder = false
            } else {
                // Chunk messages into groups of 20 for performance
                let chunkSize = 20
                let total = loadedMessages.count
                for i in stride(from: 0, to: total, by: chunkSize) {
                    let end = min(i + chunkSize, total)
                    let chunk = Array(loadedMessages[i..<end])
                    addMessages(chunk, updateType: .older)
                }
            }
        } catch {
            print("❌ loadOlderMessages 실패:", error)
        }
    }
    
    @MainActor
    private func loadNewerMessagesIfNeeded(after messageID: String?) async {
        guard !isLoadingNewer else { return }
        guard let room = self.room else { return }

        isLoadingNewer = true
        defer { isLoadingNewer = false }

        print(#function, "✅ loading newer 진행")
        do {
            // 1) 서버에서 after 이후 메시지 보충 (최대 100개, seq ASC 가정)
            let server = try await FirebaseManager.shared.fetchMessagesAfter(
                room: room,
                after: messageID ?? "",
                limit: 100
            )

            // 2) 창 최대 seq 갱신 + catchingUp → live 전환 판정
            if let pageMax = server.last?.seq {
                if pageMax > windowMaxSeq { windowMaxSeq = pageMax }
            }
            if liveMode == .catchingUp && windowMaxSeq >= entryTailSeq {
                liveMode = .live
                drainLiveBufferIfAny()
            }
            // 3) newerPage 경로에서는 바닥 체크 생략(이미 바닥 근접 스크롤로 유도됨)
            maybeUpdateLastReadSeq(trigger: "newerPage", skipNearBottomCheck: true)

            // 4) 저장/스냅샷 반영
            guard !server.isEmpty else { return }
            try await GRDBManager.shared.saveChatMessages(server)

            // 배치 반영(20개 단위)
            let chunkSize = 20
            let total = server.count
            for i in stride(from: 0, to: total, by: chunkSize) {
                let end = min(i + chunkSize, total)
                let chunk = Array(server[i..<end])
                addMessages(chunk, updateType: .newer)
            }
        } catch {
            print("❌ loadNewerMessagesIfNeeded 실패:", error)
        }
    }
    
    private func bindMessagePublishers() {
        guard let room = self.room else { return }
        SocketIOManager.shared.subscribeToMessages(for: room.ID ?? "")
            .sink { [weak self] receivedMessage in
                guard let self = self else { return }
                Task {
                    await self.handleIncomingMessage(receivedMessage)
                }
            }
            .store(in: &cancellables)

        deletionListener = FirebaseManager.shared.listenToDeletedMessages(roomID: room.ID ?? "") { [weak self] deletedMessageID in
            guard let self = self else { return }
            let rid = room.ID ?? ""
            Task.detached(priority: .medium) { [weak self, rid] in
                guard let self = self else { return }

                // 1) GRDB 영속화: 원본 + 답장 preview (메인 밖)
                do {
                    try await GRDBManager.shared.updateMessagesIsDeleted([deletedMessageID], isDeleted: true, inRoom: rid)
                    try await GRDBManager.shared.updateReplyPreviewsIsDeleted(referencing: [deletedMessageID], isDeleted: true, inRoom: rid)
                } catch {
                    print("❌ GRDB deletion persistence failed:", error)
                }

                // 2) messageMap 최신화 및 배치 리로드 목록 구성 (메인에서만)
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    var toReload: [ChatMessage] = []

                    if var deletedMsg = self.messageMap[deletedMessageID] {
                        deletedMsg.isDeleted = true
                        self.messageMap[deletedMessageID] = deletedMsg
                        toReload.append(deletedMsg)
                    } else {
                        print("⚠️ deleted message not in window: \(deletedMessageID)")
                    }

                    let repliesInWindow = self.messageMap.values.filter { $0.replyPreview?.messageID == deletedMessageID }
                    for var reply in repliesInWindow {
                        reply.replyPreview?.isDeleted = true
                        self.messageMap[reply.ID] = reply
                        toReload.append(reply)
                    }

                    // 3) UI 반영 (한 번만)
                    if !toReload.isEmpty {
                        self.addMessages(toReload, updateType: .reload)
                    }
                }
            }
        }
    }
    
    // 수신 메시지를 저장 및 UI 반영
    @MainActor
    private func handleIncomingMessage(_ message: ChatMessage) async {
        guard let room = self.room else { return }
        // 다른 방 이벤트는 무시
        if message.roomID != room.ID { return }
        print("\(message.isFailed ? "전송 실패" : "전송 성공") 메시지 수신: \(message)")

        // 1) 첨부 캐시 선행 (이미지/비디오가 있으면)
        let hasImages = message.attachments.contains { $0.type == .image }
        let hasVideos = message.attachments.contains { $0.type == .video }
        if hasImages || hasVideos {
            let rid = room.ID ?? ""
            await withTaskGroup(of: Void.self) { group in
                if hasImages {
                    group.addTask { [weak self] in
                        guard let self = self else { return }
                        await self.cacheImagesIfNeeded(for: message)
                    }
                }
                if hasVideos {
                    group.addTask { [weak self] in
                        guard let self = self else { return }
                        await self.cacheVideoAssetsIfNeeded(for: message, in: rid)
                    }
                }
                await group.waitForAll()
            }
        }

        // 2) 모드별 처리
        switch liveMode {
        case .catchingUp:
            if !liveBufferIDs.contains(message.ID) {
                liveBufferIDs.insert(message.ID)
                liveBuffer.append(message)
            }
            // catchingUp에서는 windowMaxSeq 갱신 안 함(페이지 로드 기준만)
            return

        case .live:
            addMessages([message])
            // 🔥 실시간 수신 시 핫 유저 풀 갱신
            updateHotUserPool(for: message.senderID, lastSeenAt: message.sentAt ?? Date())
            if message.seq > windowMaxSeq { windowMaxSeq = message.seq }
            // 라이브 소비 중 바닥 근처일 때만 읽음 진행 반영
            maybeUpdateLastReadSeq(trigger: "liveIncoming")
        }

        // 3) 로컬 DB 저장 (재시도 백오프)
        Task(priority: .userInitiated) {
            let maxRetries = 3
            var lastError: Error?
            for attempt in 1...maxRetries {
                do {
                    // (1) 메시지 본문/첨부 저장
                    try await GRDBManager.shared.saveChatMessages([message])

                    // (2) LocalUser + RoomMember 업데이트
                    do {
                        try GRDBManager.shared.upsertLocalUser(
                            email: message.senderID,
                            nickname: message.senderNickname,
                            profileImagePath: message.senderAvatarPath
                        )
                        try GRDBManager.shared.addLocalUser(message.senderID, toRoom: message.roomID)
                    } catch {
                        print("⚠️ LocalUser/RoomMember 업데이트 실패: \(error)")
                    }

                    lastError = nil
                    break
                } catch {
                    lastError = error
                    print("⚠️ GRDB saveChatMessages 실패 (시도 \(attempt)/\(maxRetries)): \(error)")
                    if attempt < maxRetries {
                        try? await Task.sleep(nanoseconds: UInt64(200_000_000) * UInt64(attempt))
                    }
                }
            }
            if let err = lastError {
                print("❌ GRDB saveChatMessages 최종 실패: \(err)")
            }
        }

        // 4) 내가 보낸 정상 메시지면 Firebase 기록 (비차단)
        if !message.isFailed, message.senderID == LoginManager.shared.getUserEmail {
            let currentRoom = room
            Task(priority: .utility) {
                do {
                    try await FirebaseManager.shared.saveMessage(message, currentRoom)
                } catch {
                    print("⚠️ Firebase saveMessage 실패(비차단): \(error)")
                }
            }
        }
    }
    
    // Mark: LocalUser + HotUser 관련 함수
    func updateHotUserPool(for email: String, lastSeenAt: Date) {
        // 1) 이미 핫 유저면 lastSeenAt만 갱신하고 끝
        if let idx = hotUsers.firstIndex(where: { $0.email == email }) {
            hotUsers[idx].lastSeenAt = lastSeenAt
            return
        }
        
        // 2) 새 유저인데 아직 자리가 남아 있으면 추가 + 리스너 구독
        if hotUsers.count < maxHotUsers {
            hotUsers.append(HotUser(email: email, lastSeenAt: lastSeenAt))
            _ = FirebaseManager.shared.listenToUserProfile(email: email) { _ in }
            return
        }
        
        // 3) 새 유저이고, 이미 20명이 꽉 차 있으면
        //    가장 오래 등장 안 한 유저(least recent)를 하나 골라 교체
        if let oldestIndex = hotUsers.indices.min(by: { hotUsers[$0].lastSeenAt < hotUsers[$1].lastSeenAt }) {
            let oldEmail = hotUsers[oldestIndex].email
            
            // 3-1) 오래된 유저 리스너 제거
            FirebaseManager.shared.stopListenUserProfile(email: oldEmail)
            
            // 3-2) 새 유저로 교체 + 새 리스너 시작
            hotUsers[oldestIndex] = HotUser(email: email, lastSeenAt: lastSeenAt)
            _ = FirebaseManager.shared.listenToUserProfile(email: email) { _ in }
        }
    }
    
    private func resetHotUserPool() {
        // 이 뷰컨이 사라질 때, 관련 프로필 리스너 정리
        for user in hotUsers {
            FirebaseManager.shared.stopListenUserProfile(email: user.email)
        }
        hotUsers.removeAll()
    }

    @MainActor
    private func seedHotUserPool(with messages: [ChatMessage]) {
        guard !messages.isEmpty else { return }
        
        // 최근 메시지 순으로 정렬 후, 서로 다른 이메일 기준으로 maxHotUsers까지 채우기
        let sorted = messages.sorted { $0.sentAt ?? Date() > $1.sentAt ?? Date() }
        var seen = Set<String>()

        for msg in sorted {
            let email = msg.senderID
            guard !email.isEmpty else { continue }
            if !seen.insert(email).inserted { continue }
            updateHotUserPool(for: email, lastSeenAt: msg.sentAt ?? Date())
            if hotUsers.count >= maxHotUsers { break }
        }
    }

    // 이미지 캐싱 전용
    private func cacheImagesIfNeeded(for message: ChatMessage) async {
        guard !message.attachments.isEmpty else { return }

        // 사전 로드할 썸네일 배열(첨부 index 순서 유지)
        let imageAttachments = message.attachments
            .filter { $0.type == .image }
            .sorted { $0.index < $1.index }

        // 이미 이미지 썸네일 캐싱을 끝낸 메시지는 스킵 (비디오 썸네일과 레이스 방지)
        let alreadyPrepared: Bool = await MainActor.run { self.preparedImageThumbMessageIDs.contains(message.ID) }
        if alreadyPrepared { return }

        for attachment in imageAttachments {
            let key = attachment.hash
            do {
                let cache = KingfisherManager.shared.cache
                cache.memoryStorage.config.expiration = .seconds(3600)
                cache.diskStorage.config.expiration = .days(3)

                if await KingFisherCacheManager.shared.isCached(key) {
                    if let img = await KingFisherCacheManager.shared.loadImage(named: key) {
                        await MainActor.run { self.messageImages[message.ID, default: []].append(img) }
                    }
                } else {
                    let img = try await FirebaseStorageManager.shared.fetchImageFromStorage(image: attachment.pathThumb, location: .RoomImage)
                    KingFisherCacheManager.shared.storeImage(img, forKey: key)
                    await MainActor.run { self.messageImages[message.ID, default: []].append(img) }
                }
            } catch {
                print(#function, "이미지 캐시 실패: \(error)")
            }
        }
        await MainActor.run {
            self.preparedImageThumbMessageIDs.insert(message.ID)
            self.reloadVisibleMessageIfNeeded(messageID: message.ID)
        }
    }

    // 동영상 썸네일 캐시 + 원본 URL warm-up (로컬 실패 메시지 썸네일도 지원)
    private func cacheVideoAssetsIfNeeded(for message: ChatMessage, in roomID: String) async {
        let videoAttachments = message.attachments
            .filter { $0.type == .video }
            .sorted { $0.index < $1.index }

        guard !videoAttachments.isEmpty else { return }

        let alreadyPrepared: Bool = await MainActor.run { self.preparedVideoThumbMessageIDs.contains(message.ID) }
        if alreadyPrepared { return }
        
        for attachment in videoAttachments {
            // 1) 썸네일 캐시
            let thumbPath = attachment.pathThumb
            let key = attachment.hash.isEmpty ? thumbPath : attachment.hash

            if !thumbPath.isEmpty {
                do {
                    let cache = KingfisherManager.shared.cache
                    cache.memoryStorage.config.expiration = .seconds(3600)
                    cache.diskStorage.config.expiration = .days(3)

                    if await KingFisherCacheManager.shared.isCached(key) {
                        if let img = await KingFisherCacheManager.shared.loadImage(named: key) {
                            await MainActor.run { self.messageImages[message.ID, default: []].append(img) }
                        }
                    } else {
                        // 로컬 경로(실패 메시지)인지 확인 후 분기
                        let isLocalFile = thumbPath.hasPrefix("/") || thumbPath.hasPrefix("file://")
                        if isLocalFile {
                            let fileURL = thumbPath.hasPrefix("file://") ? URL(string: thumbPath)! : URL(fileURLWithPath: thumbPath)
                            if let data = try? Data(contentsOf: fileURL),
                               let img = UIImage(data: data) {
                                KingFisherCacheManager.shared.storeImage(img, forKey: key)
                                await MainActor.run { self.messageImages[message.ID, default: []].append(img) }
                            }
                        } else {
                            let img = try await FirebaseStorageManager.shared.fetchImageFromStorage(image: thumbPath, location: .RoomImage)
                            KingFisherCacheManager.shared.storeImage(img, forKey: key)
                            await MainActor.run { self.messageImages[message.ID, default: []].append(img) }
                        }
                    }
                } catch {
                    print(#function, "🎬 비디오 썸네일 캐시 실패:", error)
                }
            }

            // 2) 원본 비디오 downloadURL warm-up (성공 메시지에만 적용)
            let path = attachment.pathOriginal
            if !path.isEmpty, !path.hasPrefix("/") {
                _ = try? await storageURLCache.url(for: path)
            }
        }
        await MainActor.run {
            self.preparedVideoThumbMessageIDs.insert(message.ID)
            self.reloadVisibleMessageIfNeeded(messageID: message.ID)
        }
    }

    @MainActor
    private func setupChatUI() {
        // 이전 상태(참여 전)에 설정된 제약을 정리하기 위해, 중복 추가를 방지하고 기존 제약과 충돌하지 않도록 제거
        if chatMessageCollectionView.superview != nil {
            chatMessageCollectionView.removeFromSuperview()
        }
        if chatUIView.superview != nil {
            chatUIView.removeFromSuperview()
        }
        
        view.addSubview(chatUIView)
        chatUIView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chatMessageCollectionView)
        chatMessageCollectionView.translatesAutoresizingMaskIntoConstraints = false
        
        chatUIViewBottomConstraint = chatUIView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        NSLayoutConstraint.activate([
            chatUIView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatUIView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatUIViewBottomConstraint!,
            chatUIView.heightAnchor.constraint(greaterThanOrEqualToConstant: chatUIView.minHeight),
            
            chatMessageCollectionView.heightAnchor.constraint(equalTo: view.heightAnchor),
            chatMessageCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatMessageCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatMessageCollectionView.bottomAnchor.constraint(equalTo: chatUIView.topAnchor),
        ])
        
        view.bringSubviewToFront(chatUIView)
        view.bringSubviewToFront(customNavigationBar)
        chatMessageCollectionView.contentInset.top = self.view.safeAreaInsets.top + chatUIView.frame.height + 10
        chatMessageCollectionView.contentInset.bottom = 5
        
        NSLayoutConstraint.deactivate(joinConsraints)
        setupCopyReplyDeleteView()
    }
    
    @MainActor
    private func handleSendButtonTap() {
        guard let message = self.chatUIView.messageTextView.text,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let room = self.room else { return }
        
        self.chatUIView.messageTextView.text = nil
        self.chatUIView.updateHeight()
        self.chatUIView.sendButton.isEnabled = false
        
        let newMessage = ChatMessage(ID: UUID().uuidString, seq: 0, roomID: room.ID ?? "", senderID: LoginManager.shared.getUserEmail, senderNickname: LoginManager.shared.currentUserProfile?.nickname ?? "", senderAvatarPath: LoginManager.shared.currentUserProfile?.thumbPath, msg: message, sentAt: Date(), attachments: [], replyPreview: replyMessage)
        
        Task.detached {
            SocketIOManager.shared.sendMessage(room, newMessage)
        }
        
        if self.replyMessage != nil {
            self.replyMessage = nil
            self.replyView.isHidden = true
        }
    }
    
    //MARK: 첨부파일 관련
    @MainActor
    private func hideOrShowOptionMenu() {
        guard let image = self.chatUIView.attachmentButton.imageView?.image else { return }
        if image != UIImage(systemName: "xmark") {
            self.chatUIView.attachmentButton.setImage(UIImage(systemName: "xmark"), for: .normal)
            
            if self.chatUIView.messageTextView.isFirstResponder {
                self.chatUIView.messageTextView.resignFirstResponder()
            }
            
            self.attachmentView.isHidden = false
            self.attachmentView.alpha = 1
            
            self.chatUIViewBottomConstraint?.constant = -(self.attachmentView.frame.height + 10)
        } else {
            self.chatUIView.attachmentButton.setImage(UIImage(systemName: "plus"), for: .normal)
            self.attachmentView.isHidden = true
            self.attachmentView.alpha = 0
            
            self.chatUIViewBottomConstraint?.constant = -10
        }
    }

    // MARK: - Video playback helper (by Storage path with caching)
    /// storagePath (e.g., "videos/<room>/<message>/video.mp4")를 받아
    /// 1) 디스크 캐시에 있으면 즉시 로컬로 재생
    /// 2) 없으면 원격 URL로 먼저 재생 후 백그라운드로 캐싱
    @MainActor
    func playVideoForStoragePath(_ storagePath: String) async {
        guard !storagePath.isEmpty else { return }
        do {
            if let local = await OPVideoDiskCache.shared.exists(forKey: storagePath) {
                self.playVideo(from: local, storagePath: storagePath)
                return
            }
            let remote = try await storageURLCache.url(for: storagePath)
            self.playVideo(from: remote, storagePath: storagePath)
            Task.detached { _ = try? await OPVideoDiskCache.shared.cache(from: remote, key: storagePath) }
        } catch {
            AlertManager.showAlertNoHandler(
                title: "재생 실패",
                message: "동영상을 불러오지 못했습니다.\n\(error.localizedDescription)",
                viewController: self
            )
        }
    }
    
    // 플레이어 오버레이에 저장 버튼 추가
    @MainActor
    private func addSaveButton(to playerVC: AVPlayerViewController, localURL: URL?, storagePath: String?) {
        guard let overlay = playerVC.contentOverlayView else { return }

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "square.and.arrow.down"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor(white: 0, alpha: 0.5)
        button.layer.cornerRadius = 22
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            Task { await self.handleSaveVideoTapped(from: playerVC, localURL: localURL, storagePath: storagePath) }
        }, for: .touchUpInside)

        overlay.addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -16),
            button.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -24),
            button.heightAnchor.constraint(equalToConstant: 44),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }
    
    // 저장 버튼 탭 → 사진 앱에 저장
    @MainActor
    private func handleSaveVideoTapped(from playerVC: AVPlayerViewController, localURL: URL?, storagePath: String?) async {
        let hud = CircularProgressHUD.show(in: playerVC.view, title: nil)
        hud.setProgress(0.15)

        do {
            let fileURL = try await resolveLocalFileURLForSaving(localURL: localURL, storagePath: storagePath) { frac in
                Task { @MainActor in hud.setProgress(0.15 + 0.75 * frac) }
            }

            let granted = await requestPhotoAddPermission()
            guard granted else {
                hud.dismiss()
                AlertManager.showAlertNoHandler(
                    title: "저장 불가",
                    message: "사진 앱 저장 권한이 필요합니다. 설정 > 개인정보보호에서 권한을 허용해 주세요.",
                    viewController: self
                )
                return
            }

            try await saveVideoToPhotos(fileURL: fileURL)
            hud.setProgress(1.0); hud.dismiss()
            AlertManager.showAlertNoHandler(
                title: "저장 완료",
                message: "사진 앱에 동영상을 저장했습니다.",
                viewController: self
            )
        } catch {
            hud.dismiss()
            AlertManager.showAlertNoHandler(
                title: "저장 실패",
                message: error.localizedDescription,
                viewController: self
            )
        }
    }
    
    private func requestPhotoAddPermission() async -> Bool {
        if #available(iOS 14, *) {
            let s = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            if s == .authorized || s == .limited { return true }
            let ns = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return ns == .authorized || ns == .limited
        } else {
            let s = PHPhotoLibrary.authorizationStatus()
            if s == .authorized { return true }
            let ns = await withCheckedContinuation { (cont: CheckedContinuation<PHAuthorizationStatus, Never>) in
                PHPhotoLibrary.requestAuthorization { cont.resume(returning: $0) }
            }
            return ns == .authorized
        }
    }

    private func saveVideoToPhotos(fileURL: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }) { ok, err in
                if let err = err {
                    cont.resume(throwing: err)
                    return
                }
                if ok {
                    cont.resume(returning: ())
                } else {
                    cont.resume(throwing: NSError(domain: "SaveVideo", code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "Unknown error while saving video"]))
                }
            }
        }
    }

    /// 저장용 로컬 파일 확보:
    /// - localURL이 file://이면 그대로 사용
    /// - storagePath 캐시가 있으면 캐시 파일 사용
    /// - 아니면 downloadURL로 내려받아 임시파일로 저장
    private func resolveLocalFileURLForSaving(localURL: URL?, storagePath: String?, onProgress: @escaping (Double)->Void) async throws -> URL {
        if let localURL, localURL.isFileURL { return localURL }

        if let storagePath,
           let cached = await OPVideoDiskCache.shared.exists(forKey: storagePath) {
            return cached
        }

        if let storagePath {
            let remote = try await storageURLCache.url(for: storagePath)
            return try await downloadToTemporaryFile(from: remote, onProgress: onProgress)
        }

        if let remote = localURL, (remote.scheme?.hasPrefix("http") == true) {
            return try await downloadToTemporaryFile(from: remote, onProgress: onProgress)
        }

        throw NSError(domain: "SaveVideo", code: -2,
                      userInfo: [NSLocalizedDescriptionKey: "저장할 파일 경로를 확인할 수 없습니다."])
    }

    private func downloadToTemporaryFile(from remote: URL, onProgress: @escaping (Double)->Void) async throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("save_\(UUID().uuidString).mp4")
        let (data, _) = try await URLSession.shared.data(from: remote)
        try data.write(to: tmp, options: .atomic)
        onProgress(1.0)
        return tmp
    }
    
    @MainActor
    private func playVideo(from url: URL, storagePath: String? = nil) {
        let asset = AVURLAsset(url: url)
        let item  = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        let vc = AVPlayerViewController()
        vc.player = player

        present(vc, animated: true) { [weak self] in
            player.play()
            self?.addSaveButton(to: vc, localURL: url, storagePath: storagePath)
        }
    }
    
    private func openCamera() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self
            imagePicker.allowsEditing = true
            imagePicker.sourceType = .camera
            
            present(imagePicker, animated: true, completion: nil)
        }
    }
    
    private func openPHPicker() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 0
        configuration.selection = .ordered
        configuration.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    private func setupAttachmentView() {
        DispatchQueue.main.async {
            self.view.addSubview(self.attachmentView)
            
            NSLayoutConstraint.activate([
                self.attachmentView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
                self.attachmentView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
                self.attachmentView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
                self.attachmentView.heightAnchor.constraint(equalToConstant: 100),
            ])
        }
    }
    
    @MainActor
    private func handleAttachmentButtonTap(identifier: String) {
        switch identifier {
        case "photo":
            print("Photo btn tapped!")
            self.hideOrShowOptionMenu()
            self.openPHPicker()
            
        case "camera":
            print("Camera btn tapped!")
            self.hideOrShowOptionMenu()
            self.openCamera()
            
        case "attachmentButton":
            self.hideOrShowOptionMenu()
            
        case "sendButton":
            self.handleSendButtonTap()
        default:
            return
        }
    }
    
    // MARK: 방 관련
    // Prevent duplicated join flow / duplicated loading HUDs
    private var isJoiningRoom: Bool = false
    private func setUpNotifications() {
        // 방 저장 관련
        NotificationCenter.default.addObserver(self, selector: #selector(handleRoomSaveCompleted), name: .roomSavedComplete, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRoomSaveFailed), name: .roomSaveFailed, object: nil)
    }
    
    @MainActor
    private func bindRoomChangePublisher() {
        if hasBoundRoomChange { return }
        hasBoundRoomChange = true
        
        // 실시간 방 업데이트 관련
        FirebaseManager.shared.roomChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedRoom in
                guard let self = self else { return }
                let previousRoom = self.room
                self.room = updatedRoom
                print(#function, "ChatViewController.swift 방 정보 변경: \(updatedRoom)")
                Task { @MainActor in
                    await self.applyRoomDiffs(old: previousRoom, new: updatedRoom)
                }
            }
            .store(in: &cancellables)
    }
    
    /// 방 정보(old → new) 변경점을 비교하고 필요한 UI/동기화만 수행
    @MainActor
    private func applyRoomDiffs(old: ChatRoom?, new: ChatRoom) async {
        // 최초 바인딩 또는 이전 정보가 없을 때: 전체 초기화 느낌으로 처리
        guard let old = old else {
            updateNavigationTitle(with: new)
            setupAnnouncementBannerIfNeeded()
            updateAnnouncementBanner(with: new.activeAnnouncement)
            return
        }
        
        // 1) 타이틀/참여자 수 변경 시 상단 네비바만 갱신
        if old.roomName != new.roomName || old.participants.count != new.participants.count {
            updateNavigationTitle(with: new)
        }
        
        // 2) 참여자 변경 시, 새로 추가된 사용자만 동기화(최소화)
        let oldSet = Set(old.participants)
        let newSet = Set(new.participants)
        let joined = Array(newSet.subtracting(oldSet))
        
        // 3) 공지 변경 감지: ID/업데이트 시각/본문/작성자 중 하나라도 달라지면 배너 갱신
        let announcementChanged: Bool = {
            if old.activeAnnouncementID != new.activeAnnouncementID { return true }
            if old.announcementUpdatedAt != new.announcementUpdatedAt { return true }
            if old.activeAnnouncement?.text != new.activeAnnouncement?.text { return true }
            if old.activeAnnouncement?.authorID != new.activeAnnouncement?.authorID { return true }
            return false
        }()
        if announcementChanged {
            setupAnnouncementBannerIfNeeded()
            updateAnnouncementBanner(with: new.activeAnnouncement)
        }
    }
    
    @objc private func handleRoomSaveCompleted(notification: Notification) {
        guard let savedRoom = notification.userInfo?["room"] as? ChatRoom else { return }
        self.room = savedRoom
        Task {
            FirebaseManager.shared.startListenRoomDoc(roomID: savedRoom.ID ?? "")
            
            if SocketIOManager.shared.isConnected {
                SocketIOManager.shared.createRoom(savedRoom.ID ?? "")
                SocketIOManager.shared.joinRoom(savedRoom.ID ?? "")
            }
        }
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.updateNavigationTitle(with: savedRoom)
            LoadingIndicator.shared.stop()
            self.view.isUserInteractionEnabled = true
        }
    }
    
    @objc private func handleRoomSaveFailed(notification: Notification) {
        LoadingIndicator.shared.stop()
        
        guard let error = notification.userInfo?["error"] as? RoomCreationError else { return }
        showAlert(error: error)
    }

    // MARK: 초기 UI 설정 관련
    @MainActor
    private func decideJoinUI() {
        guard let room = room else { return }
        
        Task {
            if room.participants.contains(LoginManager.shared.getUserEmail) {
                setupChatUI()
                chatUIView.isHidden = false
                joinRoomBtn.isHidden = true
                self.bindRoomChangePublisher()
                self.setupAnnouncementBannerIfNeeded()
                self.updateAnnouncementBanner(with: room.activeAnnouncement)
            } else {
                setJoinRoombtn()
                joinRoomBtn.isHidden = false
                chatUIView.isHidden = true
                self.customNavigationBar.rightStack.isUserInteractionEnabled = false
            }
            
            updateNavigationTitle(with: room)
        }
    }
    
    private func setJoinRoombtn() {
        self.joinRoomBtn.clipsToBounds = true
        self.joinRoomBtn.layer.cornerRadius = 20
        self.joinRoomBtn.backgroundColor = UIColor(white: 0.1, alpha: 0.05)
        joinRoomBtn.translatesAutoresizingMaskIntoConstraints = false
        
        if chatMessageCollectionView.superview == nil {
            view.addSubview(chatMessageCollectionView)
            chatMessageCollectionView.translatesAutoresizingMaskIntoConstraints = false
            
            NSLayoutConstraint.activate([
                chatMessageCollectionView.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor),
                chatMessageCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                chatMessageCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        }
        
        NSLayoutConstraint.deactivate(chatConstraints)
        
        joinConsraints = [
            chatMessageCollectionView.bottomAnchor.constraint(equalTo: joinRoomBtn.topAnchor)
        ]
        NSLayoutConstraint.activate(joinConsraints)
    }
    
    @MainActor
    @IBAction func joinRoomBtnTapped(_ sender: UIButton) {
        guard let room = self.room else { return }
        // Prevent double taps / duplicated HUDs
        guard !isJoiningRoom else { return }
        isJoiningRoom = true

        LoadingIndicator.shared.stop()
        LoadingIndicator.shared.start(on: self)

        joinRoomBtn.isHidden = true
        customNavigationBar.rightStack.isUserInteractionEnabled = true

        NSLayoutConstraint.deactivate(joinConsraints)
        joinConsraints.removeAll()
        if chatMessageCollectionView.superview != nil {
            chatMessageCollectionView.removeFromSuperview()
        }

        Task {
            do {
                // 1. 소켓 연결 (async/await 버전)
                if SocketIOManager.shared.isConnected {
                    SocketIOManager.shared.joinRoom(room.ID ?? "")
                    SocketIOManager.shared.listenToNewParticipant()
                }

                // 2. Firebase에 참여자 등록 및 최신 room 정보 fetch
                guard let ID = room.ID else { return }
                let updated = try await FirebaseManager.shared.add_room_participant_returningRoom(roomID: ID)
                self.room = updated
                FirebaseManager.shared.applyLocalRoomUpdate(updated)
                
                // 4. UI 업데이트
                await MainActor.run {
                    self.setupChatUI()
                    self.chatUIView.isHidden = false
                    self.chatMessageCollectionView.isHidden = false
                    self.bindRoomChangePublisher()
                    FirebaseManager.shared.startListenRoomDoc(roomID: ID)
                    self.view.layoutIfNeeded()
                }
                LoadingIndicator.shared.stop()
                self.isJoiningRoom = false
                print(#function, "✅ 방 참여 성공, UI 업데이트 완료")

            } catch {
                print("❌ 방 참여 처리 실패: \(error)")
                await MainActor.run {
                    self.joinRoomBtn.isHidden = false
                    self.customNavigationBar.rightStack.isUserInteractionEnabled = false
                    LoadingIndicator.shared.stop()
                    self.isJoiningRoom = false
                }
            }
        }
    }
    
    //MARK: 커스텀 내비게이션 바
    @MainActor
    @objc private func backButtonTapped() {
        // ✅ 표준 네비게이션으로만 되돌아가기 (root 교체 금지)
        // 1) 내비게이션 스택 우선
        if let nav = self.navigationController {
            // 바로 아래가 RoomCreateViewController이면, 그 이전 화면(또는 루트)로 복귀
            if let idx = nav.viewControllers.firstIndex(of: self), idx > 0, nav.viewControllers[idx-1] is RoomCreateViewController {
                if idx >= 2 {
                    let target = nav.viewControllers[idx-2]
                    nav.popToViewController(target, animated: true)
                } else {
                    nav.popToRootViewController(animated: true)
                }
            } else {
                nav.popViewController(animated: true)
            }
            return
        }

        // 2) 모달 표시된 경우에는 단순 dismiss
        if self.presentingViewController != nil {
            self.dismiss(animated: true)
            return
        }

        // 3) 폴백: 탭바 아래의 내비게이션이 있으면 루트로 복귀
        if let tab = self.view.window?.rootViewController as? UITabBarController,
           let nav = tab.selectedViewController as? UINavigationController {
            nav.popToRootViewController(animated: true)
            return
        }
    }

    @MainActor
    private func pruneRoomCreateFromNavStackIfNeeded() {
        guard let nav = self.navigationController,
              let idx = nav.viewControllers.firstIndex(of: self),
              idx > 0, nav.viewControllers[idx-1] is RoomCreateViewController else { return }
        var vcs = nav.viewControllers
        vcs.remove(at: idx-1)
        nav.setViewControllers(vcs, animated: false)
    }

    @MainActor
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.attachInteractiveDismissGesture()
        
        if let room = self.room {
            ChatViewController.currentRoomID = room.ID
        } // ✅ 현재 방 ID 저장
        pruneRoomCreateFromNavStackIfNeeded()
    }
    
    @objc private func settingButtonTapped() {
        Task { @MainActor in
            guard let room = self.room else { return }
            let roomID = room.ID ?? ""
            
//            let (profiles, imageNames): ([UserProfile], [String]) = try await Task.detached(priority: .utility) {
//                let p = try GRDBManager.shared.fetchUserProfiles(inRoom: roomID)
//                let names = try GRDBManager.shared.fetchImageNames(inRoom: roomID)
//                return (p, names)
//            }.value
//
//            var images = [UIImage]()
//            for imageName in imageNames {
//                if let image = await KingFisherCacheManager.shared.loadImage(named: imageName) {
//                    images.append(image)
//                }
//            }
            
            self.detachInteractiveDismissGesture()
            
            let settingVC = ChatRoomSettingCollectionView(room: room, profiles: [], images: [])
            self.presentSettingVC(settingVC)
            
            settingVC.onRoomUpdated = { [weak self] updatedRoom in
                guard let self = self else { return }
                Task { @MainActor in
                    self.room = updatedRoom
                    self.updateNavigationTitle(with: updatedRoom)
                }
            }
        }
        
    }
    
    @MainActor
    private func presentSettingVC(_ VC: ChatRoomSettingCollectionView) {
        guard settingPanelVC == nil else { return }
        settingPanelVC = VC
        
        if dimView.superview == nil {
            view.addSubview(dimView)
            
            let dimTap = UITapGestureRecognizer(target: self, action: #selector(didTapDimView))
            dimTap.cancelsTouchesInView = true
            dimView.addGestureRecognizer(dimTap)
            tapGesture.require(toFail: dimTap)
            
            NSLayoutConstraint.activate([
                dimView.topAnchor.constraint(equalTo: view.topAnchor),
                dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
        
        addChild(VC)
        view.addSubview(VC.view)
        VC.didMove(toParent: self)
        
        let width = floor(view.bounds.width * 0.7)
        let height = view.bounds.height
        let targetX = view.bounds.width - width
        
        VC.view.layer.cornerRadius = 16
        VC.view.clipsToBounds = true
        VC.view.frame = CGRect(x: view.bounds.width, y: 0, width: width, height: height)
        
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
            self.dimView.alpha = 1
            VC.view.frame.origin.x = targetX
        }
    }
    
    @objc private func didTapDimView() {
        dismissSettingVC()
    }
    
    @MainActor
    private func dismissSettingVC() {
        guard let VC = settingPanelVC else { return }
        
        print(#function, "호출")
        
        VC.willMove(toParent: nil)
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseIn]) {
            self.dimView.alpha = 0
            VC.view.frame.origin.x = self.view.bounds.width
        } completion: { _ in
            VC.view.removeFromSuperview()
            VC.removeFromParent()
            self.settingPanelVC = nil
        }
        
        self.attachInteractiveDismissGesture()
    }
    
    @MainActor
    private func updateNavigationTitle(with room: ChatRoom) {
        // ✅ 커스텀 내비게이션 바 타이틀 업데이트
        customNavigationBar.configureForChatRoom(
            roomTitle: room.roomName,
            participantCount: room.participants.count,
            target: self,
            onBack: #selector(backButtonTapped),
            onSearch: #selector(searchButtonTapped),
            onSetting: #selector(settingButtonTapped)
        )
    }
    
    //MARK: 대화 내용 검색
    private func bindSearchEvents() {
        customNavigationBar.searchKeywordPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] keyword in
                guard let self = self else { return }
                
                self.clearPreviousHighlightIfNeeded()
                
                guard let keyword = keyword, !keyword.isEmpty else {
                    print(#function, "✅✅✅✅✅ keyword is empty ✅✅✅✅✅")
                    return
                }
                filterMessages(containing: keyword)
            }
            .store(in: &cancellables)
        
        customNavigationBar.cancelSearchPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self else { return }
                self.exitSearchMode()
            }
            .store(in: &cancellables)
        
        searchUI.upPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self else { return }
                currentFilteredMessageIndex! -= 1
                searchUI.updateSearchResult(filteredMessages.count, currentFilteredMessageIndex!)
                moveToMessageAndShake(currentFilteredMessageIndex!)
            }
            .store(in: &cancellables)
        
        searchUI.downPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self else { return }
                currentFilteredMessageIndex! += 1
                searchUI.updateSearchResult(filteredMessages.count, currentFilteredMessageIndex!)
                moveToMessageAndShake(currentFilteredMessageIndex!)
            }
            .store(in: &cancellables)
    }
    
    @MainActor
    private func filterMessages(containing keyword: String) {
        Task {
            do {
                guard let room = self.room else { return }
                filteredMessages = try await GRDBManager.shared.fetchMessages(in: room.ID ?? "", containing: keyword)
                currentFilteredMessageIndex = filteredMessages.isEmpty == true ? nil : filteredMessages.count
                currentSearchKeyword = keyword
                highlightedMessageIDs = Set(filteredMessages.map { $0.ID })
                applyHighlight()
                
            } catch {
                print("메시지 없음")
            }
        }
    }
    
    @MainActor
    private func moveToMessageAndShake(_ idx: Int) {
        let message = filteredMessages[idx-1]
        guard let indexPath = indexPath(of: message) else { return }
        
        if let cell = chatMessageCollectionView.cellForItem(at: indexPath) as? ChatMessageCell {
            cell.shakeHorizontally()
        } else {
            chatMessageCollectionView.scrollToMessage(at: indexPath)
            scrollTargetIndex = indexPath
        }
    }
    
    @MainActor
    private func applyHighlight() {
        var snapshot = dataSource.snapshot()
        
        let itemsToRealod = snapshot.itemIdentifiers.compactMap { item -> Item? in
            if case let .message(message) = item, highlightedMessageIDs.contains(message.ID){
                return .message(message)
            }
            return nil
        }
        
        if !itemsToRealod.isEmpty {
            snapshot.reconfigureItems(itemsToRealod)
            dataSource.apply(snapshot, animatingDifferences: false)
        }
        
        searchUI.updateSearchResult(highlightedMessageIDs.count, currentFilteredMessageIndex ?? 0)
        if let idx = currentFilteredMessageIndex { moveToMessageAndShake(idx) }
    }
    
    @MainActor
    private func clearPreviousHighlightIfNeeded() {
        var snapshot = dataSource.snapshot()
        
        let itemsToRealod = snapshot.itemIdentifiers.compactMap { item -> Item? in
            if case let .message(message) = item, highlightedMessageIDs.contains(message.ID){
                return .message(message)
            }
            return nil
        }
        
        highlightedMessageIDs.removeAll()
        currentSearchKeyword = nil
        scrollTargetIndex = nil
        
        if !itemsToRealod.isEmpty {
            snapshot.reconfigureItems(itemsToRealod)
            dataSource.apply(snapshot, animatingDifferences: false)
        }
        
        searchUI.updateSearchResult(highlightedMessageIDs.count, currentFilteredMessageIndex ?? 0)
    }
    
    @MainActor
    private func exitSearchMode() {
        // 🔹 Search UI 숨기고 Chat UI 복원
        self.searchUI.isHidden = true
        self.chatUIView.isHidden = false
        
        clearPreviousHighlightIfNeeded()
    }
    
    @MainActor
    private func setupSearchUI() {
        if searchUI.superview == nil {
            view.addSubview(searchUI)
            searchUIBottomConstraint = searchUI.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -10)
            
            NSLayoutConstraint.activate([
                searchUI.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                searchUI.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                searchUIBottomConstraint!,
                searchUI.heightAnchor.constraint(equalToConstant: 50)
            ])
        }
    }
    
    @MainActor
    @objc private func searchButtonTapped() {
        customNavigationBar.switchToSearchMode()
        setupSearchUI()
        
        searchUI.isHidden = false
        chatUIView.isHidden = true
    }
    
    private func indexPath(of message: ChatMessage) -> IndexPath? {
        let snapshot = dataSource.snapshot()
        let items = snapshot.itemIdentifiers(inSection: .main)
        if let row = items.firstIndex(where: { $0 == .message(message) }) {
            return IndexPath(item: row, section: 0)
        } else {
            return nil
        }
    }
    
    //MARK: 메시지 삭제/답장/복사 관련
    @MainActor
    private func showCustomMenu(at indexPath: IndexPath/*, aboveCell: Bool*/) {
        guard let cell = chatMessageCollectionView.cellForItem(at: indexPath) as? ChatMessageCell,
              let item = dataSource.itemIdentifier(for: indexPath),
              case let .message(message) = item,
              message.isDeleted == false else { return }
        
        // 1.셀 강조하기
        cell.setHightlightedOverlay(true)
        highlightedCell = cell
        
        // 셀의 bounds 기준으로 컬렉션뷰 내 프레임 계산
        let cellFrameInCollection = cell.convert(cell.bounds, to: chatMessageCollectionView/*.collectionView*/)
        let cellCenterY = cellFrameInCollection.midY
        
        // 컬렉션 뷰 기준 중앙 사용 (화면 절반)
        let screenMiddleY = chatMessageCollectionView.bounds.midY
        let showAbove: Bool = cellCenterY > screenMiddleY
        
        // 신고 or 삭제 결정
        if let userProfile = LoginManager.shared.currentUserProfile,
           let room = self.room {
            let isOwner = userProfile.nickname == message.senderNickname
            let isAdmin = room.creatorID == userProfile.email
            
            chatCustomMenu.configurePermissions(canDelete: isOwner || isAdmin, canAnnounce: isAdmin)
        }
        
        // 2.메뉴 위치를 셀 기준으로
        view.addSubview(chatCustomMenu)
        NSLayoutConstraint.activate([
            showAbove ? chatCustomMenu.bottomAnchor.constraint(equalTo: cell.referenceView.topAnchor, constant: -8) : chatCustomMenu.topAnchor.constraint(equalTo: cell.referenceView.bottomAnchor, constant: 8),
            
            LoginManager.shared.userProfile?.nickname == message.senderNickname ? chatCustomMenu.trailingAnchor.constraint(equalTo: cell.referenceView.trailingAnchor, constant: 0) : chatCustomMenu.leadingAnchor.constraint(equalTo: cell.referenceView.leadingAnchor, constant: 0)
        ])
        
        // 3. 버튼 액션 설정
        setChatMenuActions(for: message)
    }
    
    private func setChatMenuActions(for message: ChatMessage) {
        chatCustomMenu.onReply = { [weak self] in
            guard let self = self else { return }
            self.handleReply(message: message)
            self.dismissCustomMenu()
        }
        
        chatCustomMenu.onCopy = { [weak self] in
            guard let self = self else { return }
            self.handleCopy(message: message)
            self.dismissCustomMenu()
        }
        
        chatCustomMenu.onDelete = { [weak self] in
            guard let self = self else { return }
            ConfirmView.present(in: self.view,
                                message: "삭제 시 모든 사용자의 채팅창에서 메시지가 삭제되며\n‘삭제된 메시지입니다.’로 표기됩니다.",
                                onConfirm: { [weak self] in
                guard let self = self else { return }
                self.handleDelete(message: message)
            })
            self.dismissCustomMenu()
        }
        
        chatCustomMenu.onReport = { [weak self] in
            self?.handleReport(message: message)
            self?.dismissCustomMenu()
        }
        
        chatCustomMenu.onAnnounce = { [weak self] in
            guard let self = self else { return }
            print(#function, "공지:", message.msg ?? "")
            
            ConfirmView.presentAnnouncement(in: self.view, onConfirm: { [weak self] in
                guard let self = self else { return }
                self.handleAnnouncement(message)
            })
            
            self.dismissCustomMenu()
        }
    }
    
    private func handleAnnouncement(_ message: ChatMessage) {
        let announcement = AnnouncementPayload(text: message.msg ?? "", authorID: LoginManager.shared.currentUserProfile?.nickname ?? "", createdAt: Date())
        Task { @MainActor in
            guard let room = self.room else { return }
            try await FirebaseManager.shared.setActiveAnnouncement(roomID: room.ID ?? "", messageID: message.ID, payload: announcement)
            showSuccess("공지를 등록했습니다.")
        }
    }
    
    @MainActor
    private func handleReport(message: ChatMessage) {
        print(#function, "신고:", message.msg ?? "")
        // 필요 시 UI 피드백
        showSuccess("메시지가 신고되었습니다.")
    }
    
    @MainActor
    private func handleReply(message: ChatMessage) {
        print(#function, "답장:", message)
        self.replyMessage = ReplyPreview(messageID: message.ID, sender: message.senderNickname, text: message.msg ?? "", isDeleted: false)
        replyView.configure(with: message)
        replyView.isHidden = false
    }
    
    private func handleCopy(message: ChatMessage) {
        UIPasteboard.general.string = message.msg
        print(#function, "복사:", message)
        // 필요 시 UI 피드백
        showSuccess("메시지가 복사되었습니다.")
    }
    
    private func handleDelete(message: ChatMessage) {
        Task {
            guard let room = self.room else { return }
            let messageID = message.ID
            do {
                // 1. GRDB 업데이트
                try await GRDBManager.shared.updateMessagesIsDeleted([messageID], isDeleted: true, inRoom: room.ID ?? "")
                try GRDBManager.shared.deleteImageIndex(forMessageID: messageID, inRoom: roomID)
                
                // 2. Firestore 업데이트
                do {
                    try await FirebaseManager.shared.updateMessageIsDeleted(roomID: room.ID ?? "", messageID: messageID)
                    
                    // Gather non-empty, unique paths from attachments
                    let rawPaths: [String] = message.attachments.flatMap { att in
                        return [att.pathThumb, att.pathOriginal]
                    }.compactMap { $0 }.filter { !$0.isEmpty }
                    
                    guard !rawPaths.isEmpty else { return }
                    
                    var seen = Set<String>()
                    let uniquePaths = rawPaths.filter { seen.insert($0).inserted }
                    
                    await withTaskGroup(of: Void.self) { group in
                        for path in uniquePaths {
                            group.addTask { [weak self] in
                                guard self != nil else { return }
                                FirebaseStorageManager.shared.deleteImageFromStorage(path: path)
                            }
                        }
                    }
                    
                    print("✅ 메시지 삭제 성공: \(messageID)")
                } catch {
                    print("❌ 메시지 Firestore 삭제 처리 실패:", error)
                }
            } catch {
                print("❌ 메시지 삭제 처리 실패:", error)
            }
        }
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let location = gesture.location(in: chatMessageCollectionView)
        if let indexPath = chatMessageCollectionView.indexPathForItem(at: location) {
            guard let room = self.room,
                  room.participants.contains(LoginManager.shared.getUserEmail) else { return }
            showCustomMenu(at: indexPath)
        }
    }
    
    @objc private func handleAnnouncementBannerLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let room = self.room,
              room.creatorID == LoginManager.shared.getUserEmail else { return }
        
        // 확인 팝업 → 삭제 실행
        ConfirmView.present(
            in: self.view,
            message: "현재 공지를 삭제할까요?\n삭제 시 모든 사용자의 배너에서 사라집니다.",
            style: .prominent,
            onConfirm: { [weak self] in
                guard let self = self else { return }
                Task { @MainActor in
                    do {
                        try await FirebaseManager.shared.clearActiveAnnouncement(roomID: room.ID ?? "")
                        self.updateAnnouncementBanner(with: nil)   // 배너 숨김 + 인셋 복원
                        self.showSuccess("공지를 삭제했습니다.")
                    } catch {
                        self.showSuccess("공지 삭제에 실패했습니다.")
                        print("❌ 공지 삭제 실패:", error)
                    }
                }
            }
        )
    }
    
    private func dismissCustomMenu() {
        if let cell = highlightedCell { cell.setHightlightedOverlay(false) }
        highlightedCell = nil
        chatCustomMenu.removeFromSuperview()
    }
    
    @MainActor
    private func showSuccess(_ text: String) {
        notiView.configure(text)
        
        if notiView.isHidden { notiView.isHidden = false }
        
        // 초기 상태: 보이지 않고, 약간 축소 상태
        self.notiView.alpha = 0
        self.notiView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        
        // fade-in + 확대 애니메이션
        UIView.animate(withDuration: 0.5, animations: {
            self.notiView.alpha = 1
            self.notiView.transform = .identity
        }) { _ in
            // fade-out만, scale 변화 없이 진행
            UIView.animate(withDuration: 0.5, delay: 0.6, options: [], animations: {
                self.notiView.alpha = 0
            }, completion: { _ in
                // 초기 상태로 transform은 유지 (확대 상태 유지)
                self.notiView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            })
        }
    }
    
    @MainActor
    private func setupAnnouncementBannerIfNeeded() {
        guard announcementBanner.superview == nil else { return }
        
        view.addSubview(announcementBanner)
        NSLayoutConstraint.activate([
            announcementBanner.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor),
            announcementBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            announcementBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        // 기본 인셋 저장 (최초 한 번)
        if baseTopInsetForBanner == nil {
            baseTopInsetForBanner = chatMessageCollectionView.contentInset.top
        }
        view.bringSubviewToFront(announcementBanner)
    }
    
    /// 현재 활성 공지 배너를 갱신 (고정 배너 사용)
    @MainActor
    private func updateAnnouncementBanner(with payload: AnnouncementPayload?) {
        setupAnnouncementBannerIfNeeded()
        
        guard let payload = payload else {
            // 공지 없음 → 배너 숨김 및 인셋 복원
            if !announcementBanner.isHidden {
                announcementBanner.isHidden = true
                view.layoutIfNeeded()
                adjustForBannerHeight()
            }
            return
        }
        // 배너 구성 및 표시
        announcementBanner.configure(text: payload.text,
                                     authorID: payload.authorID,
                                     createdAt: payload.createdAt,
                                     pinned: true)
        if announcementBanner.isHidden { announcementBanner.isHidden = false }
        view.layoutIfNeeded()
        adjustForBannerHeight()
    }
    
    @MainActor
    private func adjustForBannerHeight() {
        guard let base = baseTopInsetForBanner else { return }
        let height = announcementBanner.isHidden ? 0 : announcementBanner.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        let extra = height > 0 ? height + 8 : 0
        var inset = chatMessageCollectionView.contentInset
        inset.top = base + extra
        chatMessageCollectionView.contentInset = inset
        chatMessageCollectionView.verticalScrollIndicatorInsets.top = inset.top
    }
    
    private func setupCopyReplyDeleteView() {
        view.addSubview(notiView)
        NSLayoutConstraint.activate([
            notiView.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width * 0.7),
            notiView.heightAnchor.constraint(equalTo: chatUIView.heightAnchor),
            
            notiView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            notiView.bottomAnchor.constraint(equalTo: chatUIView.topAnchor, constant: -10),
        ])
        view.bringSubviewToFront(notiView)
        
        view.addSubview(replyView)
        NSLayoutConstraint.activate([
            replyView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            replyView.bottomAnchor.constraint(equalTo: chatUIView.topAnchor, constant: -10),
            replyView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            replyView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            replyView.heightAnchor.constraint(equalToConstant: 43)
        ])
        view.bringSubviewToFront(replyView)
    }
    
    private func isCurrentUser(_ email: String?) -> Bool {
        return (email ?? "") == LoginManager.shared.getUserEmail
    }
    private func isCurrentUserAdmin(of room: ChatRoom) -> Bool {
        return room.creatorID == LoginManager.shared.getUserEmail
    }
    
    //MARK: Diffable Data Source
    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: chatMessageCollectionView) { [unowned self] collectionView, indexPath, item in
            switch item {
            case .message(let message):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatMessageCell.reuseIdentifier, for: indexPath) as! ChatMessageCell
                
                // 메시지 최신 상태 반영
                let latestMessage = self.messageMap[message.ID] ?? message
                let latestImages = self.messageImages[message.ID] ?? []
                
                if !latestMessage.attachments.isEmpty {
                    cell.configureWithImage(with: latestMessage, images: latestImages)
                } else {
                    cell.configureWithMessage(with: latestMessage)
                }
                
                // ✅ 구독 정리용 Bag 준비
                let key = ObjectIdentifier(cell)
                cellSubscriptions[key] = Set<AnyCancellable>()
                
                // 이미지/비디오 탭
                cell.imageTapPublisher
                    .sink { [weak self] tappedIndex in
                        guard let self else { return }
                        guard let i = tappedIndex else { return }

                        // 최신 메시지 상태 확인
                        let currentMessage = self.messageMap[message.ID] ?? message
                        let attachments = currentMessage.attachments.sorted { $0.index < $1.index }
                        guard i >= 0, i < attachments.count else { return }
                        let att = attachments[i]

                        if att.type == .video {
                            let path = att.pathOriginal
                            guard !path.isEmpty else { return }

                            // 로컬(실패 메시지) 경로면 바로 파일 재생, 아니면 Storage 경로로 캐시+재생
                            if path.hasPrefix("/") || path.hasPrefix("file://") {
                                let url = path.hasPrefix("file://") ? URL(string: path)! : URL(fileURLWithPath: path)
                                self.playVideo(from: url)
                            } else {
                                Task { @MainActor in
                                    await self.playVideoForStoragePath(path)
                                }
                            }
                        } else {
                            // 이미지 첨부 탭 → 기존 뷰어 유지
                            self.presentImageViewer(tappedIndex: i, indexPath: indexPath)
                        }
                    }
                    .store(in: &cellSubscriptions[key]!)
                
                let keyword = self.highlightedMessageIDs.contains(latestMessage.ID) ? self.currentSearchKeyword : nil
                cell.highlightKeyword(keyword)
                
                return cell
            case .dateSeparator(let date):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DateSeperatorCell.reuseIdentifier, for: indexPath) as! DateSeperatorCell
                
                let dateText = self.formatDateToDayString(date)
                cell.configureWithDate(dateText)
                
                return cell
                
            case .readMarker:
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: readMarkCollectionViewCell.reuseIdentifier, for: indexPath) as! readMarkCollectionViewCell
                
                cell.configure()
                return cell
            }
        }
        
        chatMessageCollectionView.setCollectionViewDataSource(dataSource)
        applySnapshot([])
    }
    
    // MARK: - Diffable animation heuristics
    private func shouldAnimateDifferences(for updateType: MessageUpdateType, newItemCount: Int) -> Bool {
        switch updateType {
        case .newer:
            // 사용자가 거의 바닥(최근 메시지 근처)에 있고, 새 항목이 소량일 때만 애니메이션
            return newItemCount > 0 && newItemCount <= 20 && isNearBottom()
        case .older, .reload, .initial:
            return false
        }
    }
    
    private func isNearBottom(threshold: CGFloat = 120) -> Bool {
        let contentHeight = chatMessageCollectionView.contentSize.height
        let visibleMaxY = chatMessageCollectionView.contentOffset.y + chatMessageCollectionView.bounds.height
        return (contentHeight - visibleMaxY) <= threshold
    }
    
    func applySnapshot(_ items: [Item]) {
        var snapshot = dataSource.snapshot()
        if snapshot.sectionIdentifiers.isEmpty { snapshot.appendSections([Section.main]) }
        snapshot.appendItems(items, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: false)
        chatMessageCollectionView.scrollToBottom()
    }
    
    @MainActor
    func addMessages(_ messages: [ChatMessage], updateType: MessageUpdateType = .initial) {
        // 빠른 가드: 빈 입력, reload 전용 처리
        guard !messages.isEmpty else { return }
        let windowSize = 300
        var snapshot = dataSource.snapshot()
        
        if updateType == .reload {
            reloadDeletedMessages(messages)
            return
        }
        
        // 1) 현재 스냅샷에 존재하는 메시지 ID 집합 (O(1) 조회)
        let existingIDs: Set<String> = Set(
            snapshot.itemIdentifiers.compactMap { item -> String? in
                if case .message(let m) = item { return m.ID }
                return nil
            }
        )
        
        // 2) 안정적 중복 제거(입력 배열 내 중복 ID 제거, 원래 순서 유지)
        var seen = Set<String>()
        var deduped: [ChatMessage] = []
        deduped.reserveCapacity(messages.count)
        for msg in messages {
            if !seen.contains(msg.ID) {
                seen.insert(msg.ID)
                deduped.append(msg)
            }
        }
        
        // 3) 이미 표시 중인 항목 제거
        let incoming = deduped.filter { !existingIDs.contains($0.ID) }
        guard !incoming.isEmpty else { return } // 변경 없음 → 스냅샷 apply 불필요
        
        // 4) 시간 순 정렬(오름차순)로 날짜 구분선/삽입 안정화
        let now = Date()
        let sorted = incoming.sorted { (a, b) -> Bool in
            (a.sentAt ?? now) < (b.sentAt ?? now)
        }
        
        // 5) 새 아이템 구성 (날짜 구분선 포함)
        let items = buildNewItems(from: sorted)
        guard !items.isEmpty else { return }
        
        // 6) 스냅샷 삽입 & 읽음 마커 처리 & 가상화(윈도우 크기 제한)
        insertItems(items, into: &snapshot, updateType: updateType)
        insertReadMarkerIfNeeded(sorted, items: items, into: &snapshot, updateType: updateType)
        applyVirtualization(on: &snapshot, updateType: updateType, windowSize: windowSize)
        
        // 7) 최종 반영
        let animate = shouldAnimateDifferences(for: updateType, newItemCount: items.count)
        dataSource.apply(snapshot, animatingDifferences: animate)
    }
    
    // MARK: - Private Helpers for addMessages
    private func reloadDeletedMessages(_ messages: [ChatMessage]) {
        // 1) 최신 상태를 먼저 캐시
        for msg in messages { messageMap[msg.ID] = msg }
        
        // 2) 스냅샷에서 실제로 존재하는 동일 ID 아이템만 추려서 reload
        var snapshot = dataSource.snapshot()
        let targetIDs = Set(messages.map { $0.ID })
        let itemsToReload = snapshot.itemIdentifiers.filter { item in
            if case let .message(m) = item { return targetIDs.contains(m.ID) }
            return false
        }
        
        guard !itemsToReload.isEmpty else { return }
        snapshot.reloadItems(itemsToReload)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    private func buildNewItems(from newMessages: [ChatMessage]) -> [Item] {
        var items: [Item] = []
        for message in newMessages {
            messageMap[message.ID] = message
            let messageDate = Calendar.current.startOfDay(for: message.sentAt ?? Date())
            if lastMessageDate == nil || lastMessageDate! != messageDate {
                items.append(.dateSeparator(message.sentAt ?? Date()))
                lastMessageDate = messageDate
            }
            
            items.append(.message(message))
        }
        
        return items
    }
    
    private func insertItems(_ items: [Item], into snapshot: inout NSDiffableDataSourceSnapshot<Section, Item>, updateType: MessageUpdateType) {
        if updateType == .older {
            if let firstItem = snapshot.itemIdentifiers.first {
                snapshot.insertItems(items, beforeItem: firstItem)
            } else {
                snapshot.appendItems(items, toSection: .main)
            }
        } else {
            snapshot.appendItems(items, toSection: .main)
        }
        
    }
    
    private func insertReadMarkerIfNeeded(_ newMessages: [ChatMessage], items: [Item], into snapshot: inout NSDiffableDataSourceSnapshot<Section, Item>, updateType: MessageUpdateType) {
        let hasReadMarker = snapshot.itemIdentifiers.contains { if case .readMarker = $0 { return true } else { return false } }
        if updateType == .newer, !hasReadMarker, let lastMessageID = self.lastReadMessageID, !isUserInCurrentRoom,
           let firstMessage = newMessages.first, firstMessage.ID != lastMessageID {
            if let firstNewItem = items.first(where: { if case .message = $0 { return true } else { return false } }) {
                snapshot.insertItems([.readMarker], beforeItem: firstNewItem)
            }
        }
    }
    
    private func applyVirtualization(on snapshot: inout NSDiffableDataSourceSnapshot<Section, Item>, updateType: MessageUpdateType, windowSize: Int) {
        let allItems = snapshot.itemIdentifiers
        if allItems.count > windowSize {
            let toRemoveCount = allItems.count - windowSize
            if updateType == .older {
                let itemsToRemove = Array(allItems.suffix(toRemoveCount))
                snapshot.deleteItems(itemsToRemove)
            } else if updateType == .newer {
                let itemsToRemove = Array(allItems.prefix(toRemoveCount))
                snapshot.deleteItems(itemsToRemove)
            }
        }
        // --- Virtualization cleanup: prune messageMap and date separators ---
        let allItemsAfterVirtualization = snapshot.itemIdentifiers
        let remainingMessageIDs: Set<String> = Set(
            allItemsAfterVirtualization.compactMap { item in
                if case .message(let m) = item { return m.ID } else { return nil }
            }
        )
        messageMap = messageMap.filter { remainingMessageIDs.contains($0.key) }
        var dateSeparatorsToDelete: [Item] = []
        let presentMessageDates: Set<Date> = Set(
            allItemsAfterVirtualization.compactMap { item in
                if case .message(let m) = item {
                    return Calendar.current.startOfDay(for: m.sentAt ?? Date())
                }
                return nil
            }
        )
        for item in allItemsAfterVirtualization {
            if case .dateSeparator(let date) = item {
                let day = Calendar.current.startOfDay(for: date)
                if !presentMessageDates.contains(day) {
                    dateSeparatorsToDelete.append(item)
                }
            }
        }
        if !dateSeparatorsToDelete.isEmpty {
            snapshot.deleteItems(dateSeparatorsToDelete)
        }
        // --- End of cleanup ---
    }
    
    private func updateCollectionView(with newItems: [Item]) {
        var snapshot = dataSource.snapshot()
        snapshot.appendItems(newItems, toSection: .main)
        let animate = shouldAnimateDifferences(for: .newer, newItemCount: newItems.count)
        dataSource.apply(snapshot, animatingDifferences: animate)
        chatMessageCollectionView.scrollToBottom()
    }
    
    // 캐시된 포맷터
    private lazy var dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월 d일 EEEE"
        return f
    }()
    private func formatDateToDayString(_ date: Date) -> String {
        return dayFormatter.string(from: date)
    }
    
    //MARK: Tap Gesture
    @MainActor
    @objc private func handleTapGesture() {
        
        if settingPanelVC != nil { return }
        view.endEditing(true)
        
        if !self.attachmentView.isHidden {
            chatUIView.attachmentButton.setImage(UIImage(systemName: "plus"), for: .normal)
            self.attachmentView.isHidden = true
            self.attachmentView.alpha = 0
            
            self.chatUIViewBottomConstraint?.constant = -10
            
            UIView.animate(withDuration: 0.25) {
                self.view.layoutIfNeeded()
            }
        }
        
        if chatCustomMenu.superview != nil {
            dismissCustomMenu()
        }
    }
    
    //MARK: 키보드 관련
    private func bindKeyboardPublisher() {
        NotificationCenter.default.publisher(for: UIApplication.keyboardWillShowNotification)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.keyboardWillShow(notification)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.keyboardWillHide(notification)
            }
            .store(in: &cancellables)
    }
    
    @objc private func keyboardWillShow(_ sender: Notification) {
        guard let animationDuration = sender.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let keyboard = sender.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
        
        chatMessageCollectionView.contentInset.top = self.view.safeAreaInsets.top + chatUIView.frame.height + keyboard.cgRectValue.height - 10
        chatMessageCollectionView.verticalScrollIndicatorInsets.top = self.view.safeAreaInsets.top + chatUIView.frame.height + keyboard.cgRectValue.height - 10
        
        // Hide attachment view if visible
        if !self.attachmentView.isHidden {
            self.attachmentView.isHidden = true
            self.chatUIView.attachmentButton.setImage(UIImage(systemName: "plus"), for: .normal)
            self.chatUIViewBottomConstraint?.constant = 0
        }
        UIView.animate(withDuration: animationDuration) {
            self.view.layoutIfNeeded()
        }
    }
    
    @objc private func keyboardWillHide(_ sender: Notification) {
        guard let animationDuration = sender.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let _ = sender.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        
        chatMessageCollectionView.contentInset.top = self.view.safeAreaInsets.top + chatUIView.frame.height + 5
        chatMessageCollectionView.verticalScrollIndicatorInsets.top = self.view.safeAreaInsets.top + chatUIView.frame.height + 5
        
        UIView.animate(withDuration: animationDuration) {
            self.view.layoutIfNeeded()
        }
    }
    
    //MARK: 기타
    private func showAlert(error: RoomCreationError) {
        var title: String
        var message: String
        
        switch error {
        case .saveFailed:
            title = "저장 실패"
            message = "채팅방 정보 저장에 실패했습니다. 다시 시도해주세요."
        case .imageUploadFailed:
            title = "이미지 업로드 실패"
            message = "방 이미지 업로드에 실패했습니다. 다시 시도해주세요."
        default:
            title = "오류"
            message = "알 수 없는 오류가 발생했습니다."
        }
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { action in
            self.navigationController?.popViewController(animated: true)
        })
    }
    
    // MARK: 이미지 뷰어 관련
    // Kingfisher prefetchers & URL cache
    private var imagePrefetchers: [ImagePrefetcher] = []
    
    private func presentImageViewer(tappedIndex: Int, indexPath: IndexPath) {
        // 1) 메시지 & 첨부 수집
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case .message(let chatMessage) = item else { return }
        
        let messageID = chatMessage.ID
        guard messageMap[messageID] != nil else { return }
        print(#function, "Chat Message:", messageMap[messageID] ?? [])
        
        let imageAttachments = chatMessage.attachments
            .filter { $0.type == .image }
            .sorted { $0.index < $1.index }
        
        // 원본 우선, 없으면 썸네일
        let storagePaths: [String] = imageAttachments.compactMap { att in
            if !att.pathOriginal.isEmpty { return att.pathOriginal }
            if !att.pathThumb.isEmpty { return att.pathThumb }
            return nil
        }
        guard !storagePaths.isEmpty else { return }
        
        // 2) 이전 프리패치 중단
        stopAllPrefetchers()
        
        // 3) 우선순위(링 오더)
        let count = storagePaths.count
        let start = max(0, min(tappedIndex, count - 1))
        let order = ringOrderIndices(count: count, start: start)
        let prioritizedPaths = order.map { storagePaths[$0] }
        
        // 근처 6~8장만 메모리 워밍
        let nearCount = min(8, prioritizedPaths.count)
        let nearPaths = Array(prioritizedPaths.prefix(nearCount))
        let restPaths = Array(prioritizedPaths.dropFirst(nearCount))
        
        // 옵션
        let diskOnlyOptions: KingfisherOptionsInfo = [
            .cacheOriginalImage,
            .memoryCacheExpiration(.expired),   // 메모리는 즉시 만료 → 사실상 비활성
            .diskCacheExpiration(.days(60)),
            .backgroundDecode,
            .transition(.none)
        ]
        let warmOptions: KingfisherOptionsInfo = [
            .cacheOriginalImage,
            .memoryCacheExpiration(.seconds(180)), // 근처만 잠깐 메모리 워밍 (3분)
            .diskCacheExpiration(.days(60)),
            .backgroundDecode,
            .transition(.none)
        ]

        // 4) 프리패치: 근처 → 나머지
        Task {
            let nearURLs = await resolveURLs(for: nearPaths, concurrent: 6)
            startPrefetch(urls: nearURLs, label: "near", options: warmOptions)
            
            if !restPaths.isEmpty {
                let restURLs = await resolveURLs(for: restPaths, concurrent: 6)
                startPrefetch(urls: restURLs, label: "rest", options: diskOnlyOptions)
            }
        }
        
        // 5) 뷰어 표시 (원래 순서)
        Task { @MainActor in
            let urlsAll = await resolveURLs(for: storagePaths, concurrent: 6)
            guard !urlsAll.isEmpty else { return }
            
            let viewer = SimpleImageViewerVC(urls: urlsAll, startIndex: start)
            viewer.modalPresentationStyle = .fullScreen
            viewer.modalTransitionStyle = .crossDissolve
            self.present(viewer, animated: true)
        }
    }
    
    // Stop and clear all active Kingfisher prefetchers
    private func stopAllPrefetchers() {
        imagePrefetchers.forEach { $0.stop() }
        imagePrefetchers.removeAll()
    }
    
    // Ring-order: start, +1, -1, +2, -2, ...
    private func ringOrderIndices(count: Int, start: Int) -> [Int] {
        guard count > 0 else { return [] }
        let s = max(0, min(start, count - 1))
        var result: [Int] = [s]; var step = 1
        while result.count < count {
            let r = s + step; if r < count { result.append(r) }
            if result.count == count { break }
            let l = s - step; if l >= 0 { result.append(l) }
            step += 1
        }
        return result
    }
    
    // Storage 경로 -> URL (동시성 제한)
    private func resolveURLs(for paths: [String], concurrent: Int = 6) async -> [URL] {
        guard !paths.isEmpty else { return [] }
        var urls = Array<URL?>(repeating: nil, count: paths.count)
        var idx = 0
        while idx < paths.count {
            let end = min(idx + concurrent, paths.count)
            await withTaskGroup(of: (Int, URL?).self) { group in
                for i in idx..<end {
                    let p = paths[i]
                    group.addTask { [storageURLCache] in
                        do { return (i, try await storageURLCache.url(for: p)) }
                        catch { return (i, nil) }
                    }
                }
                for await (i, u) in group { urls[i] = u }
            }
            idx = end
        }
        return urls.compactMap { $0 }
    }
    
    // Kingfisher 프리패치 시작 (옵션 주입)
    private func startPrefetch(urls: [URL], label: String, options: KingfisherOptionsInfo) {
        guard !urls.isEmpty else { return }
        let pf = ImagePrefetcher(
            urls: urls,
            options: options,
            progressBlock: nil,
            completionHandler: { skipped, failed, completed in
                print("🧯 Prefetch[\(label)] done - completed: \(completed.count), failed: \(failed.count), skipped: \(skipped.count)")
            }
        )
        imagePrefetchers.append(pf)
        pf.start()
    }
}

private extension ChatViewController {
    @MainActor
    func setupCustomNavigationBar() {
        self.view.addSubview(customNavigationBar)
        NSLayoutConstraint.activate([
            customNavigationBar.topAnchor.constraint(equalTo: self.view.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
        
        guard let room = self.room else { return }
        customNavigationBar.configureForChatRoom(
            roomTitle: room.roomName,
            participantCount: room.participants.count,
            target: self,
            onBack: #selector(backButtonTapped),
            onSearch: #selector(searchButtonTapped),
            onSetting: #selector(settingButtonTapped)
        )
    }
}

extension ChatViewController: UIScrollViewDelegate {
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        triggerShakeIfNeeded()
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        triggerShakeIfNeeded()
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            triggerShakeIfNeeded()
        }
    }
    
    @MainActor
    private func triggerShakeIfNeeded() {
        guard let indexPath = scrollTargetIndex,
              let cell = chatMessageCollectionView.cellForItem(at: indexPath) as? ChatMessageCell else {
            return
        }
        cell.shakeHorizontally()
        scrollTargetIndex = nil  // 초기화
    }
}

extension ChatViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView,
                        willDisplay cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        
        let itemCount = collectionView.numberOfItems(inSection: 0)
        
        // ✅ Older 메시지 로드
        if indexPath.item < 5, hasMoreOlder, !isLoadingOlder {
            if let lastIndex = Self.lastTriggeredOlderIndex,
               abs(lastIndex - indexPath.item) < minTriggerDistance {
                return // 너무 가까운 위치에서 또 호출 → 무시
            }
            Self.lastTriggeredOlderIndex = indexPath.item
            
            Task {
                let firstID = dataSource.snapshot().itemIdentifiers.compactMap { item -> String? in
                    if case let .message(msg) = item { return msg.ID }
                    return nil
                }.first
                await loadOlderMessages(before: firstID)
            }
        }
        
        // ✅ Newer 메시지 로드
        if indexPath.item > itemCount - 5, hasMoreNewer, !isLoadingNewer {
            if let lastIndex = Self.lastTriggeredNewerIndex,
               abs(lastIndex - indexPath.item) < minTriggerDistance {
                return
            }
            Self.lastTriggeredNewerIndex = indexPath.item
            
            Task {
                let lastID = dataSource.snapshot().itemIdentifiers.compactMap { item -> String? in
                    if case let .message(msg) = item { return msg.ID }
                    return nil
                }.last
                await loadNewerMessagesIfNeeded(after: lastID)
            }
        }
        
        // ✅ 아바타 프리패치: 가시영역 중심 ±100 메시지의 고유 발신자
//        self.prefetchAvatarsAroundDisplayIndex(indexPath.item)
    }

}

extension ChatViewController {
    // MARK: - OPStorageURLCache (Firebase Storage downloadURL cache)
    actor OPStorageURLCache {
        private var cache: [String: URL] = [:]
        
        func url(for path: String) async throws -> URL {
            if let u = cache[path] { return u }
            let ref = Storage.storage().reference(withPath: path)
            let url = try await withCheckedThrowingContinuation { cont in
                ref.downloadURL { url, err in
                    if let url { cont.resume(returning: url) }
                    else { cont.resume(throwing: err ?? NSError(domain: "Storage", code: -1, userInfo: [NSLocalizedDescriptionKey: "downloadURL failed"])) }
                }
            }
            cache[path] = url
            return url
        }
    }

    // MARK: - OPVideoDiskCache (progressive MP4 local caching)
    actor OPVideoDiskCache {
        static let shared = OPVideoDiskCache()
        private let dir: URL
        private let capacity: Int64 = 512 * 1024 * 1024 // 512MB
        
        init() {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            dir = base.appendingPathComponent("Videos", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        /// Deterministic local file URL for a given logical key.
        func localURL(forKey key: String) -> URL {
            dir.appendingPathComponent(key.sha256() + ".mp4")
        }
        
        /// Returns local file URL if cached.
        func exists(forKey key: String) -> URL? {
            let u = localURL(forKey: key)
            return FileManager.default.fileExists(atPath: u.path) ? u : nil
        }
        
        /// Download and store a remote file to cache; returns the final local URL.
        @discardableResult
        func cache(from remote: URL, key: String) async throws -> URL {
            let tmp = dir.appendingPathComponent(UUID().uuidString + ".part")
            let (data, _) = try await URLSession.shared.data(from: remote)
            try data.write(to: tmp, options: .atomic)
            let dest = localURL(forKey: key)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            try trimIfNeeded()
            return dest
        }
        
        /// Evict old files when capacity exceeded (LRU-ish using modification date).
        private func trimIfNeeded() throws {
            let files = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            var entries: [(url: URL, date: Date, size: Int64)] = []
            var total: Int64 = 0
            for u in files {
                let rv = try u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let d = rv.contentModificationDate ?? Date.distantPast
                let s = Int64(rv.fileSize ?? 0)
                total += s
                entries.append((u, d, s))
            }
            guard total > capacity else { return }
            for entry in entries.sorted(by: { $0.date < $1.date }) {
                try? FileManager.default.removeItem(at: entry.url)
                total -= entry.size
                if total <= capacity { break }
            }
        }
    }
}

// MARK: - Utilities
fileprivate extension String {
    func sha256() -> String {
        let data = Data(self.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

//MARK: seq 업데이트 헬퍼
extension ChatViewController {
    @MainActor
    private func maybeUpdateLastReadSeq(trigger: String, skipNearBottomCheck: Bool = false) {
        guard let room = self.room else { return }

        // 사용자가 실제로 확인했다고 간주하는 최댓값: 창 최대와 입장 스냅샷 중 작은 값
        let candidate = min(windowMaxSeq, entryTailSeq)

        // 세션 중에는 바닥 근처일 때만 기록 → 쓰기 폭주 방지
        // 단, newerPage 같은 트리거에서는 이미 바닥 근접이 보장되므로 체크 생략 가능
        if !skipNearBottomCheck {
            guard isNearBottom() else { return }
        }

        // 단조 증가 & 중복 쓰기 방지
        guard candidate > lastSentLastReadSeq else { return }
        lastSentLastReadSeq = candidate

        Task(priority: .utility) { [roomID = room.ID ?? "", uid = LoginManager.shared.getUserEmail, seq = candidate] in
            do {
                try await FirebaseManager.shared.updateLastReadSeq(roomID: roomID, userID: uid, lastReadSeq: seq)
            } catch {
                print("⚠️ maybeUpdateLastReadSeq(\(trigger)) 실패: \(error)")
            }
        }
    }
}
