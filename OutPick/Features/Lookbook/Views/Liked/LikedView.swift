//
//  LikedView.swift
//  OutPick
//
//  Created by Codex on 5/26/26.
//

import Foundation
import SwiftUI

struct LikedView: View {
    @StateObject private var viewModel: LikedViewModel

    private let coordinator: LookbookCoordinator
    private let postColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
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
            LazyVStack(alignment: .leading, spacing: 36) {
                LikedEditorialHeader()
                    .padding(.horizontal, 20)

                likedBrandSection
                likedSeasonSection
                likedPostSection
            }
            .padding(.top, 28)
            .padding(.bottom, 36)
        }
        .background(OutPickTheme.SwiftUIColor.backgroundBase)
    }

    @ViewBuilder
    private var likedBrandSection: some View {
        LikedEditorialSectionHeader(
            eyebrow: "BRAND INDEX",
            title: "브랜드",
            count: viewModel.brandItems.count
        )
            .padding(.horizontal, 20)

        switch viewModel.brandSection.phase {
        case .idle, .loading:
            if viewModel.brandItems.isEmpty {
                LikedEditorialStatusPanel(
                    label: "LOADING",
                    text: "좋아요한 브랜드를 불러오는 중이에요",
                    showsProgress: true
                )
                    .padding(.horizontal, 20)
            } else {
                likedBrandCards
            }

        case .empty:
            LikedEditorialStatusPanel(
                label: "EMPTY",
                text: "아직 좋아요한 브랜드가 없어요"
            )
                .padding(.horizontal, 20)

        case .failed(let message):
            LikedEditorialStatusPanel(
                label: "UNAVAILABLE",
                text: message,
                retryAction: reload
            )
                .padding(.horizontal, 20)

        case .ready:
            likedBrandCards
        }
    }

    @ViewBuilder
    private var likedSeasonSection: some View {
        LikedEditorialSectionHeader(
            eyebrow: "SEASON EDIT",
            title: "시즌",
            count: viewModel.seasonItems.count
        )
            .padding(.horizontal, 20)

        switch viewModel.seasonSection.phase {
        case .idle, .loading:
            if viewModel.seasonItems.isEmpty {
                LikedEditorialStatusPanel(
                    label: "LOADING",
                    text: "좋아요한 시즌을 불러오는 중이에요",
                    showsProgress: true
                )
                    .padding(.horizontal, 20)
            } else {
                likedSeasonCards
            }

        case .empty:
            LikedEditorialStatusPanel(
                label: "EMPTY",
                text: "아직 좋아요한 시즌이 없어요"
            )
                .padding(.horizontal, 20)

        case .failed(let message):
            LikedEditorialStatusPanel(
                label: "UNAVAILABLE",
                text: message,
                retryAction: reload
            )
                .padding(.horizontal, 20)

        case .ready:
            likedSeasonCards
        }
    }

    @ViewBuilder
    private var likedPostSection: some View {
        LikedEditorialSectionHeader(
            eyebrow: "POST ARCHIVE",
            title: "포스트",
            count: viewModel.postItems.count
        )
            .padding(.horizontal, 20)

        switch viewModel.postSection.phase {
        case .idle, .loading:
            if viewModel.postItems.isEmpty {
                LikedEditorialStatusPanel(
                    label: "LOADING",
                    text: "좋아요한 포스트를 불러오는 중이에요",
                    showsProgress: true
                )
                    .padding(.horizontal, 20)
            } else {
                likedPostGrid
            }

        case .empty:
            LikedEditorialStatusPanel(
                label: "EMPTY",
                text: "아직 좋아요한 포스트가 없어요"
            )
                .padding(.horizontal, 20)

        case .failed(let message):
            LikedEditorialStatusPanel(
                label: "UNAVAILABLE",
                text: message,
                retryAction: reload
            )
                .padding(.horizontal, 20)

        case .ready:
            likedPostGrid
        }
    }

    private var likedBrandCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
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
            LazyHStack(alignment: .top, spacing: 12) {
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
        LazyVGrid(columns: postColumns, spacing: 6) {
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
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                .frame(width: 32, height: 28)
                .background(OutPickTheme.SwiftUIColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .padding(6)
        .accessibilityLabel("좋아요 메뉴")
    }

    private var content: some View {
        likedSectionsList
    }

    private func reload() {
        Task {
            await viewModel.reload()
        }
    }
}

private struct LikedEditorialHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("SAVED EDITS")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(OutPickTheme.SwiftUIColor.accent)

            Text("좋아요")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

            Text("마음에 든 브랜드와 룩북을 모아봤어요")
                .font(.subheadline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LikedEditorialSectionHeader: View {
    let eyebrow: String
    let title: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.accent)

                    Text(title)
                        .font(.system(size: 25, weight: .bold, design: .serif))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                }

                Spacer()

                Text(String(format: "%02d", count))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }

            Rectangle()
                .fill(OutPickTheme.SwiftUIColor.borderSubtle)
                .frame(height: 1)
        }
    }
}

private struct LikedEditorialStatusPanel: View {
    let label: String
    let text: String
    var showsProgress = false
    var retryAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textTertiary)

                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }

            Spacer(minLength: 12)

            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(OutPickTheme.SwiftUIColor.accent)
            } else if let retryAction {
                Button("다시 시도", action: retryAction)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(OutPickTheme.SwiftUIColor.borderSubtle)
                .frame(height: 1)
        }
    }
}
