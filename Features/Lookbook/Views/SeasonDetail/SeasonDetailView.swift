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

    private let brandImageCache: any BrandImageCacheProtocol
    private let coordinator: LookbookCoordinator

    @StateObject private var viewModel: SeasonDetailViewModel
    @State private var selectedPost: LookbookPost?

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    init(
        brandID: BrandID,
        seasonID: SeasonID,
        viewModel: SeasonDetailViewModel,
        brandImageCache: any BrandImageCacheProtocol,
        coordinator: LookbookCoordinator
    ) {
        self.brandID = brandID
        self.seasonID = seasonID
        self.brandImageCache = brandImageCache
        self.coordinator = coordinator
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if shouldBlockInitialLoading {
                loadingSection
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        if let season = viewModel.season {
                            SeasonDetailHeaderCardView(season: season)
                        }

                        if let errorMessage = viewModel.errorMessage, viewModel.posts.isEmpty {
                            errorSection(message: errorMessage)
                        } else if viewModel.posts.isEmpty {
                            emptySection
                        } else {
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(viewModel.posts, id: \.id) { post in
                                    Button {
                                        selectedPost = post
                                    } label: {
                                        SeasonLookGridItemView(
                                            post: post,
                                            brandImageCache: brandImageCache
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .onAppear {
                                        viewModel.postDidAppear(postID: post.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.97, blue: 0.94),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationBarTitleDisplayMode(.inline)
        .background(hiddenNavigationLink)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var loadingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.black)
            Text("포스트 목록을 불러오는 중입니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorSection(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("룩북을 불러오지 못했습니다.")
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

    private var emptySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("등록된 룩이 없습니다.")
                .font(.headline)
            Text("아직 이 시즌에 준비된 사진이 없습니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var hiddenNavigationLink: some View {
        NavigationLink(
            destination: selectedPostDestination,
            isActive: selectedPostBinding
        ) {
            EmptyView()
        }
        .hidden()
    }

    @ViewBuilder
    private var selectedPostDestination: some View {
        if let selectedPost {
            coordinator.makePostDetailView(post: selectedPost)
        } else {
            EmptyView()
        }
    }

    private var selectedPostBinding: Binding<Bool> {
        Binding(
            get: { selectedPost != nil },
            set: { isActive in
                if !isActive {
                    selectedPost = nil
                }
            }
        )
    }

    private var shouldBlockInitialLoading: Bool {
        viewModel.isLoading && viewModel.posts.isEmpty && viewModel.errorMessage == nil
    }
}
