//
//  PostDetailView.swift
//  OutPick
//
//  Created by Codex on 2/21/26.
//

import SwiftUI

struct PostDetailView: View {
    let brandID: BrandID
    let seasonID: SeasonID
    let postID: PostID

    private let brandImageCache: any BrandImageCacheProtocol
    private let avatarImageManager: AvatarImageManaging
    private let coordinator: LookbookCoordinator
    private let shareSheetFactory: (LookbookShareTarget, @escaping (LookbookChatShareViewModel.Completion) -> Void) -> AnyView
    private let onShareMove: (LookbookChatShareViewModel.Completion) async throws -> Void

    @StateObject private var viewModel: PostDetailScreenViewModel
    @StateObject private var commentCoordinator: PostCommentCoordinator
    @State private var heroImageDidResolve: Bool = false
    @State private var isPresentingImagePreview: Bool = false
    @State private var activeShareTarget: LookbookShareTarget?
    @State private var shareCompletion: LookbookChatShareViewModel.Completion?
    @State private var shareMoveErrorMessage: String?

    init(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        viewModel: PostDetailScreenViewModel,
        coordinator: LookbookCoordinator,
        commentCoordinator: PostCommentCoordinator,
        brandImageCache: any BrandImageCacheProtocol,
        avatarImageManager: AvatarImageManaging,
        shareSheetFactory: @escaping (LookbookShareTarget, @escaping (LookbookChatShareViewModel.Completion) -> Void) -> AnyView,
        onShareMove: @escaping (LookbookChatShareViewModel.Completion) async throws -> Void
    ) {
        self.brandID = brandID
        self.seasonID = seasonID
        self.postID = postID
        self.coordinator = coordinator
        self.brandImageCache = brandImageCache
        self.avatarImageManager = avatarImageManager
        self.shareSheetFactory = shareSheetFactory
        self.onShareMove = onShareMove
        _viewModel = StateObject(wrappedValue: viewModel)
        _commentCoordinator = StateObject(wrappedValue: commentCoordinator)
    }

