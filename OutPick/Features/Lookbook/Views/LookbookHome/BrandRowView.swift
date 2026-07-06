//
//  BrandRowView.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct BrandRowView: View {
    let brand: Brand
    let brandImageCache: any BrandImageCacheProtocol

    #if canImport(UIKit)
    @State private var uiImage: UIImage? = nil
    #endif

    @State private var loadFailed: Bool = false
    @State private var lastRequestedPath: String?

    // 목록 썸네일이므로 다운로드 최대 용량을 낮게 유지합니다. (대략 1MB)
    private let maxLogoBytes: Int = 1 * 1024 * 1024

    // 콜라주(현재는 이미지 1장만 사용) 영역 크기
    private let collageHeight: CGFloat = 240
    private let collageCornerRadius: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            collageView

            Text(brand.name)
                .font(.headline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

            if let englishName = brand.englishName, englishName.isEmpty == false {
                Text(englishName)
                    .font(.subheadline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }

            HStack(spacing: 10) {
                likeChip(value: brand.metrics.likeCount) // 좋아요만 표시
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(OutPickTheme.SwiftUIColor.surfaceBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
        )
        .task(id: brand.listLogoPath ?? "__empty_logo_path__") {
            await loadLogoIfNeeded()
        }
        .accessibilityIdentifier("lookbook.brand.card")
    }

    private var collageView: some View {
        GeometryReader { geo in
            imageSlot
                .frame(width: geo.size.width, height: collageHeight, alignment: .top)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: collageCornerRadius))
        }
        .frame(height: collageHeight)
    }

    @ViewBuilder
    private var imageSlot: some View {
        #if canImport(UIKit)
        if let uiImage {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                // 얼굴이 위쪽에서 잘리는 경우가 많아서 상단 기준으로 크롭되도록 정렬을 고정합니다.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            placeholderSlot
        }
        #else
        placeholderSlot
        #endif
    }

    private var placeholderSlot: some View {
        Rectangle()
            .fill(OutPickTheme.SwiftUIColor.backgroundRaised)
            .overlay {
                Image(systemName: loadFailed ? "exclamationmark.triangle" : "photo")
                    .font(.title3)
                    .foregroundStyle(
                        loadFailed
                            ? OutPickTheme.SwiftUIColor.warning
                            : OutPickTheme.SwiftUIColor.iconSecondary
                    )
            }
    }

    private func likeChip(value: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .foregroundStyle(OutPickTheme.SwiftUIColor.like)
            Text("\(value)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            Capsule().fill(OutPickTheme.SwiftUIColor.surfaceElevated)
        )
    }

    // MARK: - Loading

    @MainActor
    private func loadLogoIfNeeded() async {
        // 목록에서는 썸네일 -> detail -> original 순으로 폴백합니다.
        let resolvedPath = brand.listLogoPath
        guard let path = resolvedPath, !path.isEmpty else { return }

        // 한국어 주석: 같은 셀 인스턴스가 유지된 채 로고 경로만 바뀌는 경우를 위해 상태를 초기화합니다.
        if lastRequestedPath != path {
            lastRequestedPath = path
            loadFailed = false
            #if canImport(UIKit)
            uiImage = nil
            #endif
        }

        // 이미 로드했거나 실패했다면 중복 호출 방지
        #if canImport(UIKit)
        if uiImage != nil || loadFailed { return }
        #else
        if loadFailed { return }
        #endif

        do {
            #if canImport(UIKit)
            let image = try await brandImageCache.loadImage(
                path: path,
                maxBytes: maxLogoBytes
            )
            uiImage = image
            #endif
        } catch {
            loadFailed = true
        }
    }
}
