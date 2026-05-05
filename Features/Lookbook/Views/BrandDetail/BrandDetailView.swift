//
//  BrandDetailView.swift
//  OutPick
//
//  Created by 김가윤 on 1/3/26.
//

import SwiftUI

struct BrandDetailView: View {
    private enum SeasonCreationSheet: String, Identifiable {
        case candidateSelection

        var id: String { rawValue }
    }

    let brand: Brand
    let brandImageCache: any BrandImageCacheProtocol
    let maxBytes: Int
    let seasonDestination: (Season) -> AnyView
    let seasonCandidateSelectionFactory: (CreateBrandViewModel.CreatedBrand, @escaping () -> Void) -> AnyView

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var brandAdminSessionStore: BrandAdminSessionStore
    @StateObject private var viewModel: BrandDetailViewModel
    @State private var activeSeasonSheet: SeasonCreationSheet?
    @State private var didPrepareInitialContent: Bool = false

    init(
        brand: Brand,
        viewModel: BrandDetailViewModel,
        brandImageCache: any BrandImageCacheProtocol,
        seasonDestination: @escaping (Season) -> AnyView,
        seasonCandidateSelectionFactory: @escaping (CreateBrandViewModel.CreatedBrand, @escaping () -> Void) -> AnyView,
        maxBytes: Int = 1_000_000
    ) {
        self.brand = brand
        self.brandImageCache = brandImageCache
        self.seasonDestination = seasonDestination
        self.seasonCandidateSelectionFactory = seasonCandidateSelectionFactory
        self.maxBytes = maxBytes
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if shouldBlockInitialLoading {
                initialLoadingView
            } else {
                List {
                    BrandDetailHeaderView(
                        brand: brand,
                        brandImageCache: brandImageCache,
                        maxBytes: maxBytes
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)

                    BrandDetailSeasonsGridView(
                        seasons: viewModel.seasons,
                        isLoading: viewModel.isLoading,
                        errorMessage: viewModel.errorMessage,
                        canManageBrand: brandAdminSessionStore.canWrite(brandID: brand.id),
                        brandImageCache: brandImageCache,
                        maxBytes: maxBytes,
                        seasonDestination: seasonDestination,
                        onSeasonAppear: { season in
                            viewModel.seasonDidAppear(seasonID: season.id)
                        }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .tint(.black)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.black)
                }
                .accessibilityLabel("뒤로 가기")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if brandAdminSessionStore.canWrite(brandID: brand.id),
                   hasLookbookArchiveURL {
                    Button {
                        activeSeasonSheet = .candidateSelection
                    } label: {
                        Text("시즌 추가")
                            .foregroundStyle(.black)
                    }
                    .accessibilityLabel("시즌 추가")
                }
            }
        }
        .sheet(item: $activeSeasonSheet, onDismiss: {
            Task {
                await viewModel.refreshContents(brandID: brand.id)
            }
        }) { sheet in
            switch sheet {
            case .candidateSelection:
                NavigationView {
                    seasonCandidateSelectionFactory(
                        CreateBrandViewModel.CreatedBrand(
                            id: brand.id,
                            name: brand.name,
                            websiteURL: brand.websiteURL,
                            lookbookArchiveURL: brand.lookbookArchiveURL,
                            hasLogoAsset: brand.logoThumbPath != nil
                        ),
                        { activeSeasonSheet = nil }
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("닫기") {
                                activeSeasonSheet = nil
                            }
                        }
                    }
                }
            }
        }
        .task {
            if !brandAdminSessionStore.canWrite(brandID: brand.id) {
                await brandAdminSessionStore.refreshWritableBrands(force: true)
            }

            if didPrepareInitialContent == false {
                await prewarmHeaderLogoIfNeeded()
                await viewModel.loadContentsIfNeeded(brandID: brand.id)
                didPrepareInitialContent = true
            }
        }
    }

    private var hasLookbookArchiveURL: Bool {
        guard let lookbookArchiveURL = brand.lookbookArchiveURL else {
            return false
        }
        return !lookbookArchiveURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldBlockInitialLoading: Bool {
        didPrepareInitialContent == false && viewModel.seasons.isEmpty && viewModel.errorMessage == nil
    }

    private var initialLoadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.black)
                .scaleEffect(1.05)

            Text("브랜드를 준비하는 중입니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color(.systemBackground)
                .ignoresSafeArea()
        )
    }

    private var headerPrewarmPath: String? {
        if let thumb = brand.logoThumbPath, thumb.isEmpty == false {
            return thumb
        }

        if let detail = brand.logoDetailPath, detail.isEmpty == false {
            return detail
        }

        if let original = brand.logoOriginalPath, original.isEmpty == false {
            return original
        }

        return nil
    }

    private func prewarmHeaderLogoIfNeeded() async {
        guard let headerPrewarmPath else { return }

        await brandImageCache.prefetch(
            items: [(path: headerPrewarmPath, maxBytes: max(maxBytes, 8_000_000))],
            concurrency: 1,
            storePolicy: .memoryOnly
        )
    }

}
