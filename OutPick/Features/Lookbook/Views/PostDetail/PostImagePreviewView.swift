//
//  PostImagePreviewView.swift
//  OutPick
//
//  Created by Codex on 5/5/26.
//

import SwiftUI
import UIKit

struct PostImagePreviewView: View {
    let initialImage: UIImage?
    let previewPath: String?
    let originalPath: String?
    let remoteURL: URL?
    let sourcePageURL: URL?
    let brandImageCache: any BrandImageCacheProtocol

    var body: some View {
        LookbookImageViewerView(
            initialImage: initialImage,
            previewPath: previewPath,
            originalPath: originalPath,
            remoteURL: remoteURL,
            sourcePageURL: sourcePageURL,
            brandImageCache: brandImageCache
        )
    }
}

extension PostImagePreviewView {
    init(
        previewPath: String?,
        originalPath: String?,
        remoteURL: URL?,
        sourcePageURL: URL?,
        brandImageCache: any BrandImageCacheProtocol
    ) {
        self.initialImage = nil
        self.previewPath = previewPath
        self.originalPath = originalPath
        self.remoteURL = remoteURL
        self.sourcePageURL = sourcePageURL
        self.brandImageCache = brandImageCache
    }
}

struct LookbookImageViewerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let initialImage: UIImage?
    let previewPath: String?
    let originalPath: String?
    let remoteURL: URL?
    let sourcePageURL: URL?
    let brandImageCache: any BrandImageCacheProtocol

    private let remoteOriginalKeyPrefix = "lookbook-remote-original://"

    func makeUIViewController(context: Context) -> SimpleImageViewerVC {
        SimpleImageViewerVC(
            pages: [
                ImageViewerPage(
                    initialImage: initialImage,
                    thumbnailPath: normalized(previewPath),
                    originalPath: viewerOriginalPath
                )
            ],
            startIndex: 0,
            cachedImageProvider: nil,
            loadImageProvider: { path, maxBytes in
                await loadImage(path: path, maxBytes: maxBytes)
            },
            photoLibrarySaver: DefaultPhotoLibrarySaver(),
            onClose: {
                dismiss()
            }
        )
    }

    func updateUIViewController(_ uiViewController: SimpleImageViewerVC, context: Context) {}

    private var viewerOriginalPath: String? {
        let preview = normalized(previewPath)
        if let original = normalized(originalPath), original != preview {
            return original
        }
        if remoteURL != nil {
            return remoteOriginalKey
        }
        return normalized(originalPath)
    }

    private var remoteOriginalKey: String? {
        remoteURL.map { remoteOriginalKeyPrefix + $0.absoluteString }
    }

    private func loadImage(path: String, maxBytes: Int) async -> UIImage? {
        if path == remoteOriginalKey {
            return await loadRemoteOriginalImage(maxBytes: maxBytes)
        }

        if let image = try? await brandImageCache.loadImage(path: path, maxBytes: maxBytes) {
            return image
        }

        if path == normalized(originalPath) {
            return await loadRemoteOriginalImage(maxBytes: maxBytes)
        }

        return nil
    }

    private func loadRemoteOriginalImage(maxBytes: Int) async -> UIImage? {
        guard let remoteURL else { return nil }

        var request = URLRequest(url: remoteURL)
        request.setValue(
            "OutPick/1.0 (iOS; lookbook original preview)",
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
                data.count <= maxBytes,
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode)
            else {
                return nil
            }

            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    private func normalized(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
