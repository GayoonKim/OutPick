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
    private let coordinator: LookbookCoordinator

    @StateObject private var viewModel: PostDetailScreenViewModel
    @StateObject private var commentCoordinator: PostCommentCoordinator
    @State private var heroImageDidResolve: Bool = false
    @State private var isPresentingImagePreview: Bool = false

    init(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        viewModel: PostDetailScreenViewModel,
        coordinator: LookbookCoordinator,
        commentCoordinator: PostCommentCoordinator,
        brandImageCache: any BrandImageCacheProtocol
    ) {
        self.brandID = brandID
        self.seasonID = seasonID
        self.postID = postID
        self.coordinator = coordinator
        self.brandImageCache = brandImageCache
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
                                isSaved: viewModel.postUserState?.isSaved ?? false,
                                errorMessage: viewModel.engagementErrorMessage,
                                onLikeTap: {
                                    await viewModel.toggleLike()
                                },
                                onCommentTap: {
                                    coordinator.presentComments(using: commentCoordinator)
                                },
                                onSaveTap: {
                                    await viewModel.toggleSave()
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
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.99, green: 0.98, blue: 0.96),
                    Color.white
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: commentSheetBinding) {
            commentsSheet
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
    }

    private var commentSheetBinding: Binding<Bool> {
        Binding(
            get: { commentCoordinator.isCommentSheetPresented },
            set: { isPresented in
                if isPresented {
                    coordinator.presentComments(using: commentCoordinator)
                } else {
                    coordinator.dismissComments(using: commentCoordinator)
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
            commentCoordinator: commentCoordinator,
            onCommentSubmitted: { result in
                _ = result
            },
            onCommentDeleted: { result in
                viewModel.removeCommentFromPreview(result.commentID)
            }
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
                .tint(.black)
            Text("포스트를 준비하는 중입니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorSection(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("포스트를 불러오지 못했습니다.")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.94))
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
                Spacer()
                Button {
                    coordinator.presentComments(using: commentCoordinator)
                } label: {
                    Text("더 보기")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }

            if viewModel.comments.isEmpty {
                emptyCommentSection
            } else if let commentErrorMessage = viewModel.commentErrorMessage {
                Text(commentErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.comments) { comment in
                        let item = viewModel.displayItem(for: comment)
                        PostCommentCardView(
                            comment: item.comment,
                            author: item.author,
                            badge: .representative,
                            onCardTap: {
                                coordinator.presentComments(using: commentCoordinator)
                            }
                        )
                        .onAppear {
                            viewModel.prefetchAuthorAvatars(for: viewModel.comments)
                        }
                    }
                }
            }
        }
    }

    private var emptyCommentSection: some View {
        Text("해당 포스트에 아직 댓글이 없습니다.")
            .font(.footnote)
            .foregroundStyle(.secondary)
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
