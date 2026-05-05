//
//  PostImagePreviewView.swift
//  OutPick
//
//  Created by Codex on 5/5/26.
//

import SwiftUI
import UIKit

struct PostImagePreviewView: View {
    let previewPath: String?
    let originalPath: String?
    let remoteURL: URL?
    let sourcePageURL: URL?
    let brandImageCache: any BrandImageCacheProtocol

    @Environment(\.dismiss) private var dismiss

    @State private var uiImage: UIImage?
    @State private var isLoadingPreview: Bool = false
    @State private var isLoadingOriginal: Bool = false
    @State private var didFail: Bool = false
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    private let previewMaxBytes = 1_500_000
    private let originalMaxBytes = 12_000_000
    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            imageContent

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.48))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.trailing, 18)
        }
        .task(id: loadKey) {
            await loadPreviewThenOriginal()
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let uiImage {
            Image(uiImage: uiImage)
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
                            scale = 1
                            baseScale = 1
                            offset = .zero
                            baseOffset = .zero
                        } else {
                            scale = 2
                            baseScale = 2
                        }
                    }
                }
        } else if isLoadingPreview || isLoadingOriginal {
            ProgressView()
                .tint(.white)
        } else {
            Image(systemName: didFail ? "exclamationmark.triangle" : "photo")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.72))
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
                baseOffset = offset
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
                baseScale = scale
            }
    }

    private var loadKey: String {
        [
            previewPath,
            originalPath,
            remoteURL?.absoluteString,
            sourcePageURL?.absoluteString
        ]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    private func loadPreviewThenOriginal() async {
        uiImage = nil
        didFail = false

        if let preview = await loadPreviewImage() {
            uiImage = preview
        }

        if let original = await loadOriginalImage() {
            uiImage = original
            didFail = false
            return
        }

        didFail = uiImage == nil
    }

    private func loadPreviewImage() async -> UIImage? {
        guard let previewPath = normalized(previewPath) else { return nil }

        isLoadingPreview = true
        defer { isLoadingPreview = false }

        return try? await brandImageCache.loadImage(
            path: previewPath,
            maxBytes: previewMaxBytes
        )
    }

    private func loadOriginalImage() async -> UIImage? {
        isLoadingOriginal = true
        defer { isLoadingOriginal = false }

        if let originalPath = normalized(originalPath),
           originalPath != normalized(previewPath),
           let image = try? await brandImageCache.loadImage(
            path: originalPath,
            maxBytes: originalMaxBytes
           ) {
            return image
        }

        return await loadRemoteOriginalImage()
    }

    private func loadRemoteOriginalImage() async -> UIImage? {
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
                data.count <= originalMaxBytes,
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
