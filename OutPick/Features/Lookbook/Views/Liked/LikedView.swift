//
//  LikedView.swift
//  OutPick
//
//  Created by Codex on 5/26/26.
//

import SwiftUI

struct LikedView: View {
    @StateObject private var viewModel: LikedViewModel

    private let coordinator: LookbookCoordinator
    private let postColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    init(
        viewModel: LikedViewModel,
        coordinator: LookbookCoordinator
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.coordinator = coordinator
    }

    var body: some View {
        content
            .lookbookNavigationBar(title: "OutPick")
            .task {
                await viewModel.refreshForActivation()
            }
            .refreshable {
                await viewModel.reload()
            }
            .appToast(message: viewModel.engagementErrorMessage) {
                viewModel.clearEngagementError()
            }
            .tint(OutPickTheme.SwiftUIColor.accent)
    }

    private var likedSectionsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                likedBrandSection
                likedSeasonSection
                likedPostSection
            }
            .padding(.vertical, 18)
        }
        .background(OutPickTheme.SwiftUIColor.backgroundBase)
    }

    @ViewBuilder
    private var likedBrandSection: some View {
        LikedContentSectionHeader(title: "좋아요 브랜드", count: viewModel.brandItems.count)
            .padding(.horizontal, 20)

        switch viewModel.brandSection.phase {
        case .idle, .loading:
            if viewModel.brandItems.isEmpty {
                LikedSectionStatusRow(text: "좋아요한 브랜드를 불러오는 중...", showsProgress: true)
                    .padding(.horizontal, 20)
            } else {
                likedBrandCards
            }

        case .empty:
            LikedSectionStatusRow(text: "좋아요한 브랜드가 없습니다.")
                .padding(.horizontal, 20)

        case .failed(let message):
            LikedSectionStatusRow(text: message)
                .padding(.horizontal, 20)

        case .ready:
            likedBrandCards
        }
    }

    @ViewBuilder
    private var likedSeasonSection: some View {
        LikedContentSectionHeader(title: "좋아요 시즌", count: viewModel.seasonItems.count)
            .padding(.horizontal, 20)

        switch viewModel.seasonSection.phase {
        case .idle, .loading:
            if viewModel.seasonItems.isEmpty {
                LikedSectionStatusRow(text: "좋아요한 시즌을 불러오는 중...", showsProgress: true)
                    .padding(.horizontal, 20)
            } else {
                likedSeasonCards
            }

        case .empty:
            LikedSectionStatusRow(text: "좋아요한 시즌이 없습니다.")
                .padding(.horizontal, 20)

        case .failed(let message):
            LikedSectionStatusRow(text: message)
                .padding(.horizontal, 20)

        case .ready:
            likedSeasonCards
        }
    }

    @ViewBuilder
    private var likedPostSection: some View {
        LikedContentSectionHeader(title: "좋아요 포스트", count: viewModel.postItems.count)
            .padding(.horizontal, 20)

        switch viewModel.postSection.phase {
        case .idle, .loading:
            if viewModel.postItems.isEmpty {
                LikedSectionStatusRow(text: "좋아요한 포스트를 불러오는 중...", showsProgress: true)
                    .padding(.horizontal, 20)
            } else {
                likedPostGrid
            }

        case .empty:
            LikedSectionStatusRow(text: "좋아요한 포스트가 없습니다.")
                .padding(.horizontal, 20)

        case .failed(let message):
            LikedSectionStatusRow(text: message)
                .padding(.horizontal, 20)

        case .ready:
            likedPostGrid
        }
    }

    private var likedBrandCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(viewModel.brandItems) { item in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            coordinator.pushBrandDetail(brand: item.brand)
                        } label: {
                            LikedBrandCardView(
                                item: item,
                                brandImageCache: viewModel.brandImageCache
                            )
                        }
                        .buttonStyle(.plain)

                        unlikeMenu {
                            await viewModel.unlikeBrand(item)
                        }
                    }
                    .onAppear {
                        Task {
                            await viewModel.loadNextBrandPageIfNeeded(current: item)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
    }

    private var likedSeasonCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(viewModel.seasonItems) { item in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            coordinator.pushSeasonDetail(season: item.season)
                        } label: {
                            LikedSeasonCardView(
                                item: item,
                                brandImageCache: viewModel.brandImageCache
                            )
                        }
                        .buttonStyle(.plain)

                        unlikeMenu {
                            await viewModel.unlikeSeason(item)
                        }
                    }
                    .onAppear {
                        Task {
                            await viewModel.loadNextSeasonPageIfNeeded(current: item)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
    }

    private var likedPostGrid: some View {
        LazyVGrid(columns: postColumns, spacing: 10) {
            ForEach(viewModel.postItems) { item in
                ZStack(alignment: .topTrailing) {
                    Button {
                        coordinator.pushPostDetail(post: item.post)
                    } label: {
                        LikedPostCardView(
                            item: item,
                            brandImageCache: viewModel.brandImageCache
                        )
                    }
                    .buttonStyle(.plain)

                    unlikeMenu {
                        await viewModel.unlikePost(item)
                    }
                }
                .onAppear {
                    Task {
                        await viewModel.loadNextPostPageIfNeeded(current: item)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func unlikeMenu(action: @escaping () async -> Void) -> some View {
        Menu {
            Button(role: .destructive) {
                Task { await action() }
            } label: {
                Label("좋아요 취소", systemImage: "heart.slash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.bold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                .frame(width: 30, height: 30)
                .background(OutPickTheme.SwiftUIColor.surfaceElevated)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .padding(6)
        .accessibilityLabel("좋아요 메뉴")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle, .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .tint(OutPickTheme.SwiftUIColor.accent)
                Text("로딩 중...")
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OutPickTheme.SwiftUIColor.backgroundBase)

        case .empty:
            likedSectionsList

        case .failed(let message):
            VStack(spacing: 12) {
                Text("불러오기 실패")
                    .font(.headline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                Button("다시 시도") {
                    Task { await viewModel.reload() }
                }
                .tint(OutPickTheme.SwiftUIColor.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .background(OutPickTheme.SwiftUIColor.backgroundBase)

        case .ready:
            likedSectionsList
        }
    }
}

private struct LikedContentSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
            Text("\(count)")
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
    }
}

private struct LikedSectionStatusRow: View {
    let text: String
    var showsProgress = false

    var body: some View {
        HStack(spacing: 8) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(OutPickTheme.SwiftUIColor.accent)
            }
            Text(text)
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}
