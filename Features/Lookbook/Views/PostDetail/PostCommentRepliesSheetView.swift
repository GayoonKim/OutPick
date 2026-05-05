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
    @State private var profileAuthor: CommentAuthorDisplay?
    private let onReplySubmitted: (CommentMutationResult) -> Void

    init(
        viewModel: PostCommentRepliesViewModel,
        onReplySubmitted: @escaping (CommentMutationResult) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onReplySubmitted = onReplySubmitted
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
        }
        .sheet(isPresented: profileSheetBinding) {
            profileSheet
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
                }
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
                            }
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
