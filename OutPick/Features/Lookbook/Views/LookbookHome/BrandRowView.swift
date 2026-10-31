import SwiftUI

struct BrandRowView: View {
    let brand: Brand
    let brandImageCache: any BrandImageCacheProtocol

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(brand.name)
                .font(.headline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
            if let englishName = brand.englishName, !englishName.isEmpty {
                Text(englishName)
                    .font(.subheadline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }
            Label("\(brand.metrics.likeCount)", systemImage: "heart.fill")
                .font(.subheadline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(OutPickTheme.SwiftUIColor.borderSubtle))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lookbook.brand.card")
    }
}
