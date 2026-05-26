//
//  LikedBrandsView.swift
//  OutPick
//
//  Created by Codex on 5/26/26.
//

import SwiftUI

struct LikedBrandsView: View {
    @StateObject private var viewModel: LikedBrandsViewModel
    @EnvironmentObject private var brandAdminSessionStore: BrandAdminSessionStore
    @State private var selectedBrandID: BrandID?

    private let coordinator: LookbookCoordinator

    init(
        viewModel: LikedBrandsViewModel,
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
                likedEmptySection(title: "좋아요 시즌", emptyText: "좋아요한 시즌이 없습니다.")
                likedEmptySection(title: "좋아요 포스트", emptyText: "좋아요한 포스트가 없습니다.")
            }
            .padding(.vertical, 18)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var likedBrandSection: some View {
        LikedContentSectionHeader(title: "좋아요 브랜드", count: viewModel.items.count)
            .padding(.horizontal, 20)

        if viewModel.items.isEmpty {
            LikedEmptySectionRow(text: "좋아요한 브랜드가 없습니다.")
                .padding(.horizontal, 20)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(viewModel.items) { item in
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
                                await viewModel.loadNextPageIfNeeded(current: item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
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

private struct LikedBrandCardView: View {
    let item: LikedBrandListItem
    let brandImageCache: any BrandImageCacheProtocol

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LookbookAssetImageView(
                primaryPath: item.brand.logoThumbPath,
                secondaryPath: item.brand.logoDetailPath ?? item.brand.logoOriginalPath,
                remoteURL: nil,
                sourcePageURL: nil,
                brandImageCache: brandImageCache,
                maxBytes: 1 * 1024 * 1024
            )
            .frame(width: 132, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground))
            )

            Text(item.brand.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .imageScale(.small)
                Text("\(item.brand.metrics.likeCount)")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(width: 132, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityIdentifier("lookbook.likedBrand.card")
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
