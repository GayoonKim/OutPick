//
//  LikedPostCardView.swift
//  OutPick
//
//  Created by Codex on 6/2/26.
//

import SwiftUI

struct LikedPostCardView: View {
    let item: LikedPostListItem
    let brandImageCache: any BrandImageCacheProtocol

    var body: some View {
        LookbookAssetImageView(
            primaryPath: item.post.media.first?.preferredListPath,
            secondaryPath: item.post.media.first?.preferredDetailPath,
            remoteURL: item.post.media.first?.remoteURL,
            sourcePageURL: item.post.media.first?.sourcePageURL,
            brandImageCache: brandImageCache,
            maxBytes: 1_500_000
        )
        .aspectRatio(0.76, contentMode: .fill)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
        .contentShape(Rectangle())
        .accessibilityIdentifier("lookbook.likedPost.card")
    }
}
