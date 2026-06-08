//
//  LikedBrandRowView.swift
//  OutPick
//
//  Created by Codex on 5/26/26.
//

import SwiftUI

struct LikedBrandCardView: View {
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
                    .fill(OutPickTheme.SwiftUIColor.surfaceBase)
            )

            Text(item.brand.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                .lineLimit(1)

            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .imageScale(.small)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.like)
                Text("\(item.brand.metrics.likeCount)")
                    .monospacedDigit()
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }
            .font(.caption)
        }
        .frame(width: 132, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityIdentifier("lookbook.likedBrand.card")
    }
}
