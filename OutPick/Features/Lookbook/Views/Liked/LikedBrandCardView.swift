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
            Text(item.brand.name)
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                .lineLimit(2)

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
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lookbook.likedBrand.card")
    }
}
