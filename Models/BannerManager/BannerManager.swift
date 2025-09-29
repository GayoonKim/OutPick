// BannerManager.swift
import Foundation
import Combine
import UIKit

final class BannerManager {
    static let shared = BannerManager()
    private init() {}

    // 현재 화면에서 보고 있는 roomID (nil이면 채팅 화면이 아님)
    let currentVisibleRoomID = CurrentValueSubject<String?, Never>(nil)

    // 참여 중인 방 구독 저장소 (roomID -> cancellable)
    private var roomSubscriptions: [String: AnyCancellable] = [:]

    // 중복 배너 방지: 방별 최근 메시지 ID LRU
    private var recentPerRoom: [String: RecentSet<String>] = [:]

    // 배너 표시 콜백(앱 전역에서 주입: 토스트/상단 배너 등)
    var onPresentBanner: ((BannerPayload) -> Void)?

    // 설정
    private let maxRecentIDsPerRoom = 200
    private let muteOwnMessages = true   // 내가 보낸 메시지는 배너 안 띄움 (선호에 맞게)

    // MARK: - Public

    /// 배너용 구독 시작(참여 중인 모든 방)
    func start(for joinedRoomIDs: [String]) {
        // 불필요 구독 제거
        let toRemove = Set(roomSubscriptions.keys).subtracting(joinedRoomIDs)
        toRemove.forEach { removeRoom($0) }

        // 신규/누락 구독 추가
        let toAdd = Set(joinedRoomIDs).subtracting(roomSubscriptions.keys)
        toAdd.forEach { addRoom($0) }
    }

    /// 개별 방 추가
    func addRoom(_ roomID: String) {
        guard roomSubscriptions[roomID] == nil else { return }

        // LRU 준비
        if recentPerRoom[roomID] == nil {
            recentPerRoom[roomID] = RecentSet(capacity: maxRecentIDsPerRoom)
        }

        // SocketIOManager의 ref-counted 스트림: 중복 리스너 없음
        let pub = SocketIOManager.shared.subscribeToMessages(for: roomID)

        roomSubscriptions[roomID] = pub
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                guard let self else { return }
                
                // 현재 방 보고 있으면 배너 X (화면이 실시간 UI 반영)
                if self.currentVisibleRoomID.value == roomID { return }

                // 중복 배너 방지
                let id = msg.ID
                if self.recentPerRoom[roomID]?.contains(id) == true { return }
                self.recentPerRoom[roomID]?.insert(id)

                // 내가 보낸 메시지 mute 옵션
                if self.muteOwnMessages, msg.senderID == LoginManager.shared.getUserEmail { return }

                // 배너 내용 구성
                let text: String = bannerText(from: msg)
                let payload = BannerPayload(
                    roomID: roomID,
                    title: msg.senderNickname,
                    body: text,
                    attachmentsCount: msg.attachments.count
                )

                self.showBanner(message: payload)
            }
    }

    /// 개별 방 제거
    func removeRoom(_ roomID: String) {
        roomSubscriptions[roomID]?.cancel()
        roomSubscriptions[roomID] = nil
        recentPerRoom[roomID] = nil
        
        // SocketIOManager는 ref-count로 실제 리스너를 알아서 해제함
        SocketIOManager.shared.unsubscribeFromMessages(for: roomID)
    }

    // 화면 전환 시 호출(채팅방 진입/이탈)
    func setVisibleRoom(_ roomID: String?) {
        currentVisibleRoomID.send(roomID)
    }
    
    private func showBanner(message: BannerPayload) {
        let title = message.title
        let msg = message.body
        
        let bannerView = ChatBannerView()
        bannerView.configure(title: title, subtitle: msg, onTap: { [weak self] in
            guard let self = self else { return }
            
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
