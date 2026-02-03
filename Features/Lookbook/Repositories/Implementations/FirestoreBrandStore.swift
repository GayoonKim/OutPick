//
//  FirestoreBrandStore.swift
//  OutPick
//
//  Created by 김가윤 on 1/13/26.
//

import Foundation
import FirebaseFirestore

/// Firestore 기반 BrandStoring 구현입니다.
struct FirestoreBrandStore: BrandStoringRepository {
    let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func makeNewBrandDocumentID() -> String {
        db.collection("brands").document().documentID
    }

    func upsertBrand(
        docID: String,
        name: String,
        logoThumbPath: String?,
        logoOriginalPath: String?,
        isFeatured: Bool
    ) async throws {
        let data: [String: Any] = [
            "name": name,

            // 한국어 주석: 호환을 위해 기존 UI가 logoPath만 읽는 경우를 대비해 썸네일 경로를 넣습니다.
            "logoPath": logoThumbPath ?? NSNull(),

            // 한국어 주석: 신규 필드 - 썸네일/원본 분리 저장
            "logoThumbPath": logoThumbPath ?? NSNull(),
            "logoOriginalPath": logoOriginalPath ?? NSNull(),

            "isFeatured": isFeatured,
            "likeCount": 0,
            "viewCount": 0,
            "popularScore": 0.0,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        try await db
            .collection("brands")
            .document(docID)
            .setDataAsync(data, merge: true)
    }
}

// MARK: - Firestore async 브릿지 (setData completion -> async/await)

private extension DocumentReference {
    /// Firebase 버전에 따라 setData의 async 지원이 없을 수 있어 안전하게 브릿지합니다.
    func setDataAsync(_ documentData: [String: Any], merge: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.setData(documentData, merge: merge) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
