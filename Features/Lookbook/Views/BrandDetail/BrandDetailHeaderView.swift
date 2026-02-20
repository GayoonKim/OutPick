//
//  BrandDetailHeaderView.swift
//  OutPick
//
//  Created by 김가윤 on 1/3/26.
//

import SwiftUI

struct BrandDetailHeaderView: View {
    let brand: Brand
    let imageLoader: any ImageLoading
    let maxBytes: Int

    @State private var uiImage: UIImage?
    @State private var loadFailed: Bool = false
    @State private var isPresentingZoomPreview: Bool = false
    @State private var detailUpgradeTask: Task<Void, Never>?

    /// 홈에서 prewarm된 썸네일을 즉시 재사용하기 위해 썸네일을 우선 표시합니다.
    private var headerImagePath: String? {
        if let thumb = brand.logoThumbPath, thumb.isEmpty == false {
            return thumb
        }
        let candidate = brand.logoDetailPath ?? brand.logoOriginalPath
        guard let candidate, candidate.isEmpty == false else { return nil }
        return candidate
    }

    /// 이미 저장된 detail/original이 있으면 썸네일 표시 후 교체합니다.
    private var preferredDetailPath: String? {
        if let detail = brand.logoDetailPath, detail.isEmpty == false, detail != headerImagePath {
            return detail
        }
        if let original = brand.logoOriginalPath, original.isEmpty == false, original != headerImagePath {
            return original
        }
        return nil
    }

    /// 생성 직후(thumb만 저장된 상태)에도 detail 업로드 완료 시 자동 교체하기 위한 경로
    private var deferredDetailPath: String? {
        if let existingDetail = brand.logoDetailPath, existingDetail.isEmpty == false {
            return nil
        }
        guard brand.logoOriginalPath == nil else { return nil }
        guard let thumbPath = brand.logoThumbPath, !thumbPath.isEmpty else { return nil }
        if thumbPath.hasSuffix("/logo/thumb.jpg") {
            return String(thumbPath.dropLast("thumb.jpg".count)) + "detail.jpg"
        }
        if let lastSlash = thumbPath.lastIndex(of: "/") {
            return String(thumbPath[..<lastSlash]) + "/detail.jpg"
        }
        return "brands/\(brand.id.value)/logo/detail.jpg"
    }

    private var cacheKey: String? {
        guard let path = headerImagePath else { return nil }
        return "brandLogo|\(path)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 상단 로고(큰 이미지) - 캐시된 UIImage를 사용
            ZStack {
                if let uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        // 좌/우 빈 공간이 생기지 않도록 채우기(필요한 만큼 일부가 잘릴 수 있음)
                        .scaledToFill()
                        // 얼굴이 위쪽에서 잘리는 경우가 많아서 상단 기준으로 크롭되도록 정렬을 고정합니다.
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isPresentingZoomPreview = true
                        }
                } else if loadFailed {
                    Image(systemName: "photo")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            // 배경색을 두지 않아 이미지 뒤에 회색 배경이 보이지 않습니다.
            // 좌/우 끝까지 붙는 느낌 (클립/라운드 없음)
            .background(Color.clear)
            .frame(maxWidth: .infinity)
            .frame(height: 220, alignment: .top)
            .clipped()
            .task(id: "\(headerImagePath ?? "")|\(preferredDetailPath ?? deferredDetailPath ?? "")") {
                await loadLogoIfNeeded()
                scheduleDetailUpgradeIfNeeded()
            }
            .fullScreenCover(isPresented: $isPresentingZoomPreview) {
                if let image = uiImage {
                    ZoomPreviewView(image: image)
                }
            }
            .onDisappear {
                detailUpgradeTask?.cancel()
                detailUpgradeTask = nil
            }

            // 브랜드 이름 + 좋아요 수
            VStack(alignment: .leading, spacing: 6) {
                Text(brand.name)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("좋아요 \(brand.metrics.likeCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            // 분리선
            Divider()
                .padding(.horizontal, 16)
        }
    }

    private func loadLogoIfNeeded() async {
        // 이미 로딩된 이미지가 있거나 실패 상태면 재시도하지 않음(원하면 정책 바꿔도 됨)
        if uiImage != nil || loadFailed { return }

        guard
            let path = headerImagePath,
            let cacheKey
        else {
            loadFailed = true
            return
        }

        do {
            let headerMaxBytes = max(maxBytes, 8_000_000)
            // BrandLogoImageStore 내부에서 캐시/중복 다운로드 방지가 처리됩니다.
            let image = try await imageLoader.loadImage(
                path: path,
                cacheKey: cacheKey,
                maxBytes: headerMaxBytes
            )
            uiImage = image
        } catch {
            loadFailed = true
        }
    }

    private func scheduleDetailUpgradeIfNeeded() {
        guard detailUpgradeTask == nil else { return }
        guard let detailPath = preferredDetailPath ?? deferredDetailPath else { return }

        let maxLoadBytes = max(maxBytes, 8_000_000)
        let detailCacheKey = "brandLogo|\(detailPath)"

        detailUpgradeTask = Task(priority: .utility) {
            // 짧은 시간 재시도로 detail 업로드 완료를 감지
            for attempt in 0..<8 {
                if Task.isCancelled { break }
                do {
                    let upgraded = try await imageLoader.loadImage(
                        path: detailPath,
                        cacheKey: detailCacheKey,
                        maxBytes: maxLoadBytes
                    )
                    if Task.isCancelled { break }
                    await MainActor.run {
                        self.uiImage = upgraded
                        self.loadFailed = false
                    }
                    break
                } catch {
                    if attempt == 7 { break }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }

            await MainActor.run {
                self.detailUpgradeTask = nil
            }
        }
    }
}

private struct ZoomPreviewView: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .simultaneousGesture(magnificationGesture)
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if scale > 1 {
                            resetZoom()
                        } else {
                            scale = 2
                            baseScale = 2
                        }
                    }
                }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .padding(16)
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                if scale <= 1 {
                    resetZoom()
                } else {
                    baseOffset = offset
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let nextScale = min(max(baseScale * value, minScale), maxScale)
                scale = nextScale
                if nextScale <= minScale {
                    offset = .zero
                    baseOffset = .zero
                }
            }
            .onEnded { _ in
                if scale <= minScale {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        resetZoom()
                    }
                } else {
                    baseScale = scale
                }
            }
    }

    private func resetZoom() {
        scale = 1
        baseScale = 1
        offset = .zero
        baseOffset = .zero
    }
}
