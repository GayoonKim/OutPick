import SwiftUI
import UIKit

struct LookbookRemotePreviewImageView: View {
    let request: LookbookRemotePreviewImageRequest
    let imageLoader: any LookbookRemotePreviewImageLoading
    let maxBytes: Int

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var didFail = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(OutPickTheme.SwiftUIColor.surfaceElevated)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
                    .tint(OutPickTheme.SwiftUIColor.accent)
            } else {
                Image(systemName: didFail ? "exclamationmark.triangle" : "photo")
                    .foregroundStyle(
                        didFail
                            ? OutPickTheme.SwiftUIColor.warning
                            : OutPickTheme.SwiftUIColor.iconSecondary
                    )
            }
        }
        .clipped()
        .task(id: loadKey) {
            await load()
        }
    }

    private var loadKey: String {
        [
            request.remoteURL.absoluteString,
            request.sourcePageURL?.absoluteString ?? "",
            String(maxBytes)
        ].joined(separator: "|")
    }

    private func load() async {
        isLoading = true
        didFail = false
        defer { isLoading = false }

        do {
            image = try await imageLoader.loadImage(
                request: request,
                maxBytes: maxBytes
            )
        } catch is CancellationError {
            return
        } catch {
            image = nil
            didFail = true
        }
    }
}
