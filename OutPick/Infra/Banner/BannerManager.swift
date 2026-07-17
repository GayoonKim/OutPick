// BannerManager.swift
import Foundation
import UIKit

protocol RealtimeBackgroundRoomSessionOpening: Sendable {
    func openBackgroundRoomSession(for roomID: String) async throws -> ChatRoomSocketSession
}

extension RealtimeSocketService: RealtimeBackgroundRoomSessionOpening {}

struct BannerSubscriptionRetryPolicy: Equatable, Sendable {
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval

    init(baseDelay: TimeInterval = 0.5, maxDelay: TimeInterval = 8) {
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    func delay(forFailureAttempt attempt: Int) -> TimeInterval {
        min(maxDelay, baseDelay * pow(2, Double(max(0, attempt - 1))))
    }
}

@MainActor
final class BannerManager {
    static let shared = BannerManager()
    private var realtimeSocketService: (any RealtimeBackgroundRoomSessionOpening)?
    private var roomReadStateStore: ChatRoomReadStateStore?
    private var roomRepository: FirebaseChatRoomRepositoryProtocol?
    private let retryPolicy: BannerSubscriptionRetryPolicy
    private let retrySleep: @Sendable (TimeInterval) async -> Void

    init(
        retryPolicy: BannerSubscriptionRetryPolicy = BannerSubscriptionRetryPolicy(),
        retrySleep: @escaping @Sendable (TimeInterval) async -> Void = { delay in
            guard delay > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    ) {
        self.retryPolicy = retryPolicy
        self.retrySleep = retrySleep
    }

    // 현재 화면에서 보고 있는 roomID (nil이면 채팅 화면이 아님)
    private var currentVisibleRoomID: String?

    // 참여 중인 방 구독 저장소 (roomID -> cancellable)
    private var roomTasks: [String: Task<Void, Never>] = [:]
    private var presentationQueue = BannerPresentationQueueState()
    // window attach 재시도 중에도 view와 queue completion을 유지한다.
    private var currentBannerView: ChatBannerView?

    // 배너 표시 콜백(앱 전역에서 주입: 토스트/상단 배너 등)
    var onPresentBanner: ((BannerPayload) -> Void)?

    // 설정
    private let muteOwnMessages = true   // 내가 보낸 메시지는 배너 안 띄움 (선호에 맞게)

    // MARK: - Public

    func configure(
        roomReadStateStore: ChatRoomReadStateStore,
        roomRepository: FirebaseChatRoomRepositoryProtocol
    ) {
        self.roomReadStateStore = roomReadStateStore
        self.roomRepository = roomRepository
    }

    func configure(realtimeSocketService: any RealtimeBackgroundRoomSessionOpening) {
        self.realtimeSocketService = realtimeSocketService
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
        guard let realtimeSocketService else {
            assertionFailure("BannerManager realtime socket service가 설정되지 않았습니다.")
            return
        }

        #if DEBUG
        print("[BannerManager] addRoom subscription room=\(roomID)")
        #endif

        roomTasks[roomID] = Task { [weak self] in
            guard let self else { return }
            var failureAttempt = 0

            while !Task.isCancelled {
                do {
                    let session = try await realtimeSocketService.openBackgroundRoomSession(
                        for: roomID
                    )
                    failureAttempt = 0

                    for await msg in session.messages {
                        if Task.isCancelled { break }
                        await self.handleIncomingMessage(msg, roomID: roomID)
                    }
                    await session.close()

                    guard !Task.isCancelled else { break }
                    failureAttempt += 1
                } catch {
                    guard !Task.isCancelled else { break }
                    guard Self.shouldRetrySubscription(after: error) else {
                        #if DEBUG
                        print("[BannerManager] terminal stream failure room=\(roomID): \(error)")
                        #endif
                        break
                    }
                    failureAttempt += 1

                    #if DEBUG
                    print("[BannerManager] stream failed room=\(roomID), retry=\(failureAttempt): \(error)")
                    #endif
                }

                await self.retrySleep(
                    self.retryPolicy.delay(forFailureAttempt: failureAttempt)
                )
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
    }

    func stopAll() {
        for task in roomTasks.values {
            task.cancel()
        }
        roomTasks.removeAll()
        currentVisibleRoomID = nil
        presentationQueue.reset()
        currentBannerView?.dismiss()
        currentBannerView = nil
    }

    // 화면 전환 시 호출(채팅방 진입/이탈)
    func setVisibleRoom(_ roomID: String?) {
        #if DEBUG
        print("[BannerManager] setVisibleRoom -> \(roomID ?? "nil")")
        #endif
        currentVisibleRoomID = roomID
    }

    nonisolated private static func shouldRetrySubscription(after error: Error) -> Bool {
        let nsError = error as NSError
        return !(nsError.domain == "SocketIO" && nsError.code == -1003)
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

        if let next = presentationQueue.enqueue(payload) {
            showBanner(message: next)
        }
    }
    
    private func showBanner(message: BannerPayload) {
        let title = message.title
        let msg = message.body
        print(#function, title, msg)
        let bannerView = ChatBannerView()
        currentBannerView = bannerView
        bannerView.configure(title: title, subtitle: msg, onTap: { [weak self] in
            guard self != nil else { return }
            
            print(#function, "메시지 배너 탭", message)
        }
        )

        onPresentBanner?(message)
        bannerView.show { [weak self, weak bannerView] in
            guard let self else { return }
            if self.currentBannerView === bannerView {
                self.currentBannerView = nil
            }
            if let next = self.presentationQueue.finishCurrent() {
                self.showBanner(message: next)
            }
        }
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

// 배너 표시용 모델
struct BannerPayload: Equatable, Sendable {
    let roomID: String
    let title: String
    let body: String
    let attachmentsCount: Int
}

// 편의
private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
