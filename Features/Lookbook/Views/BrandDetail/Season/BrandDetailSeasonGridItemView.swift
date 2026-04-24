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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SeasonCoverThumbView(
                thumbPath: season.coverThumbPath,
                fallbackPath: season.coverPath,
                remoteURL: season.coverRemoteURL,
                sourcePageURL: season.sourceURL,
                brandImageCache: brandImageCache,
                maxBytes: maxBytes
            )
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(season.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
    }
}
