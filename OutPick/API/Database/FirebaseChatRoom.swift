//
//  FirebaseChatRoom.swift
//  OutPick
//
//  Created by 김가윤 on 10/2/24.
//

import Foundation
import FirebaseCore
import FirebaseFirestore

// 방 정보 저장 함수
func saveRoomInfoToFirestore(room: ChatRoom, completion: @escaping (Result<Void, Error>) -> Void) {
    
    let db = Firestore.firestore()
    
    // 방 컬렉션에서 방 ID를 기준으로 문서 참조 생성
    let roomRef = db.collection("rooms").document(room.roomName)
    
    db.runTransaction({ (transaction, errorPointer) -> Any? in
        // 방 정보가 이미 존재하는지 확인
        do {
            let roomSnapshot = try transaction.getDocument(roomRef)
            
            // 방이 이미 존재하면 오류 처리 (방 이름 중복 방지)
            if roomSnapshot.exists {
                errorPointer?.pointee = NSError(domain: "ChatAppErrorDomain", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "방 이름 중복"
                ])
                return nil
            }
            
            // Firestore에 방 데이터 추가
            transaction.setData(room.toDictionary(), forDocument: roomRef)
            
        } catch {
            // 트랜잭션 실패 처리
            errorPointer?.pointee = error as NSError
            return nil
        }
        
        return nil
    }) { (object, error) in
        // 트랜잭션 완료 처리
        if let error = error {
            print("트랜잭션 실패: \(error)")
            completion(.failure(error))
        } else {
            print("트랜잭션 성공")
            completion(.success(()))
        }
    }
    
}
