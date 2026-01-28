//
//  BrandDetailSeasonGridItemView.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/26.
//

import SwiftUI

struct BrandDetailSeasonGridItemView: View {
    let season: Season
    let imageLoader: any ImageLoading
    let maxBytes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SeasonCoverThumbView(
                thumbPath: season.coverThumbPath,
                fallbackPath: season.coverPath,
                imageLoader: imageLoader,
                maxBytes: maxBytes
            )
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(seasonTitle)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
    }

    private var seasonTitle: String {
        let yy = season.year % 100
        return String(format: "%02d%@", yy, termText)
    }

    private var termText: String {
        switch season.term {
        case .fw: return "FW"
        case .ss: return "SS"
        }
    }
}
