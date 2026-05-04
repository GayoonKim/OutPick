//
//  PostCommentsViewModel.swift
//  OutPick
//
//  Created by Codex on 5/1/26.
//

import Foundation

@MainActor
final class PostCommentsViewModel: ObservableObject {
    @Published private(set) var pinnedComments: [Comment] = []
    @Published private(set) var representativeComment: Comment?
    @Published private(set) var rootComments: [Comment] = []
    @Published private(set) var selectedSort: CommentSortOption
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var isSubmittingComment: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var submissionErrorMessage: String?
    @Published var draftMessage: String = ""

    private let brandID: BrandID
    private let seasonID: SeasonID
    private let postID: PostID
    private let useCase: any LoadPostCommentsUseCaseProtocol
    private let createUseCase: any CreatePostCommentUseCaseProtocol
    private let pageSize: Int

    private var nextCursor: PageCursor?
    private var loadedKey: String?
    private var isRequestingPage: Bool = false

    var hasMoreRootComments: Bool {
        nextCursor != nil
    }

    var canSubmitComment: Bool {
        draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            isSubmittingComment == false
    }

    init(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        useCase: any LoadPostCommentsUseCaseProtocol,
        createUseCase: any CreatePostCommentUseCaseProtocol,
        initialSort: CommentSortOption = .latest,
        pageSize: Int = 30
    ) {
        self.brandID = brandID
        self.seasonID = seasonID
        self.postID = postID
        self.useCase = useCase
        self.createUseCase = createUseCase
        self.selectedSort = initialSort
        self.pageSize = pageSize
    }

    func loadIfNeeded() async {
        let key = stateKey(sort: selectedSort)
        guard loadedKey != key else { return }
        await loadPage(reset: true)
    }

    func refresh() async {
        loadedKey = nil
        await loadPage(reset: true)
    }

    func selectSort(_ sort: CommentSortOption) async {
        guard selectedSort != sort else { return }
        selectedSort = sort
        loadedKey = nil
        await loadPage(reset: true)
    }

    func loadNextPage() async {
        guard hasMoreRootComments else { return }
        await loadPage(reset: false)
    }

    @discardableResult
    func submitComment() async -> CommentMutationResult? {
        guard isSubmittingComment == false else { return nil }

        let message = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.isEmpty == false else {
            submissionErrorMessage = CommentSubmissionError.emptyMessage.localizedDescription
            return nil
        }

        isSubmittingComment = true
        submissionErrorMessage = nil
        defer {
            isSubmittingComment = false
        }

        do {
            let result = try await createUseCase.execute(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                message: message
            )
            draftMessage = ""
            loadedKey = nil
            await loadPage(reset: true)
            return result
        } catch {
            submissionErrorMessage = "댓글을 등록하지 못했습니다."
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
            if reset {
                let content = try await useCase.execute(
                    brandID: brandID,
                    seasonID: seasonID,
                    postID: postID,
                    sort: selectedSort,
                    page: PageRequest(size: pageSize, cursor: nil)
                )
                pinnedComments = content.pinnedComments
                representativeComment = content.representativeComment
                nextCursor = content.rootComments.nextCursor
                rootComments = content.rootComments.items
                loadedKey = stateKey(sort: selectedSort)
            } else {
                let page = try await useCase.loadRootComments(
                    brandID: brandID,
                    seasonID: seasonID,
                    postID: postID,
                    sort: selectedSort,
                    page: PageRequest(size: pageSize, cursor: nextCursor)
                )
                let excludedIDs = duplicateExcludedIDs()
                let visibleItems = page.items.filter {
                    excludedIDs.contains($0.id) == false
                }
                nextCursor = page.nextCursor
                rootComments.append(contentsOf: visibleItems)
            }
        } catch {
            errorMessage = "댓글을 불러오지 못했습니다."
        }
    }

    private func duplicateExcludedIDs() -> Set<CommentID> {
        var ids = Set(pinnedComments.map(\.id))
        if let representativeComment {
            ids.insert(representativeComment.id)
        }
        return ids
    }

    private func stateKey(sort: CommentSortOption) -> String {
        "\(brandID.value)|\(seasonID.value)|\(postID.value)|\(sort.rawValue)"
    }
}
