//
//  LookbookAssetImageView.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import SwiftUI
import UIKit

struct LookbookAssetImageView: View {
    let primaryPath: String?
    let secondaryPath: String?
    let remoteURL: URL?
    let sourcePageURL: URL?
    let brandImageCache: any BrandImageCacheProtocol
    let maxBytes: Int
    let onLoadCompleted: ((Bool) -> Void)?

    @State private var uiImage: UIImage?
    @State private var isLoading: Bool = false
    @State private var didFail: Bool = false
    @State private var displayedIdentity: String?
    @State private var activeTaskKey: String?
    @State private var retryGeneration = 0

    init(
        primaryPath: String?,
        secondaryPath: String?,
        remoteURL: URL?,
        sourcePageURL: URL?,
        brandImageCache: any BrandImageCacheProtocol,
        maxBytes: Int,
        onLoadCompleted: ((Bool) -> Void)? = nil
    ) {
        self.primaryPath = primaryPath
        self.secondaryPath = secondaryPath
        self.remoteURL = remoteURL
        self.sourcePageURL = sourcePageURL
        self.brandImageCache = brandImageCache
        self.maxBytes = maxBytes
        self.onLoadCompleted = onLoadCompleted
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(OutPickTheme.SwiftUIColor.backgroundRaised)

            if let uiImage {
                GeometryReader { geo in
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .onAppear { ImageCacheMetrics.shared.mark("ui.asset.imageBranchAppeared", key: loadKey) }
                }
            } else if isLoading {
                ProgressView()
                    .tint(OutPickTheme.SwiftUIColor.accent)
            } else if didFail {
                Button {
                    retryGeneration &+= 1
                } label: {
                    Label("이미지 다시 시도", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.warning)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "photo")
                    .imageScale(.large)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.iconSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
        }
        .task(id: taskKey) {
            await ImageCacheMetrics.$consumer.withValue("visible") {
                await ImageCacheMetrics.shared.request(key: loadKey) { await loadImage() }
            }
        }
    }

    private var loadKey: String {
        assetRequest.identity
    }

    private var taskKey: String { "\(loadKey)|\(retryGeneration)" }

    private var assetRequest: LookbookAssetImageRequest {
        LookbookAssetImageRequest(
            primaryPath: primaryPath,
            secondaryPath: secondaryPath,
            remoteURL: remoteURL,
            sourcePageURL: sourcePageURL,
            maxBytes: maxBytes
        )
    }

    private func loadImage() async {
        let request = assetRequest
        let currentTaskKey = taskKey
        let isRetry = retryGeneration > 0
        activeTaskKey = currentTaskKey
        if displayedIdentity != loadKey {
            uiImage = nil
            displayedIdentity = loadKey
        }
        didFail = false
        isLoading = true
        defer {
            if activeTaskKey == currentTaskKey { isLoading = false }
        }

        for path in request.storagePaths {
            do {
                let image = try await brandImageCache.loadImage(
                    path: path,
                    maxBytes: maxBytes
                )
                try Task.checkCancellation()
                guard activeTaskKey == currentTaskKey else { return }
                uiImage = image
                onLoadCompleted?(true)
                ImageCacheMetrics.shared.mark("ui.asset.assigned", key: path, outcome: "success")
                return
            } catch {
                if error is CancellationError || Task.isCancelled { return }
                continue
            }
        }

        guard let remoteRequest = request.remote else {
            guard activeTaskKey == currentTaskKey, !Task.isCancelled else { return }
            if request.storagePaths.isEmpty { return }
            didFail = true
            onLoadCompleted?(false)
            return
        }
        let remoteURL = remoteRequest.remoteURL
        var completed = false
        if let cached = await brandImageCache.cachedRemoteImage(request: remoteRequest),
           cached.requiresValidation == false {
            guard !Task.isCancelled, activeTaskKey == currentTaskKey else { return }
            uiImage = cached.image
            onLoadCompleted?(true)
            completed = true
            ImageCacheMetrics.shared.mark("ui.asset.assigned", key: remoteURL.absoluteString, outcome: cached.isFresh ? "httpFresh" : "httpStale")
            if cached.isFresh { return }
        }
        do {
            let image: UIImage
            if isRetry {
                image = try await brandImageCache.retryRemoteImage(request: remoteRequest)
            } else {
                image = try await brandImageCache.updatedRemoteImage(request: remoteRequest)
            }
            try Task.checkCancellation()
            guard activeTaskKey == currentTaskKey else { return }
            uiImage = image
            ImageCacheMetrics.shared.mark("ui.asset.assigned", key: remoteURL.absoluteString, outcome: "httpValidated")
            if !completed { onLoadCompleted?(true) }
        } catch {
            if error is CancellationError || Task.isCancelled || activeTaskKey != currentTaskKey { return }
            if case LookbookHTTPImageError.permanentStatus = error {
                uiImage = nil
                didFail = true
                onLoadCompleted?(false)
                return
            }
            if !completed {
                didFail = true
                onLoadCompleted?(false)
            }
        }
    }

}
