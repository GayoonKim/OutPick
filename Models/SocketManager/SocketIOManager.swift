//
//  SocketIOManager.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.

import UIKit
import SocketIO
import Combine
import CryptoKit

class SocketIOManager {
    static let shared = SocketIOManager()

    // MARK: - Socket Error
    enum SocketError: Error {
        case connectionFailed([Any])
    }
    
    var manager: SocketManager!
    var socket: SocketIOClient!
    
    private var connectWaiters: [() -> Void] = []
    private var hasOnConnectBound = false
    
    // 연결 상태 확인 프로퍼티 추가
    var isConnected: Bool {
        return socket.status == .connected
    }
    
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    // Combine의 PassthroughSubject를 사용하여 이벤트 스트림 생성
    
    // 새로운 참여자 알림을 위한 Publisher 추가
    private let participantSubject = PassthroughSubject<(String, String), Never>() // (roomName, email)
    var participantUpdatePublisher: AnyPublisher<(String, String), Never> {
        return participantSubject.eraseToAnyPublisher()
    }
    
    private var didBindListeners = false
    
    private var joinedRooms = Set<String>()
    private var pendingRooms: Set<String> = []
    
    private var roomSubjects = [String: PassthroughSubject<ChatMessage, Never>]()
    private var subscriberCounts = [String: Int]() // 구독자 ref count
    
    private init() {
        //manager = SocketManager(socketURL: URL(string: "http://127.0.0.1:3000")!, config: [.log(true), .compress])
        manager = SocketManager(socketURL: URL(string: "http://192.168.123.182:3000")!, config: [.log(true), .compress])
        socket = manager.defaultSocket
        
        socket.on(clientEvent: .connect) {data, ack in
            print("Socket Connected")
            
            guard let nickName = LoginManager.shared.currentUserProfile?.nickname else { return }
            self.socket.emit("set username", nickName)
            
            // Join any pending rooms after connecting and setting username
            for roomID in self.pendingRooms {
                self.socket.emit("join room", roomID)
                self.joinedRooms.insert(roomID)
            }
            self.pendingRooms.removeAll()
        }
        
        socket.on(clientEvent: .error) { data, ack in
            print("소켓 에러:", data)
        }
    }
    
    func establishConnection() async throws {
        // 이미 연결된 경우
        if socket.status == .connected {
            print("이미 연결된 상태")
            return
        }
        
        // 연결 중인 경우
        if socket.status == .connecting {
            print("이미 연결 중인 상태")
            try await withCheckedThrowingContinuation { continuation in
                self.connectWaiters.append {
                    continuation.resume()
                }
            }
            return
        }
        
        // 연결 시도
        try await withCheckedThrowingContinuation { continuation in
            self.connectWaiters.append {
                continuation.resume()
            }
            
            if !self.hasOnConnectBound {
                self.hasOnConnectBound = true
                self.socket.on(clientEvent: .connect) { [weak self] _, _ in
                    guard let self else { return }
                    let waiters = self.connectWaiters
                    self.connectWaiters.removeAll()
                    waiters.forEach { $0() }
                }
                
                self.socket.on(clientEvent: .error) { [weak self] data, _ in
                    guard let self else { return }
                    let waiters = self.connectWaiters
                    self.connectWaiters.removeAll()
                    waiters.forEach { _ in
                        continuation.resume(throwing: SocketError.connectionFailed(data))
                    }
                }
            }
            
            print("소켓 연결 시도")
            self.socket.connect()
        }
    }
    
    func closeConnection() {
        socket.disconnect()
    }
    
