//
//  BrandDetailView.swift
//  OutPick
//
//  Created by 김가윤 on 1/3/26.
//

import SwiftUI

struct BrandDetailView: View {
    let brand: Brand
    let imageLoader: any ImageLoading
    let maxBytes: Int

    @Environment(\.repositoryProvider) private var provider
    @StateObject private var viewModel = BrandDetailViewModel()
    @State private var isPresentCreateSeason: Bool = false

    init(
        brand: Brand,
        imageLoader: any ImageLoading,
        maxBytes: Int = 1_000_000
    ) {
        self.brand = brand
        self.imageLoader = imageLoader
        self.maxBytes = maxBytes
    }

    var body: some View {
        List {
            BrandDetailHeaderView(
                brand: brand,
                imageLoader: imageLoader,
                maxBytes: maxBytes
            )
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)

            BrandDetailSeasonsGridView(
                seasons: viewModel.seasons,
                isLoading: viewModel.isLoading,
                errorMessage: viewModel.errorMessage,
                imageLoader: imageLoader,
                maxBytes: maxBytes
            )
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle(brand.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isPresentCreateSeason = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("시즌 추가")
            }
        }
        .sheet(isPresented: $isPresentCreateSeason, onDismiss: {
            Task {
                await viewModel.refreshSeasons(
                    brandID: brand.id,
                    seasonRepository: provider.seasonRepository
                )
            }
        }) {
            CreateSeasonView(
                viewModel: CreateSeasonViewModel(
                    brandID: brand.id,
                    seasonRepository: provider.seasonRepository,
                    tagRepository: provider.tagRepository,
                    tagAliasRepository: provider.tagAliasRepository,
                    tagConceptRepository: provider.tagConceptRepository
                )
            )
        }
        .task {
            await viewModel.loadSeasonsIfNeeded(
                brandID: brand.id,
                seasonRepository: provider.seasonRepository
            )
        }
    }
}
