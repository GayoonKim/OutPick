import SwiftUI

struct InterestedStyleBrandCardView: View {
    let brand: Brand
    let brandImageCache: any BrandImageCacheProtocol

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(brand.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                .lineLimit(2)
            if let englishName = brand.englishName, !englishName.isEmpty {
                Text(englishName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .lineLimit(2)
            }
            Label("\(brand.metrics.likeCount)", systemImage: "heart.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .frame(width: 136, alignment: .leading)
        .padding(16)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lookbook.interest.brand.card")
    }
}
