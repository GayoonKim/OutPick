//
//  PostCommentRepliesSheetView.swift
//  OutPick
//
//  Created by Codex on 5/1/26.
//

import SwiftUI

struct PostCommentRepliesSheetView: View {
    @StateObject private var viewModel: PostCommentRepliesViewModel
    private let avatarImageManager: ChatAvatarImageManaging
    private let firebaseRepositories: any FirebaseRepositoryProviding
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var brandAdminSessionStore: BrandAdminSessionStore
    @State private var profileAuthor: CommentAuthorDisplay?
    @State private var pendingDeleteItem: CommentDisplayItem?
    @State private var pendingReportItem: CommentDisplayItem?
    @State private var pendingBlockItem: CommentDisplayItem?

    init(
        viewModel: PostCommentRepliesViewModel,
        avatarImageManager: ChatAvatarImageManaging,
        firebaseRepositories: any FirebaseRepositoryProviding
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.avatarImageManager = avatarImageManager
        self.firebaseRepositories = firebaseRepositories
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .background(OutPickTheme.SwiftUIColor.borderSubtle)
            parentCommentSection
            Divider()
                .background(OutPickTheme.SwiftUIColor.borderSubtle)
            repliesContent
        }
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            inputBar
        }
        .task {
            await viewModel.loadIfNeeded()
            await brandAdminSessionStore.ensureWritableBrandsLoaded()
        }
        .sheet(isPresented: profileSheetBinding) {
            profileSheet
        }
        .sheet(item: $pendingDeleteItem) { item in
            deleteConfirmationSheet(for: item)
        }
        .sheet(item: $pendingReportItem) { item in
            reportConfirmationSheet(for: item)
        }
        .sheet(item: $pendingBlockItem) { item in
            blockConfirmationSheet(for: item)
        }
        .appToast(message: activeToastMessage, bottomPadding: 92) {
            if viewModel.actionErrorMessage != nil {
                viewModel.clearActionError()
            }
            if viewModel.submissionErrorMessage != nil {
                viewModel.clearSubmissionError()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("답글")
                .font(.headline.weight(.bold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

            Spacer()

            Button {
                dismiss()
            } label: {
                LookbookNavigationIconLabel(systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("답글 닫기")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(OutPickTheme.SwiftUIColor.backgroundBase)
    }

    private var parentCommentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("원댓글")
            if viewModel.isParentCommentHidden {
                hiddenParentCommentView
            } else {
                let item = viewModel.displayItem(for: viewModel.parentComment)
                PostCommentCardView(
                    comment: item.comment,
                    likeCount: viewModel.displayLikeCount(for: item.comment),
                    replyCount: viewModel.displayReplyCount(for: item.comment),
                    isLiked: viewModel.isCommentLiked(item.comment),
                    isMutatingLike: viewModel.isMutatingLike(item.comment),
                    author: item.author,
                    badgeTitle: "원댓글",
                    avatarImageManager: avatarImageManager,
                    actions: .init(
                        onProfileTap: {
                            profileAuthor = item.author
                        },
                        onLikeTap: {
                            await viewModel.toggleLike(item.comment)
                        },
                        onDeleteTap: deleteAction(for: item),
                        onReportTap: reportAction(for: item),
                        onBlockTap: blockAction(for: item)
                    )
                )
                .onAppear {
                    viewModel.prefetchAuthorAvatars(around: item.id)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
    }

    private var hiddenParentCommentView: some View {
        Text("차단한 사용자의 댓글입니다.")
            .font(.footnote)
            .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .background(OutPickTheme.SwiftUIColor.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var repliesContent: some View {
        ScrollView(showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 14) {
                if shouldShowInitialLoading {
                    loadingSection
                } else if viewModel.replies.isEmpty {
                    emptyStateSection
                } else {
                    sectionTitle("답글")

                    ForEach(viewModel.replies) { reply in
                        let item = viewModel.displayItem(for: reply)
                        PostCommentCardView(
                            comment: item.comment,
                            likeCount: viewModel.displayLikeCount(for: item.comment),
                            replyCount: viewModel.displayReplyCount(for: item.comment),
                            isLiked: viewModel.isCommentLiked(item.comment),
                            isMutatingLike: viewModel.isMutatingLike(item.comment),
                            author: item.author,
                            avatarImageManager: avatarImageManager,
                            actions: .init(
                                onProfileTap: {
                                    profileAuthor = item.author
                                },
                                onLikeTap: {
                                    await viewModel.toggleLike(item.comment)
                                },
                                onDeleteTap: deleteAction(for: item),
                                onReportTap: reportAction(for: item),
                                onBlockTap: blockAction(for: item)
                            )
                        )
                        .task(id: item.id) {
                            viewModel.prefetchAuthorAvatars(around: item.id)
                            guard reply.id == viewModel.replies.last?.id else { return }
                            await viewModel.loadNextPage()
                        }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .tint(OutPickTheme.SwiftUIColor.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var inputBar: some View {
        PostCommentInputBarView(
            text: $viewModel.draftMessage,
            placeholder: "답글을 입력하세요.",
            isSubmitting: viewModel.isSubmittingReply,
            canSubmit: viewModel.canSubmitReply,
            submitAccessibilityLabel: "답글 등록",
            onSubmit: {
                await viewModel.submitReply()
            }
        )
    }

    private func deleteAction(for item: CommentDisplayItem) -> (() -> Void)? {
        guard viewModel.canDelete(
            item.comment,
            isBrandWritable: brandAdminSessionStore.canWrite(brandID: viewModel.currentBrandID)
        ) else {
            return nil
        }

        return {
            pendingDeleteItem = item
        }
    }

    private func reportAction(for item: CommentDisplayItem) -> (() -> Void)? {
        guard viewModel.canReportOrBlock(item.comment) else { return nil }

        return {
            pendingReportItem = item
        }
    }

    @ViewBuilder
    private func deleteConfirmationSheet(for item: CommentDisplayItem) -> some View {
        let sheet = CommentDeleteConfirmationSheetView(
            author: item.author,
            isDeleting: viewModel.isPerformingCommentAction,
            avatarImageManager: avatarImageManager,
            onCancel: {
                pendingDeleteItem = nil
            },
            onConfirm: {
                Task {
                    if await viewModel.deleteComment(item.comment) != nil {
                        if item.comment.id == viewModel.parentComment.id {
                            dismiss()
                        }
                    }
                    pendingDeleteItem = nil
                }
            }
        )
        if #available(iOS 16.0, *) {
            sheet
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.hidden)
        } else {
            sheet
        }
    }

    @ViewBuilder
    private func reportConfirmationSheet(for item: CommentDisplayItem) -> some View {
        let sheet = CommentReportSheetView(
            author: item.author,
            isReporting: viewModel.isPerformingCommentAction,
            avatarImageManager: avatarImageManager,
            onCancel: {
                pendingReportItem = nil
            },
            onSubmit: { reason, detail in
                Task {
                    await viewModel.reportComment(
                        item.comment,
                        author: item.author,
                        reason: reason,
                        detail: detail
                    )
                    pendingReportItem = nil
                }
            }
        )
        if #available(iOS 16.0, *) {
            sheet
                .presentationDetents([.height(520)])
                .presentationDragIndicator(.hidden)
        } else {
            sheet
        }
    }

    private func blockAction(for item: CommentDisplayItem) -> (() -> Void)? {
        guard viewModel.canReportOrBlock(item.comment) else { return nil }

        return {
            pendingBlockItem = item
        }
    }

    @ViewBuilder
    private func blockConfirmationSheet(for item: CommentDisplayItem) -> some View {
        let sheet = CommentBlockConfirmationSheetView(
            author: item.author,
            isBlocking: viewModel.isPerformingCommentAction,
            avatarImageManager: avatarImageManager,
            onCancel: {
                pendingBlockItem = nil
            },
            onConfirm: {
                Task {
                    await viewModel.blockAuthor(
                        of: item.comment,
                        author: item.author
                    )
                    if item.comment.id == viewModel.parentComment.id {
                        dismiss()
                    }
                    pendingBlockItem = nil
                }
            }
        )
        if #available(iOS 16.0, *) {
            sheet
                .presentationDetents([.height(390)])
                .presentationDragIndicator(.hidden)
        } else {
            sheet
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
    }

    private var loadingSection: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(OutPickTheme.SwiftUIColor.accent)

            Text("답글을 불러오는 중입니다.")
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private var emptyStateSection: some View {
        Text("아직 답글이 없습니다.")
            .font(.footnote)
            .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            .multilineTextAlignment(.center)
    }

    private var shouldShowInitialLoading: Bool {
        viewModel.isLoading && viewModel.replies.isEmpty
    }

    private var activeToastMessage: String? {
        viewModel.actionErrorMessage ?? viewModel.submissionErrorMessage
    }

    private var profileSheetBinding: Binding<Bool> {
        Binding(
            get: { profileAuthor != nil },
            set: { isPresented in
                if isPresented == false {
                    profileAuthor = nil
                }
            }
        )
    }

    @ViewBuilder
    private var profileSheet: some View {
        if let profileAuthor {
            CommentUserProfileDetailView(
                author: profileAuthor,
                avatarImageManager: avatarImageManager,
                repositories: firebaseRepositories,
                onBack: {
                    self.profileAuthor = nil
                }
            )
        } else {
            EmptyView()
        }
    }
}
