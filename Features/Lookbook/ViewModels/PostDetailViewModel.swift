//
//  PostDetailViewModel.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import Foundation

@MainActor
final class PostDetailScreenViewModel: ObservableObject {
    @Published private(set) var post: LookbookPost?
    @Published private(set) var comments: [Comment] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var commentErrorMessage: String?

    private var loadedKey: String?
    private var isRequesting = false

    func loadIfNeeded(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        useCase: any LoadPostDetailUseCaseProtocol
    ) async {
        let key = "\(brandID.value)|\(seasonID.value)|\(postID.value)"
        guard loadedKey != key else { return }
        await load(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            useCase: useCase
        )
    }

    func refresh(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        useCase: any LoadPostDetailUseCaseProtocol
    ) async {
        loadedKey = nil
        await load(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            useCase: useCase
        )
    }

    private func load(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        useCase: any LoadPostDetailUseCaseProtocol
    ) async {
        if isRequesting { return }
        isRequesting = true
        isLoading = true
        errorMessage = nil
        commentErrorMessage = nil
        defer {
            isRequesting = false
            isLoading = false
        }

        do {
            let content = try await useCase.execute(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID
            )
            post = content.post
            comments = content.comments
            commentErrorMessage = content.commentErrorMessage
            loadedKey = "\(brandID.value)|\(seasonID.value)|\(postID.value)"
        } catch {
            post = nil
            comments = []
            errorMessage = "포스트를 불러오지 못했습니다."
            commentErrorMessage = nil
        }
    }
}
