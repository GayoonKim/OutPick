//
//  FirebaseChatRoomRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import Combine
import FirebaseFirestore

/// 채팅방 관련 데이터베이스 작업을 위한 프로토콜
protocol FirebaseChatRoomRepositoryProtocol {
    /// 방 목록 캐시 상태
    var topRoomsWithPreviews: [(ChatRoom, [ChatMessage])] { get }
    
    /// 방 변경 이벤트 Publisher
    var roomChangePublisher: AnyPublisher<ChatRoom, Never> { get }

    /// 참여중 방(요약) 변경 이벤트 Publisher
    /// - Note: JoinedRooms 목록의 head 실시간 반영 전용
    var joinedRoomsSummaryPublisher: AnyPublisher<[ChatRoom], Never> { get }

    /// 소켓 실시간 메시지를 참여중 방 요약 스트림에 즉시 반영(로컬 패치)
    /// - Parameters:
    ///   - roomID: 대상 방 ID
    ///   - message: 마지막 메시지 프리뷰
    ///   - sentAt: 마지막 메시지 시각
    ///   - seq: 서버가 전달한 메시지 시퀀스(없으면 nil)
    ///   - senderID: 마지막 메시지 발신자 ID(없으면 nil)
    @MainActor
    func applyRealtimeSummaryPatch(roomID: String, message: String, sentAt: Date, seq: Int64?, senderID: String?)
    
    /// 로컬 방 정보 업데이트 (캐시 갱신)
    func applyLocalRoomUpdate(_ updatedRoom: ChatRoom)
    
    /// Top 방 목록 페이지네이션 조회
    func fetchTopRoomsPage(after lastSnapshot: DocumentSnapshot?, limit: Int) async throws
    
    /// 방의 마지막 메시지 정보 업데이트
    func updateRoomLastMessage(roomID: String, date: Date?, msg: String, senderID: String?) async
    
    /// 방 정보 수정
    func editRoom(room: ChatRoom,
                  pickedImage: UIImage?,
                  imageData: DefaultMediaProcessingService.ImagePair?,
                  isRemoved: Bool,
                  newName: String,
                  newDesc: String) async throws -> ChatRoom
    
    /// 특정 방 문서 조회
    func getRoomDoc(room: ChatRoom) async throws -> DocumentSnapshot?
    
    /// 방 정보 Firestore에 저장
    func saveRoomInfoToFirestore(room: ChatRoom) async throws
    
    /// ID 목록으로 방 목록 조회
    func fetchRoomsWithIDs(byIDs ids: [String]) async throws -> [ChatRoom]
    
    /// 방 이름으로 검색 (페이지네이션 지원)
    func searchRooms(keyword: String, limit: Int, reset: Bool) async throws -> [ChatRoom]
    
    /// 검색 결과 다음 페이지 로드
    func loadMoreSearchRooms(limit: Int) async throws -> [ChatRoom]

    /// 참여중 방 head(요약) 실시간 리스너 시작
    @MainActor
    func startListenJoinedRoomsSummary(userEmail: String, limit: Int)

    /// 참여중 방 head(요약) 실시간 리스너 중지
    @MainActor
    func stopListenJoinedRoomsSummary()

    /// 참여중 방 페이지 조회 (비실시간)
    func fetchJoinedRoomsPage(
        userEmail: String,
        after lastSnapshot: DocumentSnapshot?,
        limit: Int
    ) async throws -> (rooms: [ChatRoom], lastSnapshot: DocumentSnapshot?)

    /// 참여중 방 tail 변경분 조회 (delta sync)
    func fetchJoinedRoomsUpdatedSince(
        userEmail: String,
        since: Date,
        limit: Int
    ) async throws -> [ChatRoom]
    
    /// 단일 방 문서 리스너 시작
    @MainActor
    func startListenRoomDoc(roomID: String)
    
    /// 현재 방 문서 리스너 중지
    @MainActor
    func stopListenRoomDoc()
    
    /// 방 정보 업데이트
    func updateRoomInfo(room: ChatRoom, newImagePath: String, roomName: String, roomDescription: String) async throws
    
    /// 방 이름 중복 검사
    func checkRoomName(roomName: String, completion: @escaping (Bool, Error?) -> Void)

    /// 방 이름 중복 검사 (async/await)
    func checkRoomNameDuplicate(roomName: String) async throws -> Bool
    
    /// 방 참여자 추가
    func addRoomParticipant(room: ChatRoom) async throws
    
    /// 방 참여자 추가 및 최신 방 정보 반환
    func addRoomParticipantReturningRoom(roomID: String) async throws -> ChatRoom
    
    /// 방 참여자 제거
    func removeParticipant(room: ChatRoom)
    
    /// 방의 최신 시퀀스 조회
    func fetchLatestSeq(for roomID: String) async throws -> Int64
}
