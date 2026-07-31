import SwiftUI

struct InterestedStyleBrandSectionView: View {
    let phase: LookbookHomeViewModel.InterestPhase
    let brands: [Brand]
    let brandImageCache: any BrandImageCacheProtocol
    let onSelectBrand: (Brand) -> Void
    let onShowAll: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
        }
        .padding(.vertical, 18)
        .accessibilityIdentifier("lookbook.interest.section")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("관심 스타일")
                    .font(.system(size: 25, weight: .bold, design: .serif))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                Text("내 취향과 가까운 브랜드")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }

            Spacer()

            if phase == .ready, brands.isEmpty == false {
                Button("전체 보기", action: onShowAll)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .tint(OutPickTheme.SwiftUIColor.accent)
                Text("취향에 맞는 브랜드를 찾고 있어요")
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 92)

        case .ready:
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(brands) { brand in
                        Button {
                            onSelectBrand(brand)
                        } label: {
                            InterestedStyleBrandCardView(
                                brand: brand,
                                brandImageCache: brandImageCache
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

        case .unconfigured:
            EmptyView()

        case .empty:
            emptyState

        case .failed(let message):
            statusCard(
                title: "관심 스타일을 불러오지 못했어요",
                message: message,
                primaryTitle: "다시 시도",
                primaryAction: onRetry,
                secondaryTitle: nil,
                secondaryAction: nil
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("아직 관심 스타일에 맞는 브랜드가 없어요")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("브랜드 검색에서 원하는 브랜드를 찾아보세요")
                .font(.system(size: 13))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
        }
        .padding(.horizontal, 20)
    }

    private func statusCard(
        title: String,
        message: String,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String?,
        secondaryAction: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(primaryTitle, action: primaryAction)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(OutPickTheme.SwiftUIColor.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(OutPickTheme.SwiftUIColor.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
        }
        .padding(.horizontal, 20)
    }
}
