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
        .accessibilityElement(children: .contain)
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
            loadingState

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
            Text("마이페이지에서 관심 스타일을 등록해 보세요")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(OutPickTheme.SwiftUIColor.surfaceBase)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 20)

        case .empty:
            emptyState

        case .failed(let message):
            failureState(message: message)
        }
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(OutPickTheme.SwiftUIColor.accent)
            Text("취향에 맞는 브랜드를 찾고 있어요")
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .padding(18)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lookbook.interest.loading")
        .padding(.horizontal, 20)
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

    private func failureState(message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)

            Button("다시 시도", action: onRetry)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(OutPickTheme.SwiftUIColor.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .buttonStyle(.plain)
                .accessibilityIdentifier("lookbook.interest.retry")
        }
        .frame(maxWidth: .infinity, minHeight: 96)
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
