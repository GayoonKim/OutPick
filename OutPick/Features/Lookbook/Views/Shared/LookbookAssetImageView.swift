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
                .fill(.gray.opacity(0.15))

            if let uiImage {
                GeometryReader { geo in
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else if isLoading {
                ProgressView()
                    .tint(.black)
            } else {
                Image(systemName: didFail ? "exclamationmark.triangle" : "photo")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: loadKey) {
            await loadImage()
        }
    }

    private var loadKey: String {
        [
            primaryPath,
            secondaryPath,
            remoteURL?.absoluteString,
            sourcePageURL?.absoluteString
        ]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    private func loadImage() async {
        uiImage = nil
        didFail = false
        isLoading = true
        defer { isLoading = false }

        for path in storagePaths {
            do {
                uiImage = try await brandImageCache.loadImage(
                    path: path,
                    maxBytes: maxBytes
                )
                onLoadCompleted?(true)
                return
            } catch {
                continue
            }
        }

        guard let remoteURL else {
            didFail = true
            onLoadCompleted?(false)
            return
        }

        var request = URLRequest(url: remoteURL)
        request.setValue(
            "OutPick/1.0 (iOS; lookbook asset preview)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let sourcePageURL {
            request.setValue(
                sourcePageURL.absoluteString,
                forHTTPHeaderField: "Referer"
            )
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode),
                let image = UIImage(data: data)
            else {
                didFail = true
                onLoadCompleted?(false)
                return
            }

            uiImage = image
            onLoadCompleted?(true)
        } catch {
            didFail = true
            onLoadCompleted?(false)
        }
    }

    private var storagePaths: [String] {
        var paths: [String] = []

        if let primaryPath,
           primaryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            paths.append(primaryPath)
        }

        if let secondaryPath,
           secondaryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           paths.contains(secondaryPath) == false {
            paths.append(secondaryPath)
        }

        return paths
    }
}
