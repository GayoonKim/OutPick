//
//  PostCommentsSheetView.swift
//  OutPick
//
//  Created by Codex on 5/1/26.
//

import SwiftUI

struct PostCommentsSheetView: View {
    @StateObject private var viewModel: PostCommentsViewModel
    private let navigationCoordinator: LookbookCoordinator
    private let brandID: BrandID
    private let seasonID: SeasonID
    private let postID: PostID
    @ObservedObject private var coordinator: PostCommentCoordinator
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var brandAdminSessionStore: BrandAdminSessionStore
    @State private var pendingDeleteItem: CommentDisplayItem?
    @State private var pendingReportItem: CommentDisplayItem?
    @State private var pendingBlockItem: CommentDisplayItem?
    @State private var isConfirmingDelete: Bool = false
    @State private var isSelectingReportReason: Bool = false
    @State private var isConfirmingBlock: Bool = false
    private let onCommentSubmitted: (CommentMutationResult) -> Void
    private let onCommentDeleted: (CommentDeletionResult) -> Void

    init(
        viewModel: PostCommentsViewModel,
        navigationCoordinator: LookbookCoordinator,
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        coordinator: PostCommentCoordinator,
        onCommentSubmitted: @escaping (CommentMutationResult) -> Void = { _ in },
        onCommentDeleted: @escaping (CommentDeletionResult) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.navigationCoordinator = navigationCoordinator
        self.brandID = brandID
        self.seasonID = seasonID
        self.postID = postID
        self.coordinator = coordinator
        self.onCommentSubmitted = onCommentSubmitted
        self.onCommentDeleted = onCommentDeleted
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView(showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if shouldShowInitialLoading {
                        loadingSection
                    } else {
                        commentsContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
        .background(Color(red: 0.98, green: 0.97, blue: 0.95).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            inputBar
        }
        .sheet(isPresented: replySheetBinding) {
            repliesSheet
        }
        .sheet(isPresented: profileSheetBinding) {
            profileSheet
        }
        .task {
            await viewModel.loadIfNeeded()
            await brandAdminSessionStore.refreshWritableBrands()
        }
        .confirmationDialog(
            "댓글을 삭제할까요?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                guard let pendingDeleteItem else { return }
                Task {
                    if let result = await viewModel.deleteComment(pendingDeleteItem.comment) {
                        onCommentDeleted(result)
                    }
                    self.pendingDeleteItem = nil
                }
            }
            Button("취소", role: .cancel) {
                pendingDeleteItem = nil
            }
        }
        .confirmationDialog(
            "신고 사유를 선택해주세요.",
            isPresented: $isSelectingReportReason,
            titleVisibility: .visible
        ) {
            ForEach(CommentReportReason.allCases, id: \.self) { reason in
                Button(reason.title, role: .destructive) {
                    guard let pendingReportItem else { return }
                    Task {
                        await viewModel.reportComment(
                            pendingReportItem.comment,
                            author: pendingReportItem.author,
                            reason: reason
                        )
                        self.pendingReportItem = nil
                    }
                }
            }
            Button("취소", role: .cancel) {
                pendingReportItem = nil
            }
        }
        .confirmationDialog(
            "이 사용자를 차단할까요?",
            isPresented: $isConfirmingBlock,
            titleVisibility: .visible
        ) {
            Button("차단", role: .destructive) {
                guard let pendingBlockItem else { return }
                Task {
                    await viewModel.blockAuthor(
                        of: pendingBlockItem.comment,
                        author: pendingBlockItem.author
                    )
                    self.pendingBlockItem = nil
                }
            }
            Button("취소", role: .cancel) {
                pendingBlockItem = nil
            }
        }
        .alert(
            "작업을 완료하지 못했습니다.",
            isPresented: actionErrorBinding
        ) {
            Button("확인") {
                viewModel.clearActionError()
            }
        } message: {
            Text(viewModel.actionErrorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("댓글")
                .font(.headline.weight(.bold))

            Spacer()

            sortControl

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("댓글 닫기")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }

    @ViewBuilder
    private var commentsContent: some View {
        if shouldShowEmptyState {
            emptyStateSection
        } else {
            ForEach(commentFeedItems) { item in
                commentCard(item.displayItem, badges: item.badges)
                    .onAppear {
                        viewModel.prefetchAuthorAvatars(around: item.id)
                        guard item.displayItem.comment.id == viewModel.rootComments.last?.id else { return }
                        Task {
                            await viewModel.loadNextPage()
                        }
                    }
            }

            if viewModel.isLoadingMore {
                ProgressView()
                    .tint(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
    }

    private func commentCard(
        _ item: CommentDisplayItem,
        badges: [PostCommentBadge] = []
    ) -> some View {
        PostCommentCardView(
            comment: item.comment,
            author: item.author,
            badges: badges,
            onProfileTap: {
                coordinator.presentProfile(for: item.author)
            },
            onRepliesTap: {
                coordinator.presentReplies(for: item.comment)
            },
            onDeleteTap: deleteAction(for: item),
            onReportTap: reportAction(for: item),
            onBlockTap: blockAction(for: item)
        )
    }

    private func deleteAction(for item: CommentDisplayItem) -> (() -> Void)? {
        guard viewModel.canDelete(
            item.comment,
            isBrandWritable: brandAdminSessionStore.canWrite(brandID: brandID)
        ) else {
            return nil
        }

        return {
            pendingDeleteItem = item
            isConfirmingDelete = true
        }
    }

    private func reportAction(for item: CommentDisplayItem) -> (() -> Void)? {
        guard viewModel.canReportOrBlock(item.comment) else { return nil }

        return {
            pendingReportItem = item
            isSelectingReportReason = true
        }
    }

    private func blockAction(for item: CommentDisplayItem) -> (() -> Void)? {
        guard viewModel.canReportOrBlock(item.comment) else { return nil }

        return {
            pendingBlockItem = item
            isConfirmingBlock = true
        }
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.actionErrorMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    viewModel.clearActionError()
                }
            }
        )
    }

    private var replySheetBinding: Binding<Bool> {
        Binding(
            get: { coordinator.replyRoute != nil },
            set: { isPresented in
                if isPresented == false {
                    coordinator.dismissReplies()
                }
            }
        )
    }

    private var profileSheetBinding: Binding<Bool> {
        Binding(
            get: { coordinator.profileRoute != nil },
            set: { isPresented in
                if isPresented == false {
                    coordinator.dismissProfile()
                }
            }
        )
    }

    @ViewBuilder
    private var repliesSheet: some View {
        if let route = coordinator.replyRoute {
            let sheet = navigationCoordinator.makeRepliesSheet(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                parentComment: route.parentComment,
                onReplySubmitted: onCommentSubmitted,
                onCommentDeleted: onCommentDeleted
            )
            if #available(iOS 16.0, *) {
                sheet
                    .presentationDetents([.fraction(0.62)])
                    .presentationDragIndicator(.visible)
            } else {
                sheet
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var profileSheet: some View {
        if let route = coordinator.profileRoute {
            CommentUserProfileDetailView(
                author: route.author,
                onBack: {
                    coordinator.dismissProfile()
                }
            )
        } else {
            EmptyView()
        }
    }

    private var inputBar: some View {
        PostCommentInputBarView(
            text: $viewModel.draftMessage,
            placeholder: "댓글을 입력하세요.",
            isSubmitting: viewModel.isSubmittingComment,
            canSubmit: viewModel.canSubmitComment,
            errorMessage: viewModel.submissionErrorMessage,
            onSubmit: {
                if let result = await viewModel.submitComment() {
                    onCommentSubmitted(result)
                }
            }
        )
    }

    private var sortControl: some View {
        HStack(spacing: 6) {
            sortButton(.latest)
            sortButton(.popular)
        }
        .padding(4)
        .background(Color(.tertiarySystemFill))
        .clipShape(Capsule())
    }

    private func sortButton(_ sort: CommentSortOption) -> some View {
        Button {
            Task {
                await viewModel.selectSort(sort)
            }
        } label: {
            Text(sort.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(viewModel.selectedSort == sort ? .white : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(viewModel.selectedSort == sort ? Color.black : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("댓글 \(sort.title) 정렬")
    }

    private var loadingSection: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(.black)

            Text("댓글을 불러오는 중입니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var emptyStateSection: some View {
        Text("해당 포스트에 아직 댓글이 없습니다.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
            .multilineTextAlignment(.center)
    }

    private var shouldShowInitialLoading: Bool {
        viewModel.isLoading &&
            viewModel.pinnedComments.isEmpty &&
            viewModel.representativeComment == nil &&
            viewModel.rootComments.isEmpty
    }

    private var shouldShowEmptyState: Bool {
        viewModel.pinnedComments.isEmpty &&
            viewModel.representativeComment == nil &&
            viewModel.rootComments.isEmpty
    }

    private var commentFeedItems: [CommentFeedItem] {
        var items = viewModel.pinnedComments.map {
            CommentFeedItem(displayItem: viewModel.displayItem(for: $0), badges: [.pinned])
        }

        if let representativeComment = viewModel.representativeComment {
            if let pinnedIndex = items.firstIndex(where: { $0.id == representativeComment.id }) {
                items[pinnedIndex].badges.append(.representative)
            } else {
                items.append(
                    CommentFeedItem(
                        displayItem: viewModel.displayItem(for: representativeComment),
                        badges: [.representative]
                    )
                )
            }
        }

        items.append(contentsOf: viewModel.rootComments.map {
            CommentFeedItem(displayItem: viewModel.displayItem(for: $0), badges: [])
        })

        return items
    }
}

private extension CommentSortOption {
    var title: String {
        switch self {
        case .latest:
            return "최신순"
        case .popular:
            return "인기순"
        }
    }
}

private struct CommentFeedItem: Identifiable {
    let displayItem: CommentDisplayItem
    var badges: [PostCommentBadge]

    var id: CommentID {
        displayItem.id
    }
}
