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

    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView("포스트 로딩 중...")
            } else if let post = viewModel.post {
                Section("Post") {
                    PostInfoRow(label: "Post ID", value: post.id.value)
                    PostInfoRow(label: "Brand ID", value: post.brandID.value)
                    PostInfoRow(label: "Season ID", value: post.seasonID.value)
                    PostInfoRow(label: "Media Count", value: String(post.media.count))
                    PostInfoRow(label: "Tag Count", value: String(post.tagIDs.count))
                    if let caption = post.caption, !caption.isEmpty {
                        Text(caption)
                    }
                }
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.secondary)
            } else {
                Text("포스트를 찾을 수 없습니다.")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                postRepository: provider.postRepository
            )
        }
    }
}

private struct PostInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
final class PostDetailScreenViewModel: ObservableObject {
    @Published private(set) var post: LookbookPost?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    private var loadedKey: String?
    private var isRequesting = false

    func loadIfNeeded(
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        postRepository: any PostRepositoryProtocol
    ) async {
        let key = "\(brandID.value)|\(seasonID.value)|\(postID.value)"
        guard loadedKey != key else { return }
        if isRequesting { return }
        isRequesting = true
        isLoading = true
        errorMessage = nil
        defer {
            isRequesting = false
            isLoading = false
        }

        do {
            let loadedPost = try await postRepository.fetchPost(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID
            )
            post = loadedPost
            loadedKey = key
        } catch {
            post = nil
            errorMessage = "포스트를 불러오지 못했습니다."
        }
    }
}
