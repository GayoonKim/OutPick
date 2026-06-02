//
//  LoadLikedPostsUseCase.swift
//  OutPick
//
//  Created by Codex on 6/2/26.
//

import Foundation
import FirebaseFirestore

struct LikedPostListItem: Equatable, Identifiable {
    var id: String { "\(post.brandID.value)_\(post.seasonID.value)_\(post.id.value)" }
    let post: LookbookPost
    let userState: PostUserState
}

struct LikedPostPage {
    let items: [LikedPostListItem]
    let last: DocumentSnapshot?
}

protocol LoadLikedPostsUseCaseProtocol {
    func execute(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> LikedPostPage
}

final class LoadLikedPostsUseCase: LoadLikedPostsUseCaseProtocol {
    private let postUserStateRepository: any PostUserStateRepositoryProtocol
    private let postRepository: any PostRepositoryProtocol

    init(
        postUserStateRepository: any PostUserStateRepositoryProtocol,
        postRepository: any PostRepositoryProtocol
    ) {
        self.postUserStateRepository = postUserStateRepository
        self.postRepository = postRepository
    }

    func execute(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> LikedPostPage {
        let statePage = try await postUserStateRepository.fetchLikedPostUserStates(
            userID: userID,
            limit: limit,
            after: last
        )

        var items: [LikedPostListItem] = []
        items.reserveCapacity(statePage.items.count)

        for state in statePage.items where state.isLiked {
            guard let brandID = state.brandID,
                  let seasonID = state.seasonID else { continue }

            do {
                let post = try await postRepository.fetchPost(
                    brandID: brandID,
                    seasonID: seasonID,
                    postID: state.postID
                )
                items.append(LikedPostListItem(post: post, userState: state))
            } catch {
                continue
            }
        }

        return LikedPostPage(items: items, last: statePage.last)
    }
}
