//
//  FirebaseChatRoomRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import FirebaseFirestore

struct RoomMemberPage {
    let userIDs: [String]
    let nextCursorUserID: String?
    let hasMore: Bool
}

/// 채팅방 생성 화면이 요구하는 최소 Repository 계약
protocol CreateRoomRepositoryProtocol {
    func checkRoomNameDuplicate(roomName: String) async throws -> Bool
    func createRoom(input: CreateChatRoomInput) async throws -> ChatRoom
    func updateRoomMetadataWithImagePaths(
        roomID: String,
        roomName: String,
        roomDescription: String,
        thumbPath: String,
        originalPath: String
    ) async throws
    func applyLocalRoomUpdate(_ updatedRoom: ChatRoom)
}

/// 채팅방 관련 데이터베이스 작업을 위한 프로토콜
protocol FirebaseChatRoomRepositoryProtocol: CreateRoomRepositoryProtocol {
    /// 방 목록 캐시 상태
    var topRoomsWithPreviews: [(ChatRoom, [ChatMessage])] { get }
    
    /// 로컬 방 정보 업데이트 (캐시 갱신)
    func applyLocalRoomUpdate(_ updatedRoom: ChatRoom)

    /// 로컬 방 목록 캐시에서 방 제거
    func removeLocalRoom(roomID: String)

    /// realtime 수신 메시지를 로컬 방 목록 preview cache에 반영
    func applyLocalIncomingMessagePreview(_ message: ChatMessage)
    
    /// Top 방 목록 페이지네이션 조회
    func fetchTopRoomsPage(after lastSnapshot: DocumentSnapshot?, limit: Int) async throws
    
    /// 방의 마지막 메시지 정보 업데이트
    func updateRoomLastMessage(roomID: String, date: Date?, msg: String, senderUID: String?) async
    
    /// 방 이름/설명만 갱신
    func updateRoomMetadata(
        roomID: String,
        roomName: String,
        roomDescription: String
    ) async throws

    /// 방 이름/설명과 대표 이미지 경로를 함께 갱신
    func updateRoomMetadataWithImagePaths(
        roomID: String,
        roomName: String,
        roomDescription: String,
        thumbPath: String,
        originalPath: String
    ) async throws

    /// 방 이름/설명은 유지하면서 대표 이미지 경로를 제거
    func removeRoomImagePathsAndUpdateMetadata(
        roomID: String,
        roomName: String,
        roomDescription: String
    ) async throws
    
    /// ID 목록으로 방 목록 조회
    func fetchRoomsWithIDs(byIDs ids: [String]) async throws -> [ChatRoom]
    
    /// 방 이름/설명 검색 (페이지네이션 지원)
    func searchRooms(keyword: String, limit: Int, reset: Bool) async throws -> RoomSearchPage
    
    /// 검색 결과 다음 페이지 로드
    func loadMoreSearchRooms(limit: Int) async throws -> RoomSearchPage

    /// 참여중 방 목록 조회 (users/{uid}/joinedRooms projection + Rooms batch fetch)
    func fetchJoinedRoomList(userUID: String) async throws -> [JoinedRoomListItem]

    /// 방 멤버 UID 페이지 조회 (Rooms/{roomID}/members)
    func fetchRoomMembersPage(roomID: String, limit: Int, afterUserID: String?) async throws -> RoomMemberPage

    /// 방 정보 업데이트
    func updateRoomInfo(room: ChatRoom, newImagePath: String, roomName: String, roomDescription: String) async throws
    
    /// 방 이름 중복 검사
    func checkRoomName(roomName: String, completion: @escaping (Bool, Error?) -> Void)

    /// 방 참여자 추가 및 최신 방 정보 반환
    func addRoomParticipantReturningRoom(roomID: String) async throws -> ChatRoom
    
    /// 방 참여자 제거
    func removeParticipant(room: ChatRoom)
    
    /// 방의 최신 시퀀스 조회
    func fetchLatestSeq(for roomID: String) async throws -> Int64
}
