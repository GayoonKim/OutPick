//
//  LikedBrandRowView.swift
//  OutPick
//
//  Created by Codex on 5/26/26.
//

import SwiftUI

struct LikedBrandRowView: View {
    let item: LikedBrandListItem
    let brandImageCache: any BrandImageCacheProtocol

    var body: some View {
        HStack(spacing: 12) {
            LookbookAssetImageView(
                primaryPath: item.brand.logoThumbPath,
                secondaryPath: item.brand.logoDetailPath ?? item.brand.logoOriginalPath,
                remoteURL: nil,
                sourcePageURL: nil,
                brandImageCache: brandImageCache,
                maxBytes: 1 * 1024 * 1024
            )
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.brand.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Image(systemName: "heart.fill")
                        .imageScale(.small)
                    Text("\(item.brand.metrics.likeCount)")
                        .font(.subheadline)
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

//            Image(systemName: "chevron.right")
//                .font(.footnote.weight(.semibold))
//                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityIdentifier("lookbook.likedBrand.row")
    }
}
