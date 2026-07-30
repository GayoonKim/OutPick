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
        VStack(alignment: .leading, spacing: 9) {
            LookbookAssetImageView(
                primaryPath: item.brand.logoThumbPath,
                secondaryPath: item.brand.logoDetailPath ?? item.brand.logoOriginalPath,
                remoteURL: nil,
                sourcePageURL: nil,
                brandImageCache: brandImageCache,
                maxBytes: 1 * 1024 * 1024
            )
            .frame(width: 148, height: 148)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(OutPickTheme.SwiftUIColor.surfaceBase)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
            }

            Text(item.brand.name)
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                .lineLimit(1)

            HStack(spacing: 7) {
                Text("BRAND")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.accent)

                Spacer(minLength: 0)

                Image(systemName: "heart.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.like)

                Text("\(item.brand.metrics.likeCount)")
                    .monospacedDigit()
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }
            .font(.caption2)
        }
        .frame(width: 148, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityIdentifier("lookbook.likedBrand.card")
    }
}
