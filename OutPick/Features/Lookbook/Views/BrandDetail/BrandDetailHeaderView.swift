//
//  BrandDetailHeaderView.swift
//  OutPick
//
//  Created by 김가윤 on 1/3/26.
//

import SwiftUI

struct BrandDetailHeaderView: View {
    let brand: Brand
    let likeCount: Int
    let isLiked: Bool
    let isMutatingLike: Bool
    let brandImageCache: any BrandImageCacheProtocol
    let maxBytes: Int
    let onLikeTap: () async -> Void
    let onShareTap: () -> Void

    @Environment(\.openURL) private var openURL

    private var officialWebsiteURL: URL? {
        guard let rawValue = brand.websiteURL, rawValue.isEmpty == false else {
            return nil
        }
        return URL(string: rawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 브랜드 이름 + 좋아요 버튼
            VStack(alignment: .leading, spacing: 6) {
                Text(brand.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                if let englishName = brand.englishName, englishName.isEmpty == false {
                    Text(englishName)
                        .font(.subheadline)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                }

                Button {
                    Task {
                        await onLikeTap()
                    }
                } label: {
                    HStack(spacing: 6) {
                        ZStack {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(
                                    isLiked
                                        ? OutPickTheme.SwiftUIColor.like
                                        : OutPickTheme.SwiftUIColor.iconSecondary
                                )
                                .opacity(isMutatingLike ? 0 : 1)

                            if isMutatingLike {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(
                                        isLiked
                                            ? OutPickTheme.SwiftUIColor.like
                                            : OutPickTheme.SwiftUIColor.iconSecondary
                                    )
                            }
                        }
                        .frame(width: 18, height: 18)

                        Text("좋아요 \(likeCount)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(
                                isLiked
                                    ? OutPickTheme.SwiftUIColor.like
                                    : OutPickTheme.SwiftUIColor.textSecondary
                            )
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(
                                isLiked
                                    ? OutPickTheme.SwiftUIColor.like.opacity(0.12)
                                    : OutPickTheme.SwiftUIColor.surfaceElevated
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("브랜드 좋아요 \(likeCount)")

                HStack(spacing: 8) {
                    if let officialWebsiteURL {
                        Button {
                            openURL(officialWebsiteURL)
                        } label: {
                            Label("공식 사이트 방문", systemImage: "safari")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(OutPickTheme.SwiftUIColor.accent)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onShareTap) {
                        VStack(spacing: 2) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
                                .frame(width: 34, height: 28)

                            Text("공유")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(OutPickTheme.SwiftUIColor.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("브랜드 공유")
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)

            // 분리선
            Divider()
                .overlay(OutPickTheme.SwiftUIColor.borderSubtle)
                .padding(.horizontal, 16)
        }
    }

}