    var body: some View {
        ZStack {
            if let errorMessage = viewModel.errorMessage, viewModel.post == nil {
                errorSection(message: errorMessage)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        if let post = viewModel.post {
                            heroImageSection(post: post)
                            PostDetailMetricsCardView(
                                post: post,
                                commentCount: viewModel.visibleCommentCount ?? post.metrics.commentCount,
                                isLiked: viewModel.postUserState?.isLiked ?? false,
                                isMutatingLike: viewModel.isMutatingLike,
                                onLikeTap: {
                                    await viewModel.toggleLike()
                                },
                                onCommentTap: {
                                    commentCoordinator.presentComments()
                                },
                                onShareTap: {
                                    activeShareTarget = .post(post)
                                }
                            )
                            commentSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .opacity(shouldBlockContentWithLoading ? 0 : 1)

                if shouldBlockContentWithLoading {
                    loadingSection
                }
            }
        }
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
        .lookbookNavigationBar(
            title: "",
            showsBackButton: true,
            onBack: { coordinator.pop() }
        )
        .sheet(isPresented: commentSheetBinding) {
            commentsSheet
        }
        .sheet(item: $activeShareTarget) { target in
            shareSheetFactory(target) { completion in
                activeShareTarget = nil
                shareCompletion = completion
            }
            .applyShareSheetPresentation()
        }
        .sheet(item: $shareCompletion) { completion in
            LookbookShareConfirmationBar(
                roomName: completion.roomName,
                onMove: {
                    moveToSharedChatRoom(completion)
                },
                onClose: {
                    self.shareCompletion = nil
                }
            )
            .applyShareConfirmationSheetPresentation()
        }
        .onAppear {
            heroImageDidResolve = heroAssetKey == nil
        }
        .onChange(of: heroAssetKey) { newValue in
            heroImageDidResolve = newValue == nil
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .appToast(message: viewModel.engagementErrorMessage) {
            viewModel.clearEngagementError()
        }
        .appToast(message: shareMoveErrorMessage) {
            shareMoveErrorMessage = nil
        }
    }

    private func moveToSharedChatRoom(_ completion: LookbookChatShareViewModel.Completion) {
        Task {
            do {
                try await onShareMove(completion)
                shareCompletion = nil
            } catch {
                shareMoveErrorMessage = "채팅방으로 이동할 수 없습니다."
            }
        }
    }

    private var commentSheetBinding: Binding<Bool> {
        Binding(
            get: { commentCoordinator.isCommentSheetPresented },
            set: { isPresented in
                if isPresented {
                    commentCoordinator.presentComments()
                } else {
                    commentCoordinator.dismissComments()
                }
            }
        )
    }

    @ViewBuilder
    private var commentsSheet: some View {
        let sheet = coordinator.makeCommentsSheet(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            commentCoordinator: commentCoordinator
        )
        if #available(iOS 16.0, *) {
            sheet
                .presentationDetents([.fraction(0.70)])
                .presentationDragIndicator(.visible)
        } else {
            sheet
        }
    }

    private var loadingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(OutPickTheme.SwiftUIColor.accent)
            Text("포스트를 준비하는 중입니다.")
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorSection(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("포스트를 불러오지 못했습니다.")
                .font(.headline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func heroImageSection(post: LookbookPost) -> some View {
        if let firstMedia = post.media.first {
            LookbookAssetImageView(
                primaryPath: firstMedia.preferredListPath,
                secondaryPath: firstMedia.preferredDetailPath,
                remoteURL: firstMedia.remoteURL,
                sourcePageURL: firstMedia.sourcePageURL,
                brandImageCache: brandImageCache,
                maxBytes: 1_500_000,
                onLoadCompleted: { _ in
                    heroImageDidResolve = true
                }
            )
            .frame(height: 520)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                isPresentingImagePreview = true
            }
            .fullScreenCover(isPresented: $isPresentingImagePreview) {
                PostImagePreviewView(
                    previewPath: firstMedia.preferredListPath,
                    originalPath: firstMedia.preferredDetailPath,
                    remoteURL: firstMedia.remoteURL,
                    sourcePageURL: firstMedia.sourcePageURL,
                    brandImageCache: brandImageCache
                )
            }
        }
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("댓글")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                Spacer()
                Button {
                    commentCoordinator.presentComments()
                } label: {
                    Text("더 보기")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
                }
                .buttonStyle(.plain)
            }

            if viewModel.comments.isEmpty {
                emptyCommentSection
            } else if let commentErrorMessage = viewModel.commentErrorMessage {
                Text(commentErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.comments) { comment in
                        let item = viewModel.displayItem(for: comment)
                        PostCommentCardView(
                            comment: item.comment,
                            likeCount: viewModel.displayLikeCount(for: item.comment),
                            replyCount: viewModel.displayReplyCount(for: item.comment),
                            author: item.author,
                            badge: .representative,
                            avatarImageManager: avatarImageManager,
                            actions: .init(
                                onCardTap: {
                                    commentCoordinator.presentComments()
                                }
                            )
                        )
                        .onAppear {
                            viewModel.prefetchAuthorAvatars(
                                for: viewModel.comments,
                                avatarImageManager: avatarImageManager
                            )
                        }
                    }
                }
            }
        }
    }

    private var emptyCommentSection: some View {
        Text("해당 포스트에 아직 댓글이 없습니다.")
            .font(.footnote)
            .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
            .multilineTextAlignment(.center)
    }

    private var heroAssetKey: String? {
        guard let firstMedia = viewModel.post?.media.first else {
            return nil
        }

        return [
            firstMedia.preferredDetailPath,
            firstMedia.preferredListPath,
            firstMedia.remoteURL.absoluteString
        ]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    private var shouldBlockContentWithLoading: Bool {
        if viewModel.isLoading && viewModel.post == nil {
            return true
        }

        guard viewModel.post != nil else {
            return false
        }

        return heroImageDidResolve == false
    }
}
