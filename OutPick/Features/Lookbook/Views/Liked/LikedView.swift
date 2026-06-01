//
//  LikedView.swift
//  OutPick
//
//  Created by Codex on 5/26/26.
//

import SwiftUI

struct LikedView: View {
    @StateObject private var viewModel: LikedViewModel
    @EnvironmentObject private var brandAdminSessionStore: BrandAdminSessionStore
    @State private var selectedBrandID: BrandID?
    @State private var selectedSeasonID: String?

    private let coordinator: LookbookCoordinator

    init(
        viewModel: LikedViewModel,
        coordinator: LookbookCoordinator
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.coordinator = coordinator
    }

    var body: some View {
        NavigationView {
            content
                .navigationTitle("좋아요")
                .navigationBarTitleDisplayMode(.inline)
                .task {
                    await viewModel.refreshForActivation()
                }
                .refreshable {
                    await viewModel.reload()
                }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .tint(.black)
    }

    private var likedSectionsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                likedBrandSection
                likedSeasonSection
                likedEmptySection(title: "좋아요 포스트", emptyText: "좋아요한 포스트가 없습니다.")
            }
            .padding(.vertical, 18)
        }
        .background(Color(.systemBackground))
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

    private var likedBrandCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(viewModel.brandItems) { item in
                    Button {
                        selectedBrandID = item.id
                    } label: {
                        LikedBrandCardView(
                            item: item,
                            brandImageCache: viewModel.brandImageCache
                        )
                    }
                    .buttonStyle(.plain)
                    .background {
                        NavigationLink(
                            destination: coordinator.makeBrandDetailView(brand: item.brand)
                                .environmentObject(brandAdminSessionStore),
                            tag: item.id,
                            selection: $selectedBrandID
                        ) {
                            EmptyView()
                        }
                        .opacity(0)
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
                    Button {
                        selectedSeasonID = item.id
                    } label: {
                        LikedSeasonCardView(
                            item: item,
                            brandImageCache: viewModel.brandImageCache
                        )
                    }
                    .buttonStyle(.plain)
                    .background {
                        NavigationLink(
                            destination: coordinator.makeSeasonDetailView(season: item.season),
                            tag: item.id,
                            selection: $selectedSeasonID
                        ) {
                            EmptyView()
                        }
                        .opacity(0)
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

    private func likedEmptySection(title: String, emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LikedContentSectionHeader(title: title, count: 0)
            LikedEmptySectionRow(text: emptyText)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle, .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("로딩 중...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .empty:
            likedSectionsList

        case .failed(let message):
            VStack(spacing: 12) {
                Text("불러오기 실패")
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("다시 시도") {
                    Task { await viewModel.reload() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)

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
            Text("\(count)")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
    }
}

private struct LikedEmptySectionRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
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
            }
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}
