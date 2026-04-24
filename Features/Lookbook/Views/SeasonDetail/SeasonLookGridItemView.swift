//
//  SeasonLookGridItemView.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import SwiftUI

struct SeasonLookGridItemView: View {
    let post: LookbookPost
    let brandImageCache: any BrandImageCacheProtocol

    private var firstMedia: MediaAsset? {
        post.media.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LookbookAssetImageView(
                primaryPath: firstMedia?.preferredListPath,
                secondaryPath: firstMedia?.preferredDetailPath,
                remoteURL: firstMedia?.remoteURL,
                sourcePageURL: firstMedia?.sourcePageURL,
                brandImageCache: brandImageCache,
                maxBytes: 1_500_000
            )
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0),
                        Color.black.opacity(0.45)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let captionText {
                            Text(captionText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        }

                        Text("좋아요 \(post.metrics.likeCount) · 댓글 \(post.metrics.commentCount)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.88))
                    }
                    .padding(12)
                }
            }
        }
    }

    private var captionText: String? {
        guard let caption = post.caption?.trimmingCharacters(in: .whitespacesAndNewlines),
              caption.isEmpty == false else {
            return nil
        }
        return caption
    }
}
