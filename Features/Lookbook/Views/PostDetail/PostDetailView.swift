//
//  PostDetailView.swift
//  OutPick
//
//  Created by Codex on 2/21/26.
//

import SwiftUI
import UIKit

struct PostDetailView: View {
    let brandID: BrandID
    let seasonID: SeasonID
    let postID: PostID

    @Environment(\.repositoryProvider) private var provider
    @StateObject private var viewModel = PostDetailScreenViewModel()
    @StateObject private var commentCoordinator = PostCommentCoordinator()
    @State private var heroImageDidResolve: Bool = false
    @State private var isPresentingImagePreview: Bool = false
    @State private var profileAuthor: CommentAuthorDisplay?

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
                                isLiked: viewModel.postUserState?.isLiked ?? false,
                                isSaved: viewModel.postUserState?.isSaved ?? false,
                                errorMessage: viewModel.engagementErrorMessage,
                                onLikeTap: {
                                    Task {
                                        await viewModel.toggleLike(
                                            brandID: brandID,
                                            seasonID: seasonID,
                                            postID: postID,
                                            repository: provider.postEngagementRepository
                                        )
                                    }
                                },
                                onCommentTap: {
                                    commentCoordinator.presentComments()
                                },
                                onSaveTap: {
                                    Task {
                                        await viewModel.toggleSave(
                                            brandID: brandID,
                                            seasonID: seasonID,
                                            postID: postID,
                                            repository: provider.postEngagementRepository
                                        )
                                    }
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
            await viewModel.loadIfNeeded(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                useCase: loadPostDetailUseCase,
                postUserStateRepository: provider.postUserStateRepository
            )
        }
        .refreshable {
            await viewModel.refresh(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                useCase: loadPostDetailUseCase,
                postUserStateRepository: provider.postUserStateRepository
            )
        }
        .sheet(isPresented: profileSheetBinding) {
            profileSheet
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

    private var loadPostDetailUseCase: some LoadPostDetailUseCaseProtocol {
        LoadPostDetailUseCase(
            postRepository: provider.postRepository,
            commentRepository: provider.commentRepository
        )
    }

    private func makePostCommentsViewModel() -> PostCommentsViewModel {
        PostCommentsViewModel(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            useCase: LoadPostCommentsUseCase(
                commentRepository: provider.commentRepository
            ),
            createUseCase: CreatePostCommentUseCase(
                repository: provider.commentWritingRepository
            )
        )
    }

    private func makePostCommentRepliesViewModel(
        parentComment: Comment
    ) -> PostCommentRepliesViewModel {
        PostCommentRepliesViewModel(
            brandID: brandID,
            seasonID: seasonID,
            postID: postID,
            parentComment: parentComment,
            useCase: LoadCommentRepliesUseCase(
                commentRepository: provider.commentRepository
            ),
            createUseCase: CreateCommentReplyUseCase(
                repository: provider.commentWritingRepository
            )
        )
    }

    @ViewBuilder
    private var commentsSheet: some View {
        let sheet = PostCommentsSheetView(
            viewModel: makePostCommentsViewModel(),
            coordinator: commentCoordinator,
            repliesViewModelFactory: makePostCommentRepliesViewModel(parentComment:),
            onCommentSubmitted: { result in
                viewModel.applyCommentMutation(result)
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
                brandImageCache: provider.brandImageCache,
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
                    brandImageCache: provider.brandImageCache
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
                    commentCoordinator.presentComments()
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
                            onProfileTap: {
                                profileAuthor = item.author
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

private struct PostImagePreviewView: View {
    let previewPath: String?
    let originalPath: String?
    let remoteURL: URL?
    let sourcePageURL: URL?
    let brandImageCache: any BrandImageCacheProtocol

    @Environment(\.dismiss) private var dismiss

    @State private var uiImage: UIImage?
    @State private var isLoadingPreview: Bool = false
    @State private var isLoadingOriginal: Bool = false
    @State private var didFail: Bool = false
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    private let previewMaxBytes = 1_500_000
    private let originalMaxBytes = 12_000_000
    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            imageContent

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.48))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.trailing, 18)
        }
        .task(id: loadKey) {
            await loadPreviewThenOriginal()
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let uiImage {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .simultaneousGesture(magnificationGesture)
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if scale > 1 {
                            scale = 1
                            baseScale = 1
                            offset = .zero
                            baseOffset = .zero
                        } else {
                            scale = 2
                            baseScale = 2
                        }
                    }
                }
        } else if isLoadingPreview || isLoadingOriginal {
            ProgressView()
                .tint(.white)
        } else {
            Image(systemName: didFail ? "exclamationmark.triangle" : "photo")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                baseOffset = offset
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let nextScale = min(max(baseScale * value, minScale), maxScale)
                scale = nextScale
                if nextScale <= minScale {
                    offset = .zero
                    baseOffset = .zero
                }
            }
            .onEnded { _ in
                baseScale = scale
            }
    }

    private var loadKey: String {
        [
            previewPath,
            originalPath,
            remoteURL?.absoluteString,
            sourcePageURL?.absoluteString
        ]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    private func loadPreviewThenOriginal() async {
        uiImage = nil
        didFail = false

        if let preview = await loadPreviewImage() {
            uiImage = preview
        }

        if let original = await loadOriginalImage() {
            uiImage = original
            didFail = false
            return
        }

        didFail = uiImage == nil
    }

    private func loadPreviewImage() async -> UIImage? {
        guard let previewPath = normalized(previewPath) else { return nil }

        isLoadingPreview = true
        defer { isLoadingPreview = false }

        return try? await brandImageCache.loadImage(
            path: previewPath,
            maxBytes: previewMaxBytes
        )
    }

    private func loadOriginalImage() async -> UIImage? {
        isLoadingOriginal = true
        defer { isLoadingOriginal = false }

        if let originalPath = normalized(originalPath),
           originalPath != normalized(previewPath),
           let image = try? await brandImageCache.loadImage(
            path: originalPath,
            maxBytes: originalMaxBytes
           ) {
            return image
        }

        return await loadRemoteOriginalImage()
    }

    private func loadRemoteOriginalImage() async -> UIImage? {
        guard let remoteURL else { return nil }

        var request = URLRequest(url: remoteURL)
        request.setValue(
            "OutPick/1.0 (iOS; lookbook original preview)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let sourcePageURL {
            request.setValue(
                sourcePageURL.absoluteString,
                forHTTPHeaderField: "Referer"
            )
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                data.count <= originalMaxBytes,
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode)
            else {
                return nil
            }

            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    private func normalized(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
