//
//  SeasonDetailView.swift
//  OutPick
//
//  Created by Codex on 2/21/26.
//

import SwiftUI

struct SeasonDetailView: View {
    let brandID: BrandID
    let seasonID: SeasonID
    let onSelectPost: ((PostID) -> Void)?

    @Environment(\.repositoryProvider) private var provider
    @StateObject private var viewModel = SeasonDetailViewModel()

    init(
        brandID: BrandID,
        seasonID: SeasonID,
        onSelectPost: ((PostID) -> Void)? = nil
    ) {
        self.brandID = brandID
        self.seasonID = seasonID
        self.onSelectPost = onSelectPost
    }

    var body: some View {
        List {
            Section("Season") {
                if let season = viewModel.season {
                    InfoRow(label: "ID", value: season.id.value)
                    InfoRow(label: "Title", value: season.title)
                    InfoRow(label: "Posts", value: String(season.postCount))
                } else if viewModel.isLoading {
                    ProgressView("시즌 로딩 중...")
                } else if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                } else {
                    Text("시즌 정보를 불러오지 못했습니다.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Posts") {
                if viewModel.posts.isEmpty, viewModel.isLoading {
                    ProgressView("포스트 로딩 중...")
                } else if viewModel.posts.isEmpty {
                    Text("등록된 포스트가 없습니다.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.posts, id: \.id) { post in
                        Button {
                            onSelectPost?(post.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(post.caption ?? "(캡션 없음)")
                                        .font(.body)
                                        .lineLimit(1)
                                    Text("postID: \(post.id.value)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Season")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded(
                brandID: brandID,
                seasonID: seasonID,
                seasonRepository: provider.seasonRepository,
                postRepository: provider.postRepository
            )
        }
        .refreshable {
            await viewModel.refresh(
                brandID: brandID,
                seasonID: seasonID,
                seasonRepository: provider.seasonRepository,
                postRepository: provider.postRepository
            )
        }
    }
}

private struct InfoRow: View {
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
final class SeasonDetailViewModel: ObservableObject {
    @Published private(set) var season: Season?
    @Published private(set) var posts: [LookbookPost] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    private var loadedKey: String?
    private var isRequesting: Bool = false

    func loadIfNeeded(
        brandID: BrandID,
        seasonID: SeasonID,
        seasonRepository: any SeasonRepositoryProtocol,
        postRepository: any PostRepositoryProtocol
    ) async {
        let key = "\(brandID.value)|\(seasonID.value)"
        guard loadedKey != key else { return }
        await load(
            brandID: brandID,
            seasonID: seasonID,
            seasonRepository: seasonRepository,
            postRepository: postRepository
        )
    }

    func refresh(
        brandID: BrandID,
        seasonID: SeasonID,
        seasonRepository: any SeasonRepositoryProtocol,
        postRepository: any PostRepositoryProtocol
    ) async {
        loadedKey = nil
        await load(
            brandID: brandID,
            seasonID: seasonID,
            seasonRepository: seasonRepository,
            postRepository: postRepository
        )
    }

    private func load(
        brandID: BrandID,
        seasonID: SeasonID,
        seasonRepository: any SeasonRepositoryProtocol,
        postRepository: any PostRepositoryProtocol
    ) async {
        if isRequesting { return }
        isRequesting = true
        isLoading = true
        errorMessage = nil
        defer {
            isRequesting = false
            isLoading = false
        }

        do {
            async let seasonTask = seasonRepository.fetchSeason(brandID: brandID, seasonID: seasonID)
            async let postsTask = postRepository.fetchPosts(
                brandID: brandID,
                seasonID: seasonID,
                sort: .newest,
                filterTagIDs: [],
                page: PageRequest(size: 30, cursor: nil)
            )

            let (loadedSeason, loadedPosts) = try await (seasonTask, postsTask)
            season = loadedSeason
            posts = loadedPosts.items
            loadedKey = "\(brandID.value)|\(seasonID.value)"
        } catch {
            season = nil
            posts = []
            errorMessage = "시즌/포스트를 불러오지 못했습니다."
        }
    }
}
