//
//  FirestoreMapper.swift
//  OutPick
//
//  Created by 김가윤 on 12/17/25.
//

import FirebaseFirestore

enum FirestoreMapper {
    /// 지정된 DocumentSnapshot을 Decodable 타입으로 변환합니다.
    /// - Parameter snapshot: 매핑할 Firestore 문서 스냅샷
    /// - Returns: 스냅샷의 내용을 담은 타입 `T` 인스턴스
    /// - Throws: 데이터가 없거나 디코딩 실패 시 오류를 throw
    static func mapDocument<T: Decodable>(_ snapshot: DocumentSnapshot) throws -> T {
        // `data(as:)`는 문서의 데이터를 `T` 타입으로 디코딩합니다 [oai_citation:1‡firebase.google.com](https://firebase.google.com/docs/firestore/solutions/swift-codable-data-mapping#:~:text=docRef.getDocument%20,self%29).
        return try snapshot.data(as: T.self)
    }
}
