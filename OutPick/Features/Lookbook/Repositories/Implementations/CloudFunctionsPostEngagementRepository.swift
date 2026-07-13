//
//  CloudFunctionsPostEngagementRepository.swift
//  OutPick
//
//  Created by Codex on 4/28/26.
//

import Foundation

final class CloudFunctionsPostEngagementRepository: PostEngagementRepositoryProtocol {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) {
        self.transport = transport
    }

    func setLike(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        isLiked: Bool
    ) async throws -> PostEngagementResult {
        try await setEngagement(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            kind: "like",
            isEnabled: isLiked
        )
    }

    func setSave(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        isSaved: Bool
    ) async throws -> PostEngagementResult {
        try await setEngagement(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            kind: "save",
            isEnabled: isSaved
        )
    }

    private func setEngagement(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        kind: String,
        isEnabled: Bool
    ) async throws -> PostEngagementResult {
        let response = try await transport.call(
            "setPostEngagement",
            data: [
                "brandID": brandID.value,
                "seasonID": seasonID.value,
                "postID": postID.value,
                "kind": kind,
                "isEnabled": isEnabled
            ]
        )
        return try EngagementCloudFunctionsMapper.post(
            response,
            brandID: brandID,
            seasonID: seasonID
        )
    }
}
