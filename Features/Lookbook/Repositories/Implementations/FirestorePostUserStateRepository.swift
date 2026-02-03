//
//  FirestorePostUserStateRepository.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

final class FirestorePostUserStateRepository: PostUserStateRepositoryProtocol {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchPostUserState(userID: UserID, postID: PostID) async throws -> PostUserState? {
        let doc = try await db
            .collection("Users")
            .document(userID.value)
            .collection("postStates")
            .document(postID.value)
            .getDocument()

        /// 문서가 없으면 nil
        guard doc.exists else { return nil }

        let dto: PostUserStateDTO = try FirestoreMapper.mapDocument(doc)
        /// 경로에서 주입(권장)
        return dto.toDomain(postID: postID, userID: userID)
    }
}
