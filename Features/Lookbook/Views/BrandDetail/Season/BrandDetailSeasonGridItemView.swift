//
//  BrandDetailSeasonGridItemView.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/26.
//

import SwiftUI

struct BrandDetailSeasonGridItemView: View {
    let season: Season
    let brandImageCache: any BrandImageCacheProtocol
    let maxBytes: Int
    let onTap: ((Season) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SeasonCoverThumbView(
                thumbPath: season.coverThumbPath,
                fallbackPath: season.coverPath,
                brandImageCache: brandImageCache,
                maxBytes: maxBytes
            )
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(seasonTitle)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?(season)
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
