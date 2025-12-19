//
//  ReplacementDTO.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

struct ReplacementItemDTO: Codable {
    @DocumentID var id: String?

    /// replacements가 `posts/{postId}/replacements/{replacementId}`라면 postID는 경로에서 주입하는 편이 깔끔합니다.
    /// 전역 조회가 필요하면 문서에 postID를 중복 저장해도 됩니다.
    let postID: String?

    let title: String
    let brandName: String?
//    let price: Int?
//    let currency: String?
//    let buyURL: String?
    let imageURL: String?
    let tagIDs: [String]?
//    let createdBy: String?
    let createdAt: Timestamp?

    func toDomain(postID: PostID) throws -> ReplacementItem {
        guard let id else { throw MappingError.missingDocumentID }

        return ReplacementItem(
            id: ReplacementID(value: id),
            postID: postID,
            title: title,
            brandName: brandName,
//            price: price,
//            currency: currency,
//            buyURL: buyURL.flatMap(URL.init(string:)),
            imageURL: imageURL.flatMap(URL.init(string:)),
            tagIDs: (tagIDs ?? []).map { TagID(value: $0) },
//            createdBy: createdBy.map { UserID(value: $0) },
            createdAt: createdAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
        )
    }

    /// 선택: 문서에 postID가 포함된 경우
    func toDomainFromEmbeddedPostID() throws -> ReplacementItem {
        guard let embeddedPostID = postID, !embeddedPostID.isEmpty else {
            throw MappingError.missingRequiredField("postID")
        }
        return try toDomain(postID: PostID(value: embeddedPostID))
    }
}
