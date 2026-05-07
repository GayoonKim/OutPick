//
//  PostCommentRepliesSheetView.swift
//  OutPick
//
//  Created by Codex on 5/1/26.
//

import SwiftUI

struct PostCommentRepliesSheetView: View {
    @StateObject private var viewModel: PostCommentRepliesViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var brandAdminSessionStore: BrandAdminSessionStore
    @State private var profileAuthor: CommentAuthorDisplay?
    @State private var pendingDeleteItem: CommentDisplayItem?
    @State private var pendingReportItem: CommentDisplayItem?
    @State private var pendingBlockItem: CommentDisplayItem?
    @State private var isConfirmingDelete: Bool = false
    @State private var isSelectingReportReason: Bool = false
    @State private var isConfirmingBlock: Bool = false
    private let onReplySubmitted: (CommentMutationResult) -> Void
    private let onCommentDeleted: (CommentDeletionResult) -> Void

    init(
        viewModel: PostCommentRepliesViewModel,
        onReplySubmitted: @escaping (CommentMutationResult) -> Void = { _ in },
        onCommentDeleted: @escaping (CommentDeletionResult) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onReplySubmitted = onReplySubmitted
        self.onCommentDeleted = onCommentDeleted
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            parentCommentSection
            Divider()
            repliesContent
        }
        .background(Color(red: 0.98, green: 0.97, blue: 0.95).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            inputBar
        }
        .task {
            await viewModel.loadIfNeeded()
            await brandAdminSessionStore.refreshWritableBrands()
        }
        .sheet(isPresented: profileSheetBinding) {
            profileSheet
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
                        if pendingDeleteItem.comment.id == viewModel.parentComment.id {
                            dismiss()
                        }
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
                    if pendingBlockItem.comment.id == viewModel.parentComment.id {
                        dismiss()
                    }
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
            Text("답글")
                .font(.headline.weight(.bold))

            Spacer()

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
            .accessibilityLabel("답글 닫기")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }

    private var parentCommentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("원댓글")
            let item = viewModel.displayItem(for: viewModel.parentComment)
            PostCommentCardView(
                comment: item.comment,
                author: item.author,
                badgeTitle: "원댓글",
                onProfileTap: {
                    profileAuthor = item.author
                },
                onDeleteTap: deleteAction(for: item),
                onReportTap: reportAction(for: item),
                onBlockTap: blockAction(for: item)
            )
            .onAppear {
                viewModel.prefetchAuthorAvatars(around: item.id)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.72))
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
                            author: item.author,
                            onProfileTap: {
                                profileAuthor = item.author
                            },
                            onDeleteTap: deleteAction(for: item),
                            onReportTap: reportAction(for: item),
                            onBlockTap: blockAction(for: item)
                        )
                            .onAppear {
                                viewModel.prefetchAuthorAvatars(around: item.id)
                                guard reply.id == viewModel.replies.last?.id else { return }
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
            errorMessage: viewModel.submissionErrorMessage,
            submitAccessibilityLabel: "답글 등록",
            onSubmit: {
                if let result = await viewModel.submitReply() {
                    onReplySubmitted(result)
                }
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

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.primary)
    }

    private var loadingSection: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(.black)

            Text("답글을 불러오는 중입니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private var emptyStateSection: some View {
        Text("아직 답글이 없습니다.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            .multilineTextAlignment(.center)
    }

    private var shouldShowInitialLoading: Bool {
        viewModel.isLoading && viewModel.replies.isEmpty
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
                onBack: {
                    self.profileAuthor = nil
                }
            )
        } else {
            EmptyView()
        }
    }
}
