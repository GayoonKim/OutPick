//
//  BrandDetailSeasonsGridView.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/26.
//

import SwiftUI

struct BrandDetailSeasonsGridView: View {
    let seasons: [Season]
    let isLoading: Bool
    let errorMessage: String?
    let canManageBrand: Bool
    let brandImageCache: any BrandImageCacheProtocol
    let maxBytes: Int
    let coordinator: LookbookCoordinator
    let onSeasonAppear: (Season) -> Void

    @State private var selectedSeason: Season?

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("시즌")
                    .font(.headline)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }

            if seasons.isEmpty, isLoading {
                loadingSection
            } else if seasons.isEmpty, !isLoading, errorMessage == nil {
                Text(emptyStateMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(seasons, id: \.id) { season in
                        Button {
                            selectedSeason = season
                        } label: {
                            BrandDetailSeasonGridItemView(
                                season: season,
                                brandImageCache: brandImageCache,
                                maxBytes: maxBytes
                            )
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            onSeasonAppear(season)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(hiddenNavigationLink)
    }

    private var loadingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.black)
                .scaleEffect(1.05)

            Text("시즌 목록을 불러오는 중입니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
    }

    private var emptyStateMessage: String {
        canManageBrand ?
            "등록된 시즌이 없습니다. 상단의 시즌 추가에서 시즌을 가져올 수 있습니다." :
            "등록된 시즌이 없습니다."
    }

    @ViewBuilder
    private var hiddenNavigationLink: some View {
        NavigationLink(
            destination: selectedSeasonDestination,
            isActive: selectedSeasonBinding
        ) {
            EmptyView()
        }
        .hidden()
    }

    @ViewBuilder
    private var selectedSeasonDestination: some View {
        if let selectedSeason {
            coordinator.makeSeasonDetailView(season: selectedSeason)
        } else {
            EmptyView()
        }
    }

    private var selectedSeasonBinding: Binding<Bool> {
        Binding(
            get: { selectedSeason != nil },
            set: { isActive in
                if !isActive {
                    selectedSeason = nil
                }
            }
        )
    }

}
