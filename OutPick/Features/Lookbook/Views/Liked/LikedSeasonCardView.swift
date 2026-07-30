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
        VStack(alignment: .leading, spacing: 9) {
            LookbookAssetImageView(
                primaryPath: item.season.coverThumbPath,
                secondaryPath: item.season.coverPath,
                remoteURL: item.season.coverRemoteURL.flatMap(URL.init(string:)),
                sourcePageURL: nil,
                brandImageCache: brandImageCache,
                maxBytes: 1 * 1024 * 1024
            )
            .frame(width: 156, height: 208)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(OutPickTheme.SwiftUIColor.surfaceBase)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
            }

            Text(item.season.title)
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                .lineLimit(2)

            HStack(spacing: 7) {
                Text("SEASON")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.accent)

                Spacer(minLength: 0)

                Image(systemName: "heart.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.like)

                Text("\(item.season.likeCount)")
                    .monospacedDigit()
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }
            .font(.caption2)
        }
        .frame(width: 156, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityIdentifier("lookbook.likedSeason.card")
    }
}
