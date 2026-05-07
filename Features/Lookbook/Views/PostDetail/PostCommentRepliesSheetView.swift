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
    @State private var isPresentingReportSheet: Bool = false
    @State private var isPresentingBlockSheet: Bool = false
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
        .sheet(isPresented: reportSheetBinding) {
            reportConfirmationSheet
        }
        .sheet(isPresented: blockSheetBinding) {
            blockConfirmationSheet
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
            if viewModel.isParentCommentHidden {
                hiddenParentCommentView
            } else {
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.72))
    }

    private var hiddenParentCommentView: some View {
        Text("차단한 사용자의 댓글입니다.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .background(Color.white.opacity(0.94))
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
            isPresentingReportSheet = true
        }
    }

    private var reportSheetBinding: Binding<Bool> {
        Binding(
            get: { isPresentingReportSheet && pendingReportItem != nil },
            set: { isPresented in
                isPresentingReportSheet = isPresented
                if isPresented == false {
                    pendingReportItem = nil
                }
            }
        )
    }

    @ViewBuilder
    private var reportConfirmationSheet: some View {
        if let pendingReportItem {
            let sheet = CommentReportSheetView(
                author: pendingReportItem.author,
                isReporting: viewModel.isPerformingCommentAction,
                onCancel: {
                    isPresentingReportSheet = false
                    self.pendingReportItem = nil
                },
                onSubmit: { reason, detail in
                    Task {
                        await viewModel.reportComment(
                            pendingReportItem.comment,
                            author: pendingReportItem.author,
                            reason: reason,
                            detail: detail
                        )
                        isPresentingReportSheet = false
                        self.pendingReportItem = nil
                    }
                }
            )
            if #available(iOS 16.0, *) {
                sheet
                    .presentationDetents([.height(520)])
                    .presentationDragIndicator(.visible)
            } else {
                sheet
            }
        } else {
            EmptyView()
        }
    }

    private func blockAction(for item: CommentDisplayItem) -> (() -> Void)? {
        guard viewModel.canReportOrBlock(item.comment) else { return nil }

        return {
            pendingBlockItem = item
            isPresentingBlockSheet = true
        }
    }

    private var blockSheetBinding: Binding<Bool> {
        Binding(
            get: { isPresentingBlockSheet && pendingBlockItem != nil },
            set: { isPresented in
                isPresentingBlockSheet = isPresented
                if isPresented == false {
                    pendingBlockItem = nil
                }
            }
        )
    }

    @ViewBuilder
    private var blockConfirmationSheet: some View {
        if let pendingBlockItem {
            let sheet = CommentBlockConfirmationSheetView(
                author: pendingBlockItem.author,
                isBlocking: viewModel.isPerformingCommentAction,
                onCancel: {
                    isPresentingBlockSheet = false
                    self.pendingBlockItem = nil
                },
                onConfirm: {
                    Task {
                        await viewModel.blockAuthor(
                            of: pendingBlockItem.comment,
                            author: pendingBlockItem.author
                        )
                        isPresentingBlockSheet = false
                        if pendingBlockItem.comment.id == viewModel.parentComment.id {
                            dismiss()
                        }
                        self.pendingBlockItem = nil
                    }
                }
            )
            if #available(iOS 16.0, *) {
                sheet
                    .presentationDetents([.height(360)])
                    .presentationDragIndicator(.visible)
            } else {
                sheet
            }
        } else {
            EmptyView()
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
