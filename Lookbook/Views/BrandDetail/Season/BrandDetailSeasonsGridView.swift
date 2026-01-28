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
    let imageLoader: any ImageLoading
    let maxBytes: Int

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

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.9)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }

            if seasons.isEmpty, !isLoading, errorMessage == nil {
                Text("등록된 시즌이 없습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(seasons, id: \.id) { season in
                        BrandDetailSeasonGridItemView(
                            season: season,
                            imageLoader: imageLoader,
                            maxBytes: maxBytes
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }
}
