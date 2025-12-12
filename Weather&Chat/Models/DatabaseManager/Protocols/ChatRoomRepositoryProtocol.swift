//
//  ChatRoomRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import Combine
import FirebaseFirestore

/// 채팅방 관련 데이터베이스 작업을 위한 프로토콜
protocol ChatRoomRepositoryProtocol {
    /// 방 목록 캐시 상태
    var topRoomsWithPreviews: [(ChatRoom, [ChatMessage])] { get }
    
    /// 방 변경 이벤트 Publisher
    var roomChangePublisher: AnyPublisher<ChatRoom, Never> { get }
    
    /// 로컬 방 정보 업데이트 (캐시 갱신)
    func applyLocalRoomUpdate(_ updatedRoom: ChatRoom)
    
    /// Top 방 목록 페이지네이션 조회
    func fetchTopRoomsPage(after lastSnapshot: DocumentSnapshot?, limit: Int) async throws
    
    /// 방의 마지막 메시지 정보 업데이트
    func updateRoomLastMessage(roomID: String, date: Date?, msg: String) async
    
    /// 방 정보 수정
    func editRoom(room: ChatRoom,
                  pickedImage: UIImage?,
                  imageData: MediaManager.ImagePair?,
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
    
    /// 단일 방 문서 리스너 시작
    func startListenRoomDoc(roomID: String)
    
    /// 여러 방 문서 리스너 시작 (배치)
    func startListenRoomDocs(roomIDs: [String])
    
    /// 모든 방 문서 리스너 중지
    func stopListenAllRoomDocs()
    
    /// 방 정보 업데이트
    func updateRoomInfo(room: ChatRoom, newImagePath: String, roomName: String, roomDescription: String) async throws
    
    /// 방 이름 중복 검사
    func checkRoomName(roomName: String, completion: @escaping (Bool, Error?) -> Void)
    
    /// 방 참여자 추가
    func add_room_participant(room: ChatRoom) async throws
    
    /// 방 참여자 추가 및 최신 방 정보 반환
    func add_room_participant_returningRoom(roomID: String) async throws -> ChatRoom
    
    /// 방 참여자 제거
    func remove_participant(room: ChatRoom)
    
    /// 방의 최신 시퀀스 조회
    func fetchLatestSeq(for roomID: String) async throws -> Int64
}

