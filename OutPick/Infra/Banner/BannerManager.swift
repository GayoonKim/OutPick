// BannerManager.swift
import Foundation
import UIKit

@MainActor
final class BannerManager {
    static let shared = BannerManager()
    private let realtimeSocketService: RealtimeSocketService
    private var roomReadStateStore: ChatRoomReadStateStore?
    private var roomRepository: FirebaseChatRoomRepositoryProtocol?

    private init(
        realtimeSocketService: RealtimeSocketService = .shared
    ) {
        self.realtimeSocketService = realtimeSocketService
    }

    // 현재 화면에서 보고 있는 roomID (nil이면 채팅 화면이 아님)
    private var currentVisibleRoomID: String?

    // 참여 중인 방 구독 저장소 (roomID -> cancellable)
    private var roomTasks: [String: Task<Void, Never>] = [:]

    // 중복 배너 방지: 방별 최근 메시지 ID LRU
    private var recentPerRoom: [String: RecentSet<String>] = [:]

    // 배너 표시 콜백(앱 전역에서 주입: 토스트/상단 배너 등)
    var onPresentBanner: ((BannerPayload) -> Void)?

    // 설정
    private let maxRecentIDsPerRoom = 200
    private let muteOwnMessages = true   // 내가 보낸 메시지는 배너 안 띄움 (선호에 맞게)

    // MARK: - Public

    func configure(
        roomReadStateStore: ChatRoomReadStateStore,
        roomRepository: FirebaseChatRoomRepositoryProtocol
    ) {
        self.roomReadStateStore = roomReadStateStore
        self.roomRepository = roomRepository
    }

    /// 배너용 구독 시작(참여 중인 모든 방)
    func start(for joinedRoomIDs: [String]) {
        #if DEBUG
        print("[BannerManager] start joinedRooms=\(joinedRoomIDs.count) subscribed=\(roomTasks.count)")
        #endif
        // 불필요 구독 제거
        let toRemove = Set(roomTasks.keys).subtracting(joinedRoomIDs)
        toRemove.forEach { removeRoom($0) }

        // 신규/누락 구독 추가
        let toAdd = Set(joinedRoomIDs).subtracting(roomTasks.keys)
        toAdd.forEach { addRoom($0) }
    }

    /// 개별 방 추가
    func addRoom(_ roomID: String) {
        guard roomTasks[roomID] == nil else { return }

        #if DEBUG
        print("[BannerManager] addRoom subscription room=\(roomID)")
        #endif

        // LRU 준비
        if recentPerRoom[roomID] == nil {
            recentPerRoom[roomID] = RecentSet(capacity: maxRecentIDsPerRoom)
        }

        roomTasks[roomID] = Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await self.realtimeSocketService.openRoomSession(for: roomID)
                defer {
                    Task {
                        await session.close()
                    }
                }

                for await msg in session.messages {
                    if Task.isCancelled { break }
                    await self.handleIncomingMessage(msg, roomID: roomID)
                }
            } catch {
                #if DEBUG
                print("[BannerManager] stream failed room=\(roomID): \(error)")
                #endif
            }
        }
    }

    /// 개별 방 제거
    func removeRoom(_ roomID: String) {
        #if DEBUG
        print("[BannerManager] removeRoom subscription room=\(roomID)")
        #endif
        roomTasks[roomID]?.cancel()
        roomTasks[roomID] = nil
        recentPerRoom[roomID] = nil
    }

    func stopAll() {
        for task in roomTasks.values {
            task.cancel()
        }
        roomTasks.removeAll()
        recentPerRoom.removeAll()
        currentVisibleRoomID = nil
    }

    // 화면 전환 시 호출(채팅방 진입/이탈)
    func setVisibleRoom(_ roomID: String?) {
        #if DEBUG
        print("[BannerManager] setVisibleRoom -> \(roomID ?? "nil")")
        #endif
        currentVisibleRoomID = roomID
    }

    private func handleIncomingMessage(_ msg: ChatMessage, roomID: String) async {
        let text = bannerText(from: msg)
        roomReadStateStore?.seedIncomingMessage(msg)
        roomRepository?.applyLocalIncomingMessagePreview(msg)

        #if DEBUG
        print("[BannerManager] incoming room=\(roomID) msgID=\(msg.ID) sender=\(msg.senderUID) visible=\(currentVisibleRoomID ?? "nil")")
        #endif

        // 현재 방 보고 있으면 배너 X (화면이 실시간 UI 반영)
        if currentVisibleRoomID == roomID {
            #if DEBUG
            print("[BannerManager] skip banner (visible room) room=\(roomID)")
            #endif
            return
        }

        let id = msg.ID
        if recentPerRoom[roomID]?.contains(id) == true {
            #if DEBUG
            print("[BannerManager] skip banner (duplicate) room=\(roomID) msgID=\(id)")
            #endif
            return
        }
        recentPerRoom[roomID]?.insert(id)

        if muteOwnMessages, msg.senderUID == LoginManager.shared.canonicalUserID {
            #if DEBUG
            print("[BannerManager] skip banner (own message) room=\(roomID) sender=\(msg.senderUID)")
            #endif
            return
        }

        let payload = BannerPayload(
            roomID: roomID,
            title: msg.senderNickname,
            body: text,
            attachmentsCount: msg.attachments.count
        )

        showBanner(message: payload)
    }
    
    private func showBanner(message: BannerPayload) {
        let title = message.title
        let msg = message.body
        print(#function, title, msg)
        let bannerView = ChatBannerView()
        bannerView.configure(title: title, subtitle: msg, onTap: { [weak self] in
            guard self != nil else { return }
            
            print(#function, "메시지 배너 탭", message)
        }
        )
        
        bannerView.show()
    }
}

// MARK: - Helpers

private func bannerText(from msg: ChatMessage) -> String {
    if !msg.msg.orEmpty.isEmpty {
        return msg.msg.orEmpty
    }
    // 첨부 위주로 문구 생성
    let images = msg.attachments.filter { $0.type == .image }.count
    let videos = msg.attachments.filter { $0.type == .video }.count
    switch (images, videos) {
    case (let i, let v) where i > 0 && v == 0: return "사진 \(i)장"
    case (let i, let v) where v > 0 && i == 0: return "동영상 \(v)개"
    case (let i, let v) where i > 0 && v > 0:  return "사진 \(i)장, 동영상 \(v)개"
    default: return "(메시지)"
    }
}

// 최근 ID LRU (간단 구현)
private struct RecentSet<Element: Hashable> {
    private(set) var set: Set<Element> = []
    private var queue: [Element] = []
    let capacity: Int

    init(capacity: Int) { self.capacity = max(1, capacity) }

    mutating func insert(_ e: Element) {
        if set.contains(e) { return }
        set.insert(e)
        queue.append(e)
        if queue.count > capacity, let old = queue.first {
            queue.removeFirst()
            set.remove(old)
        }
    }
    func contains(_ e: Element) -> Bool { set.contains(e) }
}

// 배너 표시용 모델
struct BannerPayload {
    let roomID: String
    let title: String
    let body: String
    let attachmentsCount: Int
}

// 편의
private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
