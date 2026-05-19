//
//  BrandDetailView.swift
//  OutPick
//
//  Created by 김가윤 on 1/3/26.
//

import SwiftUI

struct BrandDetailView: View {
    let brand: Brand
    let brandImageCache: any BrandImageCacheProtocol
    let maxBytes: Int
    let coordinator: LookbookCoordinator
    let seasonAdditionSheetFactory: (@escaping () -> Void) -> AnyView

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var brandAdminSessionStore: BrandAdminSessionStore
    @StateObject private var viewModel: BrandDetailViewModel
    @State private var isPresentingSeasonAddition: Bool = false
    @State private var didPrepareInitialContent: Bool = false

    init(
        brand: Brand,
        viewModel: BrandDetailViewModel,
        brandImageCache: any BrandImageCacheProtocol,
        coordinator: LookbookCoordinator,
        seasonAdditionSheetFactory: @escaping (@escaping () -> Void) -> AnyView,
        maxBytes: Int = 1_000_000
    ) {
        self.brand = brand
        self.brandImageCache = brandImageCache
        self.coordinator = coordinator
        self.seasonAdditionSheetFactory = seasonAdditionSheetFactory
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
                        coordinator: coordinator,
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
                        isPresentingSeasonAddition = true
                    } label: {
                        Text("시즌 추가")
                            .foregroundStyle(.black)
                    }
                    .accessibilityLabel("시즌 추가")
                }
            }
        }
        .sheet(isPresented: $isPresentingSeasonAddition, onDismiss: {
            Task {
                await viewModel.refreshContents(brandID: brand.id)
            }
        }) {
            seasonAdditionSheetFactory {
                isPresentingSeasonAddition = false
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
