//
//  PostCommentRepliesViewModel.swift
//  OutPick
//
//  Created by Codex on 5/1/26.
//

import Foundation

@MainActor
final class PostCommentRepliesViewModel: ObservableObject {
    @Published private(set) var replies: [Comment] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var isSubmittingReply: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var submissionErrorMessage: String?
    @Published var draftMessage: String = ""

    @Published private(set) var parentComment: Comment

    private let brandID: BrandID
    private let seasonID: SeasonID
    private let postID: PostID
    private let useCase: any LoadCommentRepliesUseCaseProtocol
    private let createUseCase: any CreateCommentReplyUseCaseProtocol
    private let pageSize: Int

    private var nextCursor: PageCursor?
    private var loadedKey: String?
    private var isRequestingPage: Bool = false

    var hasMoreReplies: Bool {
        nextCursor != nil
    }

    var canSubmitReply: Bool {
        draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            isSubmittingReply == false
    }

    init(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        parentComment: Comment,
        useCase: any LoadCommentRepliesUseCaseProtocol,
        createUseCase: any CreateCommentReplyUseCaseProtocol,
        pageSize: Int = 30
    ) {
        self.brandID = brandID
        self.seasonID = seasonID
        self.postID = postID
        self.parentComment = parentComment
        self.useCase = useCase
        self.createUseCase = createUseCase
        self.pageSize = pageSize
    }

    func loadIfNeeded() async {
        let key = stateKey()
        guard loadedKey != key else { return }
        await loadPage(reset: true)
    }

    func refresh() async {
        loadedKey = nil
        await loadPage(reset: true)
    }

    func loadNextPage() async {
        guard hasMoreReplies else { return }
        await loadPage(reset: false)
    }

    @discardableResult
    func submitReply() async -> CommentMutationResult? {
        guard isSubmittingReply == false else { return nil }

        let message = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.isEmpty == false else {
            submissionErrorMessage = CommentSubmissionError.emptyMessage.localizedDescription
            return nil
        }

        isSubmittingReply = true
        submissionErrorMessage = nil
        defer {
            isSubmittingReply = false
        }

        do {
            let result = try await createUseCase.execute(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                parentCommentID: parentComment.id,
                message: message
            )
            parentComment.replyCount = result.replyCount
            draftMessage = ""
            loadedKey = nil
            await loadPage(reset: true)
            return result
        } catch {
            submissionErrorMessage = "답글을 등록하지 못했습니다."
            return nil
        }
    }

    private func loadPage(reset: Bool) async {
        guard isRequestingPage == false else { return }
        isRequestingPage = true
        if reset {
            isLoading = true
            errorMessage = nil
        } else {
            isLoadingMore = true
        }
        defer {
            isRequestingPage = false
            isLoading = false
            isLoadingMore = false
        }

        do {
            let page = try await useCase.execute(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                parentCommentID: parentComment.id,
                page: PageRequest(
                    size: pageSize,
                    cursor: reset ? nil : nextCursor
                )
            )

            nextCursor = page.nextCursor
            if reset {
                replies = page.items
                loadedKey = stateKey()
            } else {
                replies.append(contentsOf: page.items)
            }
        } catch {
            errorMessage = "답글을 불러오지 못했습니다."
        }
    }

    private func stateKey() -> String {
        "\(brandID.value)|\(seasonID.value)|\(postID.value)|\(parentComment.id.value)"
    }
}
