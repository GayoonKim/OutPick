import SwiftUI
import UIKit

struct InterestedStyleBrandCardView: View {
    let brand: Brand
    let brandImageCache: any BrandImageCacheProtocol

    @State private var image: UIImage?
    @State private var loadFailed = false

    private let cardWidth: CGFloat = 168
    private let imageHeight: CGFloat = 190
    private let maxLogoBytes = 1 * 1024 * 1024

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            imageContent
                .frame(width: cardWidth, height: imageHeight)
                .background(OutPickTheme.SwiftUIColor.backgroundRaised)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(brand.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                .lineLimit(1)

            if let englishName = brand.englishName, englishName.isEmpty == false {
                Text(englishName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .lineLimit(1)
            }

            Label("\(brand.metrics.likeCount)", systemImage: "heart.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .frame(width: cardWidth, alignment: .leading)
        .task(id: logoLoadKey) {
            await loadImage()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lookbook.interest.brand.card")
    }

    @ViewBuilder
    private var imageContent: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: cardWidth, height: imageHeight, alignment: .top)
                .clipped()
        } else {
            Rectangle()
                .fill(OutPickTheme.SwiftUIColor.backgroundRaised)
                .overlay {
                    Image(systemName: loadFailed ? "exclamationmark.triangle" : "photo")
                        .foregroundStyle(
                            loadFailed
                                ? OutPickTheme.SwiftUIColor.warning
                                : OutPickTheme.SwiftUIColor.iconSecondary
                        )
                }
        }
    }

    @MainActor
    private func loadImage() async {
        image = nil
        loadFailed = false
        guard let path = brand.listLogoPath, path.isEmpty == false else { return }

        do {
            image = try await brandImageCache.loadImage(
                path: path,
                maxBytes: maxLogoBytes
            )
        } catch {
            loadFailed = true
        }
    }

    private var logoLoadKey: String {
        "\(brand.listLogoPath ?? "__empty__")|\(brand.updatedAt.timeIntervalSince1970)"
    }
}
