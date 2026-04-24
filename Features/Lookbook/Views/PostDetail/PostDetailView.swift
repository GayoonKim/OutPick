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

    @Environment(\.repositoryProvider) private var provider
    @StateObject private var viewModel = PostDetailScreenViewModel()
    @State private var heroImageDidResolve: Bool = false

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
                            PostDetailMetricsCardView(post: post)
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
        .onAppear {
            heroImageDidResolve = heroAssetKey == nil
        }
        .onChange(of: heroAssetKey) { newValue in
            heroImageDidResolve = newValue == nil
        }
        .task {
            await viewModel.loadIfNeeded(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                useCase: loadPostDetailUseCase
            )
        }
        .refreshable {
            await viewModel.refresh(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                useCase: loadPostDetailUseCase
            )
        }
    }

    private var loadPostDetailUseCase: some LoadPostDetailUseCaseProtocol {
        LoadPostDetailUseCase(
            postRepository: provider.postRepository,
            commentRepository: provider.commentRepository
        )
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
                primaryPath: firstMedia.preferredDetailPath,
                secondaryPath: firstMedia.preferredListPath,
                remoteURL: firstMedia.remoteURL,
                sourcePageURL: firstMedia.sourcePageURL,
                brandImageCache: provider.brandImageCache,
                maxBytes: 3_000_000,
                onLoadCompleted: { _ in
                    heroImageDidResolve = true
                }
            )
            .frame(height: 520)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("댓글")
                    .font(.title3.weight(.bold))
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.85)
                        .tint(.black)
                }
            }

            if viewModel.comments.isEmpty {
                Text("아직 댓글이 없습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let commentErrorMessage = viewModel.commentErrorMessage {
                Text(commentErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.comments) { comment in
                        PostCommentCardView(comment: comment)
                    }
                }
            }
        }
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
