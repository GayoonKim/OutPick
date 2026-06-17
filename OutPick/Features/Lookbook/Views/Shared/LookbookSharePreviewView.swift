//
//  LookbookSharePreviewView.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import SwiftUI

struct LookbookSharePreviewView: View {
    let sharedContent: LookbookSharedContent
    let brandImageCache: any BrandImageCacheProtocol

    var body: some View {
        HStack(spacing: 12) {
            LookbookAssetImageView(
                primaryPath: sharedContent.thumbnailPathSnapshot,
                secondaryPath: nil,
                remoteURL: nil,
                sourcePageURL: nil,
                brandImageCache: brandImageCache,
                maxBytes: 1_000_000
            )
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(sharedContent.compactDisplayTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                    .lineLimit(1)

                if let subtitle = sharedContent.compactDisplaySubtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

}