    func subscribeToMessages(for roomID: String) -> AnyPublisher<ChatMessage, Never> {
        print(#function, "✅✅✅✅✅ 2. subscribeToMessages 호출")
        
        subscriberCounts[roomID, default: 0] += 1

        if roomSubjects[roomID] == nil {
            let subject = PassthroughSubject<ChatMessage, Never>()
            roomSubjects[roomID] = subject

            // Ensure joined before attaching listeners (idempotent)
            if !joinedRooms.contains(roomID) { joinRoom(roomID) }

            // 소켓 리스너 등록
            attachChatListener(for: roomID) { [weak self] message in
                guard let self = self else { return }
                print(#function,"✅✅✅✅✅ attachChatListener:", message)
                self.roomSubjects[roomID]?.send(message)
            }
            // 이미지 브로드캐스트 리스너 등록
            attachImageListener(for: roomID) { [weak self] message in
                guard let self = self else { return }
                print(#function,"✅✅✅✅✅ attachImageListener:", message)
                self.roomSubjects[roomID]?.send(message)
            }
            // 비디오 브로드캐스트 리스너 등록
            attachVideoListener(for: roomID) { [weak self] message in
                guard let self = self else { return }
                print(#function,"✅✅✅✅✅ attachVideoListener:", message)
                self.roomSubjects[roomID]?.send(message)
            }
        }

        return roomSubjects[roomID]!.eraseToAnyPublisher()
    }

    func unsubscribeFromMessages(for roomID: String) {
        guard let count = subscriberCounts[roomID], count > 0 else { return }
        subscriberCounts[roomID] = count - 1

        if subscriberCounts[roomID] == 0 {
            detachChatListener(for: roomID)
            detachImageListener(for: roomID)
            detachVideoListener(for: roomID)
            roomSubjects[roomID]?.send(completion: .finished)
            roomSubjects[roomID] = nil
        }
    }
    
    private func attachChatListener(for roomID: String, onMessage: @escaping (ChatMessage) -> Void) {
        let event = "chat message:\(roomID)"
        print(#function, "bind →", event)
        // Prevent duplicate handlers for the same room event
        socket.off(event)

        socket.on(event) { [weak self] data, _ in
            guard let self = self else { return }
            guard let dict = data.first as? [String: Any] else {
                #if DEBUG
                print("[attachChatListener] invalid payload (not dict):", data)
                #endif
                return
            }

            guard let message = ChatMessage.from(dict) else {
                #if DEBUG
                print("[attachChatListener] parse failed =", dict)
                #endif
                return
            }
            guard message.roomID == roomID else {
                #if DEBUG
                print("[attachChatListener] room mismatch payload=\(message.roomID) subscribed=\(roomID)")
                #endif
                return
            }
            DispatchQueue.main.async {
                onMessage(message)
            }
        }
    }

    private func detachChatListener(for roomID: String) {
        socket.off("chat message:\(roomID)")
    }

    // 이미지 수신용 리스너
    private func attachImageListener(for roomID: String, onMessage: @escaping (ChatMessage) -> Void) {
        let event = "receiveImages:\(roomID)"
        print(#function, "bind →", event)
        // Prevent duplicate handlers for the same room event
        socket.off(event)

        socket.on(event) { [weak self] data, _ in
            guard let self = self else { return }
            guard let dict = data.first as? [String: Any] else {
                #if DEBUG
                print("[attachImageListener] invalid payload (not dict):", data)
                #endif
                return
            }
            // Normalize server payload (senderNickname vs senderNickName, id vs ID)
            var normalized = dict
            if normalized["senderNickName"] == nil, let v = normalized["senderNickname"] { normalized["senderNickName"] = v }
            if normalized["ID"] == nil, let v = normalized["id"] as? String { normalized["ID"] = v }

            guard let message = ChatMessage.from(normalized) else {
                #if DEBUG
                print("[attachImageListener] parse failed normalized=", normalized)
                #endif
                return
            }
            guard message.roomID == roomID else {
                #if DEBUG
                print("[attachImageListener] room mismatch payload=\(message.roomID) subscribed=\(roomID)")
                #endif
                return
            }
            // (선택) 이미지 메시지만 통과시키고 싶다면 아래 가드를 유지
            // guard message.attachments.contains(where: { $0.type == .image }) else { return }
            DispatchQueue.main.async {
                onMessage(message)
            }
        }
    }

    // 비디오 수신용 리스너
    private func attachVideoListener(for roomID: String, onMessage: @escaping (ChatMessage) -> Void) {
        let event = "receiveVideo:\(roomID)"
        print(#function, "bind →", event)
        // Prevent duplicate handlers for the same room event
        socket.off(event)

        socket.on(event) { [weak self] data, _ in
            guard let self = self else { return }
            guard let dict = data.first as? [String: Any] else {
                #if DEBUG
                print("[attachVideoListener] invalid payload (not dict):", data)
                #endif
                return
            }

            // Normalize server payload (senderNickname vs senderNickName, id vs ID)
            var normalized = dict
            if normalized["senderNickName"] == nil, let v = normalized["senderNickname"] { normalized["senderNickName"] = v }
            if normalized["ID"] == nil, let v = normalized["id"] as? String { normalized["ID"] = v }

            guard let message = ChatMessage.from(normalized) else {
                #if DEBUG
                print("[attachVideoListener] parse failed normalized=", normalized)
                #endif
                return
            }
            guard message.roomID == roomID else {
                #if DEBUG
                print("[attachVideoListener] room mismatch payload=\(message.roomID) subscribed=\(roomID)")
                #endif
                return
            }
            // (선택) 비디오 메시지만 통과시키고 싶다면 아래 가드를 사용
            // guard message.attachments.contains(where: { $0.type == .video }) else { return }
            DispatchQueue.main.async {
                onMessage(message)
            }
        }
    }

    private func detachVideoListener(for roomID: String) {
        socket.off("receiveVideo:\(roomID)")
    }

    private func detachImageListener(for roomID: String) {
        socket.off("receiveImages:\(roomID)")
    }
    
    func joinRoom(_ roomID: String) {
        if socket.status == .connected {
            guard joinedRooms.insert(roomID).inserted else {
                print("이미 참여한 방:", roomID); return
            }
            socket.emit("join room", roomID)
        } else {
            // Not connected: queue for joining after connect
            pendingRooms.insert(roomID)
        }
        // listener off/on은 유지해도 됨. emit 자체가 중복되지 않는 게 핵심
    }
    
    func createRoom(_ roomID: String) {
        print("createRoom 호출 - roomID: ", roomID)
        
        guard socket.status == .connected else {
            print("소켓이 연결되지 않음")
            return
        }
        
        // 기존 방 생성 관련 리스너 제거 (중복 방지)
        socket.off("room created")
        socket.off("room error")
        
        socket.emit("create room", roomID)
        
        // 방 생성 성공/실패 모니터링
        socket.on("room created") { data, _ in
            print("방 생성 성공: ", data)
        }
        socket.on("room error") { data, _ in
            print("방 생성 실패: ", data)
        }
    }
    
    func sendMessages(_ room: ChatRoom, _ message: ChatMessage) {
        // 1. Optimistic UI: Publish the message immediately as not failed
        // 2. If not connected, mark as failed and publish (again, so UI can update)
        guard socket.status == .connected else {
            print("소켓이 연결되지 않음")
            var failedMessage = message
            failedMessage.isFailed = true
            DispatchQueue.main.async {
                self.roomSubjects[room.ID ?? ""]?.send(failedMessage)
            }
            return
        }

        let payload = message.toSocketRepresentation()
        print("📤 전송할 소켓 데이터: \(payload)")  // 디버깅용

        socket.emitWithAck("chat message", payload).timingOut(after: 5) { [weak self] ackResponse in
            guard let self = self else { return }

            let ackDict = ackResponse.first as? [String:Any]
            let ok = (ackDict?["ok"] as? Bool) ?? (ackDict?["success"] as? Bool) ?? false
            let duplicate = (ackDict?["duplicate"] as? Bool) ?? false

            if ok || duplicate {
                Task {
                    await FirebaseManager.shared.updateRoomLastMessageAt(roomID: room.ID ?? "", date: message.sentAt)
                }
            } else {
                // Failure: mark the same message as failed and re-publish for UI update
                var failedMessage = message
                failedMessage.isFailed = true
                DispatchQueue.main.async {
                    self.roomSubjects[room.ID ?? ""]?.send(failedMessage)
                }
            }
        }
    }
    
    // MARK: - Emit (meta-only attachments)
    /// 메타 전용 첨부(썸네일/원본 경로 등)를 소켓으로 전송
    /// ChatViewController에서 attachments.map { $0.toDict() } 로 호출합니다.
    func sendImages(_ room: ChatRoom, _ attachments: [[String: Any]]) {
        // 0) 가드
        guard !attachments.isEmpty else { return }
        let roomID = room.ID ?? ""
        let senderID = LoginManager.shared.getUserEmail
        let senderNickname = LoginManager.shared.currentUserProfile?.nickname ?? ""
        let clientMessageID = UUID().uuidString
        let now = Date()
        let isoSentAt = Self.isoFormatter.string(from: now)
        print(#function," attachments", attachments)
        // 헬퍼: dict -> Attachment 모델 변환 (로컬 퍼블리시용)
        func makeAttachment(from dict: [String: Any], fallbackIndex: Int) -> Attachment {
            let index = dict["index"] as? Int ?? fallbackIndex
            let pathThumb = (dict["pathThumb"] as? String) ?? ""
            let pathOriginal = (dict["pathOriginal"] as? String) ?? ""
            let width = (dict["w"] as? Int) ?? (dict["width"] as? Int) ?? 0
            let height = (dict["h"] as? Int) ?? (dict["height"] as? Int) ?? 0
            let bytesOriginal = (dict["bytesOriginal"] as? Int) ?? (dict["size"] as? Int) ?? 0
            let hash = (dict["hash"] as? String) ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let blurhash = dict["blurhash"] as? String
            return Attachment(
                type: .image,
                index: index,
                pathThumb: pathThumb,
                pathOriginal: pathOriginal,
                width: width,
                height: height,
                bytesOriginal: bytesOriginal,
                hash: hash,
                blurhash: blurhash
            )
        }

        // 연결 안 되어 있으면 실패 메시지 로컬 퍼블리시
        guard socket.status == .connected else {
            let atts = attachments.enumerated().map { makeAttachment(from: $0.element, fallbackIndex: $0.offset) }
            let failed = ChatMessage(
                ID: clientMessageID,
                roomID: roomID,
                senderID: senderID,
                senderNickname: senderNickname,
                msg: "",
                sentAt: now,
                attachments: atts,
                replyPreview: nil,
                isFailed: true
            )
            DispatchQueue.main.async {
                self.roomSubjects[roomID]?.send(failed)
            }
            return
        }
            
        // 1) 서버 이벤트/페이로드 구성(메타만 포함)
        let eventName = "send images" // 새 프로토콜 이벤트명 (서버 index.js와 일치)
        let body: [String: Any] = [
            "roomID": roomID,
            "messageID": clientMessageID,
            "type": "image",
            "msg": "",
            "attachments": attachments,
            "senderID": senderID,
            "senderNickname": senderNickname,
            "sentAt": isoSentAt
        ]

        // 2) Ack 포함 전송 → 성공 시 로컬 퍼블리시
        socket.emitWithAck(eventName, body).timingOut(after: 15) { [weak self] ackResponse in
            guard let self = self else { return }
            let ack = ackResponse.first as? [String: Any]
            let ok = (ack?["ok"] as? Bool) ?? (ack?["success"] as? Bool) ?? false
            let duplicate = (ack?["duplicate"] as? Bool) ?? false

            let atts = attachments.enumerated().map { makeAttachment(from: $0.element, fallbackIndex: $0.offset) }
            let message = ChatMessage(
                ID: clientMessageID,
                roomID: roomID,
                senderID: senderID,
                senderNickname: senderNickname,
                msg: "",
                sentAt: now,
                attachments: atts,
                replyPreview: nil,
                isFailed: !(ok || duplicate)
            )

            if ok || duplicate {
                Task {
                    await FirebaseManager.shared.updateRoomLastMessageAt(roomID: roomID, date: now)
                }
            }
            DispatchQueue.main.async {
                self.roomSubjects[roomID]?.send(message)
            }
        }
    }
    
    /// 업로드/송신 실패 시: preparePairs에서 받은 ImagePair 배열을 이용해
    /// 로컬 프리뷰 파일을 만들고 실패 메시지(ChatMessage)를 생성한다.
    /// - Parameters:
    ///   - room: 대상 방
    ///   - pairs: ImagePair 배열 (index 순서로 정렬됨이 보장되지는 않음)
    ///   - publish: true면 내부에서 roomSubject로 곧바로 퍼블리시, false면 퍼블리시하지 않음
    ///   - onBuilt: 실패 메시지 객체를 콜백으로 전달(썸네일 캐시/추가 가공 후 VC에서 addMessages 호출용)
    func sendFailedImages(_ room: ChatRoom,
                          fromPairs pairs: [MediaManager.ImagePair],
                          publish: Bool = true) {
        guard !pairs.isEmpty else { return }

        let roomID = room.ID ?? ""
        let senderID = LoginManager.shared.getUserEmail
        let senderNickname = LoginManager.shared.currentUserProfile?.nickname ?? ""

        // 로컬 파일 저장 디렉터리 (앱 캐시)
        let fm = FileManager.default
        let baseDir: URL = {
            let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("failed-attachments", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }()

        @discardableResult
        func writeTempFile(_ data: Data, ext: String = "jpg") -> URL? {
            let name = UUID().uuidString + "." + ext
            let url = baseDir.appendingPathComponent(name)
            do {
                try data.write(to: url, options: .atomic)
                return url
            } catch {
                print("[sendFailedImages] failed to write temp file: \(error)")
                return nil
            }
        }

        var atts: [Attachment] = []
        atts.reserveCapacity(pairs.count)

        for p in pairs.sorted(by: { $0.index < $1.index }) {
            autoreleasepool {
                guard let fileURL = writeTempFile(p.thumbData) else { return }
                let att = Attachment(
                    type: .image,
                    index: p.index,
                    pathThumb: fileURL.absoluteString,     // "file://" 로컬 경로
                    pathOriginal: fileURL.absoluteString,  // 뷰어에서도 프리뷰 노출을 위해 동일 경로
                    width: p.originalWidth,
                    height: p.originalHeight,
                    bytesOriginal: p.thumbData.count,
                    hash: p.sha256,
                    blurhash: nil
                )
                atts.append(att)
            }
        }

        let failedMessage = ChatMessage(
            ID: UUID().uuidString,
            roomID: roomID,
            senderID: senderID,
            senderNickname: senderNickname,
            msg: "",
            sentAt: Date(),
            attachments: atts,
            replyPreview: nil,
            isFailed: true
        )

        DispatchQueue.main.async {
            self.roomSubjects[roomID]?.send(failedMessage)
        }
    }

    
    private func processFailedImages(_ room: ChatRoom, _ images: [UIImage]) async {
        // 빈 입력이면 종료
        guard !images.isEmpty else { return }

        // 실패 시에도 메모리 사용을 줄이기 위해 다운스케일 + 압축(로컬 프리뷰용)
        let maxDimension: CGFloat = 1600
        let jpegQuality: CGFloat = 0.6

        // 로컬 파일 저장 디렉터리 (앱 캐시)
        let fm = FileManager.default
        let baseDir: URL = {
            let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("failed-attachments", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }()

        // 헬퍼: 이미지 다운스케일 후 JPEG Data 생성
        func downscaleJPEGData(_ image: UIImage, maxEdge: CGFloat, quality: CGFloat) -> Data? {
            let size = image.size
            guard size.width > 0 && size.height > 0 else { return image.jpegData(compressionQuality: quality) }
            let scale = Swift.min(1.0, maxEdge / Swift.max(size.width, size.height))
            let targetSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
            if scale >= 1.0 {
                return image.jpegData(compressionQuality: quality)
            }
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1.0
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            let scaled = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            return scaled.jpegData(compressionQuality: quality)
        }

        // 헬퍼: SHA-256(hex)
        func sha256Hex(_ data: Data) -> String {
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        }

        // 헬퍼: 캐시 디렉터리에 파일 저장 후 file:// URL 반환
        func writeTempFile(_ data: Data, ext: String = "jpg") -> URL? {
            let name = UUID().uuidString + "." + ext
            let url = baseDir.appendingPathComponent(name)
            do {
                try data.write(to: url, options: .atomic)
                return url
            } catch {
                print("failed to write temp file: \(error)")
                return nil
            }
        }

        var localAttachments: [Attachment] = []
        localAttachments.reserveCapacity(images.count)

        // 순차 처리 + autoreleasepool로 메모리 피크 완화
        for (idx, image) in images.enumerated() {
            autoreleasepool {
                guard let data = downscaleJPEGData(image, maxEdge: maxDimension, quality: jpegQuality),
                      let fileURL = writeTempFile(data) else { return }

                let hash = sha256Hex(data)
                let pw = image.cgImage?.width ?? Int(image.size.width * image.scale)
                let ph = image.cgImage?.height ?? Int(image.size.height * image.scale)

                // 메타 전용 Attachment (로컬 미리보기이므로 Thumb/Original을 동일 파일로 설정)
                let att = Attachment(
                    type: .image,
                    index: idx,
                    pathThumb: fileURL.absoluteString,     // "file://" 경로
                    pathOriginal: fileURL.absoluteString,  // "file://" 경로
                    width: pw,
                    height: ph,
                    bytesOriginal: data.count,
                    hash: hash,
                    blurhash: nil
                )
                localAttachments.append(att)
            }
        }

        // 일부라도 생성되었으면 실패 메시지 전송 (메타만 포함)
        guard !localAttachments.isEmpty else { return }
        let failedMessage = ChatMessage(
            ID: UUID().uuidString,
            roomID: room.ID ?? "",
            senderID: LoginManager.shared.getUserEmail,
            senderNickname: LoginManager.shared.currentUserProfile?.nickname ?? "",
            msg: "",
            sentAt: Date(),
            attachments: localAttachments,
            replyPreview: nil,
            isFailed: true
        )

        await MainActor.run {
            self.roomSubjects[room.ID ?? ""]?.send(failedMessage)
        }
    }
    
    // MARK: - Send: Video
    /// 비디오 메타만 서버로 전송 (바이너리 X). 서버는 이 메타로 메시지를 생성/중계한다.
    /// - Parameters:
    ///   - roomID: 방 ID
    ///   - payload: 업로드 완료된 비디오의 메타 정보
    ///   - ackTimeout: (선택) ACK 대기 시간
    ///   - completion: (선택) 성공/실패 콜백
    // MARK: - Send: Video
    /// 비디오 메타만 서버로 전송 (바이너리 X). 서버는 이 메타로 메시지를 생성/중계한다.
    /// 소켓 미연결/ACK 실패 시 로컬 실패 메시지를 주입한다.
    func sendVideo(roomID: String,
                   payload: VideoMetaPayload,
                   ackTimeout: Double = 5.0,
                   completion: ((Result<Void, Error>) -> Void)? = nil) {
        let dict: [String: Any] = [
            "roomID": payload.roomID,
            "messageID": payload.messageID,
            "storagePath": payload.storagePath,
            "thumbnailPath": payload.thumbnailPath,
            "duration": payload.duration,
            "width": payload.width,
            "height": payload.height,
            "sizeBytes": payload.sizeBytes,
            "approxBitrateMbps": payload.approxBitrateMbps,
            "preset": payload.preset,
            // (선택) 보낸이 정보 포함
            "senderID": LoginManager.shared.getUserEmail,
            "senderNickname": LoginManager.shared.currentUserProfile?.nickname ?? ""
        ]

        #if canImport(SocketIO)
        if socket.status == .connected {
            socket.emitWithAck("chat:video", dict).timingOut(after: ackTimeout) { [weak self] items in
                guard let self = self else { return }
                // 서버에서 { ok: true } 형태로 응답한다고 가정
                if let first = items.first as? [String: Any],
                   let ok = first["ok"] as? Bool, ok == true {
                    completion?(.success(()))
                } else if items.isEmpty {
                    // 응답이 없어도 성공 처리(서버 ACK 미사용 환경)
                    completion?(.success(()))
                } else {
                    // ACK 실패 → 로컬 실패 메시지 주입
                    self.sendFailedVideos(roomID: payload.roomID, payload: payload)
                    let err = NSError(domain: "SocketIO", code: -1,
                                      userInfo: [NSLocalizedDescriptionKey: "서버 ACK 실패 또는 형식 불일치: \(items)"])
                    completion?(.failure(err))
                }
            }
        } else {
            // 미연결: 실패 메시지 먼저 주입하고 재연결 시도
            self.sendFailedVideos(roomID: payload.roomID, payload: payload)
            socket.connect()
            let err = NSError(domain: "SocketIO", code: -1009,
                              userInfo: [NSLocalizedDescriptionKey: "소켓이 연결되어 있지 않습니다."])
            completion?(.failure(err))
        }
        #else
        // SocketIO 미링크 환경에서도 컴파일 가능하도록
        completion?(.success(()))
        #endif
    }
    
    // MARK: - Local Fail: Video
    /// 업로드 실패 또는 소켓 미연결 시, 로컬에서 '실패한 비디오 메시지'를 스트림에 주입합니다.
    /// 서버로는 아무 것도 전송하지 않으며, 재시도 UX를 위해 타임라인에 즉시 반영합니다.
    /// - Parameters:
    ///   - roomID: 방 ID
    ///   - senderID: 보낸 사람 UID
    ///   - senderNickname: 보낸 사람 닉네임
    ///   - localURL: 압축된 비디오의 로컬 파일 URL (mp4 등)
    ///   - thumbData: 썸네일 JPEG 데이터(옵션). 있으면 임시 파일로 저장해 pathThumb에 넣습니다.
    ///   - duration: 비디오 길이(초)
    ///   - width: 비디오 가로 해상도
    ///   - height: 비디오 세로 해상도
    ///   - presetCode: "standard720" | "dataSaver720" | "high1080" 등 (로깅용)
    func sendFailedVideos(roomID: String,
                          senderID: String,
                          senderNickname: String,
                          localURL: URL,
                          thumbData: Data?,
                          duration: Double,
                          width: Int,
                          height: Int,
                          presetCode: String) {
        // 1) 파일 크기
        let bytes: Int64 = (try? (FileManager.default
            .attributesOfItem(atPath: localURL.path)[.size] as? NSNumber)?.int64Value) ?? 0
        
        // 2) 썸네일을 임시 경로로 저장 (UI에서 즉시 표시 가능)
        var thumbPath: String = ""
        if let data = thumbData, !data.isEmpty {
            let thumbURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("vidthumb_\(UUID().uuidString).jpg")
            do {
                try data.write(to: thumbURL, options: .atomic)
                thumbPath = thumbURL.path
            } catch {
                #if DEBUG
                print("[sendFailedVideos] thumbnail write failed:", error)
                #endif
            }
        }
        
        // 3) 실패 메시지용 ID/해시
        let clientMessageID = "failed-\(UUID().uuidString)"
        
        // 4) 첨부(.video) 구성 — 로컬 경로를 그대로 넣어 미리보기/재시도에 활용
        let attachment = Attachment(
            type: .video,
            index: 0,
            pathThumb: thumbPath,
            pathOriginal: localURL.path,
            width: width,
            height: height,
            bytesOriginal: Int(bytes),
            hash: clientMessageID,
            blurhash: nil
        )
        
        // 5) 실패 ChatMessage 구성
        let message = ChatMessage(
            ID: clientMessageID,
            roomID: roomID,
            senderID: senderID,
            senderNickname: senderNickname,
            msg: "",
            sentAt: Date(),
            attachments: [attachment],
            replyPreview: nil,
            isFailed: true,
            isDeleted: false
        )
        
        #if DEBUG
        print("[sendFailedVideos] roomID=\(roomID) preset=\(presetCode) duration=\(duration)s size=\(bytes)B")
        #endif
        
        // 6) 로컬 스트림으로 즉시 발행 (UI 업데이트)
        DispatchQueue.main.async {
            self.roomSubjects[roomID]?.send(message)
        }
    }
    
    /// 업로드는 성공했으나 소켓 전송(브로드캐스트)이 실패한 경우: 원격(Storage) 경로 기반으로 실패 메시지 발행
    func sendFailedVideos(roomID: String, payload: VideoMetaPayload) {
        let senderID = LoginManager.shared.getUserEmail
        let senderNickname = LoginManager.shared.currentUserProfile?.nickname ?? ""

        // 서버 브로드캐스트 포맷과 동일한 첨부(.video), 단 isFailed만 true
        let attachment = Attachment(
            type: .video,
            index: 0,
            pathThumb: payload.thumbnailPath,
            pathOriginal: payload.storagePath,
            width: payload.width,
            height: payload.height,
            bytesOriginal: Int(payload.sizeBytes),
            hash: payload.messageID,
            blurhash: nil
        )

        // 실패 메시지 ID는 충돌 방지를 위해 prefix 부여
        let failedID = "failed-\(payload.messageID)"
        let message = ChatMessage(
            ID: failedID,
            roomID: roomID,
            senderID: senderID,
            senderNickname: senderNickname,
            msg: "",
            sentAt: Date(),
            attachments: [attachment],
            replyPreview: nil,
            isFailed: true,
            isDeleted: false
        )

        DispatchQueue.main.async {
            self.roomSubjects[roomID]?.send(message)
        }
    }
    
    func setUserName(_ userName: String) {
        print("setUserName 호출됨: \(userName)")
        socket.emit("set username", userName)
        print("유저 이름 이벤트 emit 완료")
    }

    func notifyNewParticipant(roomID: String, email: String) {
        guard socket.status == .connected else {
            print("소켓이 연결되어 있지 않아 새 참여자 알림 emit 실패")
            return
        }
        
        print("새 참여자 알림 emit - room: \(roomID), email: \(email)")
        socket.emit("new participant joined", roomID, email)
    }
    
    func listenToNewParticipant() {
        socket.off("room participant updated")
        socket.on("room participant updated") { [weak self] data, _ in
            guard let self = self,
                  let dict = data.first as? [String: String],
                  let roomID = dict["roomID"],
                  let email = dict["email"] else {
                print("room participant updated 수신 실패: 데이터 형식 불일치")
                return
            }

            Task { @MainActor in
                do {
                    let profile = try await FirebaseManager.shared.fetchUserProfileFromFirestore(email: email)
                    
                    // GRDB를 통해 로컬 DB에 저장
                    try await GRDBManager.shared.dbPool.write { db in
                        try profile.save(db)
                        try db.execute(
                            sql: "INSERT OR REPLACE INTO roomParticipant (roomID, email) VALUES (?, ?)",
                            arguments: [roomID, email]
                        )
                    }
                    
                    // 새로운 참여자 알림 발행
                    self.participantSubject.send((roomID, email))
                    
                } catch {
                    print("새 참여자 프로필 불러오기/저장 실패: \(error)")
                }
            }
        }
    }
}


