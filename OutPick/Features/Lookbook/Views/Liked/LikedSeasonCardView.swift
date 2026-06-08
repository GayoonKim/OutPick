//
//  Untitled.swift
//  OutPick
//
//  Created by 김가윤 on 5/27/26.
//

import SwiftUI

struct LikedSeasonCardView: View {
    let item: LikedSeasonListItem
    let brandImageCache: any BrandImageCacheProtocol

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LookbookAssetImageView(
                primaryPath: item.season.coverThumbPath,
                secondaryPath: item.season.coverPath,
                remoteURL: item.season.coverRemoteURL.flatMap(URL.init(string:)),
                sourcePageURL: nil,
                brandImageCache: brandImageCache,
                maxBytes: 1 * 1024 * 1024
            )
            .frame(width: 132, height: 176)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(OutPickTheme.SwiftUIColor.surfaceBase)
            )

            Text(item.season.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                .lineLimit(2)

            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .imageScale(.small)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.like)
                Text("\(item.season.likeCount)")
                    .monospacedDigit()
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }
            .font(.caption)
        }
        .frame(width: 132, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityIdentifier("lookbook.likedSeason.card")
    }
}
