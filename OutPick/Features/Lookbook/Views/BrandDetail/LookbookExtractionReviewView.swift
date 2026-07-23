import SwiftUI

struct LookbookExtractionReviewView: View {
    @StateObject private var viewModel: LookbookExtractionReviewViewModel
    @State private var scheduledPrefetchKeys = Set<String>()
    private let imageLoader: any LookbookRemotePreviewImageLoading
    private let onBack: () -> Void
    private let previewMaxBytes = 16 * 1024 * 1024
    private let prefetchWindowSize = 8

    init(
        viewModel: LookbookExtractionReviewViewModel,
        imageLoader: any LookbookRemotePreviewImageLoading,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.imageLoader = imageLoader
        self.onBack = onBack
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.review == nil {
                VStack(spacing: 14) {
                    Text("검토 정보를 불러오는 중입니다.")
                        .font(.subheadline)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)

                    ProgressView()
                        .tint(OutPickTheme.SwiftUIColor.accent)
                        .controlSize(.large)
                }
            } else if let review = viewModel.review {
                reviewContent(review)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                    Text("검토 정보를 표시할 수 없습니다")
                        .font(.headline)
                }
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
        .lookbookNavigationBar(
            title: "추출 결과 검토",
            showsBackButton: true,
            onBack: onBack
        )
        .task { await viewModel.load() }
        .appToast(message: viewModel.errorMessage) {
            viewModel.clearError()
        }
    }

    private func reviewContent(_ review: LookbookExtractionReview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary(review)
                candidateCarousel(review)
                if review.isCorrectionRequired {
                    correctionActions(review)
                } else {
                    reviewActions(review)
                }
            }
            .padding(20)
        }
        .onAppear {
            schedulePrefetch(review: review, startingAt: 0)
        }
    }

    private func summary(_ review: LookbookExtractionReview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(summaryTitle(review))
                .font(.title3.weight(.semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

            HStack(spacing: 10) {
                countCard(
                    title: "예상",
                    value: review.expectedCandidateCount.map { "\($0)개" } ?? "알 수 없음"
                )
                countCard(title: "발견", value: "\(review.candidates.count)개")
            }

            ForEach(visibleQualityReasons(review), id: \.self) { reason in
                Text(reasonText(reason))
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.warning)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(OutPickTheme.SwiftUIColor.surfaceBase)
        )
    }

    private func countCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(OutPickTheme.SwiftUIColor.surfaceElevated)
        )
    }

    private func candidateCarousel(_ review: LookbookExtractionReview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("추출된 이미지")
                .font(.headline)
            if review.allowsCandidateExclusion {
                Text("불필요한 이미지는 눌러서 제외할 수 있어요.")
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(
                        Array(review.candidates.enumerated()),
                        id: \.element.candidateKey
                    ) { index, candidate in
                        Button {
                            viewModel.toggle(candidateKey: candidate.candidateKey)
                        } label: {
                            candidateCard(
                                review: review,
                                candidate: candidate,
                                index: index
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!review.allowsCandidateExclusion)
                        .onAppear {
                            schedulePrefetch(
                                review: review,
                                startingAt: index + 1
                            )
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func candidateCard(
        review: LookbookExtractionReview,
        candidate: LookbookExtractionReviewCandidate,
        index: Int
    ) -> some View {
        let isExcluded = viewModel.excludedCandidateKeys.contains(
            candidate.candidateKey
        )
        return ZStack(alignment: .topTrailing) {
            LookbookRemotePreviewImageView(
                request: previewRequest(url: candidate.sourceURL),
                imageLoader: imageLoader,
                maxBytes: previewMaxBytes
            )
            .frame(width: 168, height: 224)
            .opacity(isExcluded ? 0.48 : 1)

            if review.allowsCandidateExclusion {
                Image(
                    systemName: isExcluded
                        ? "xmark.circle.fill"
                        : "checkmark.circle.fill"
                )
                .font(.title2)
                .foregroundStyle(
                    isExcluded
                        ? OutPickTheme.SwiftUIColor.warning
                        : OutPickTheme.SwiftUIColor.success
                )
                .padding(8)
            }

            VStack {
                Spacer()
                HStack {
                    Text("\(index + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        Image(
                            systemName: isExcluded
                                ? "eye.slash.fill"
                                : "photo.fill"
                        )
                        .font(.caption2)
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(8)
                .background(.black.opacity(0.45))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isExcluded
                        ? OutPickTheme.SwiftUIColor.warning
                        : OutPickTheme.SwiftUIColor.borderSubtle,
                    lineWidth: isExcluded ? 2 : 1
                )
        )
    }

    private func schedulePrefetch(
        review: LookbookExtractionReview,
        startingAt index: Int
    ) {
        guard index < review.candidates.count else { return }
        let upperBound = min(index + prefetchWindowSize, review.candidates.count)
        let candidates = review.candidates[index..<upperBound].filter {
            scheduledPrefetchKeys.contains($0.candidateKey) == false
        }
        guard !candidates.isEmpty else { return }
        scheduledPrefetchKeys.formUnion(candidates.map(\.candidateKey))
        let requests = candidates.map {
            previewRequest(url: $0.sourceURL)
        }
        Task {
            await imageLoader.prefetch(
                requests: requests,
                maxBytes: previewMaxBytes,
                concurrency: 4
            )
        }
    }

    private func previewRequest(
        url: URL
    ) -> LookbookRemotePreviewImageRequest {
        LookbookRemotePreviewImageRequest(
            remoteURL: url,
            sourcePageURL: nil
        )
    }

    private func reviewActions(_ review: LookbookExtractionReview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if review.allowsApproval {
                Button {
                    Task { await viewModel.approve() }
                } label: {
                    Text("승인")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    viewModel.isSubmitting ||
                    viewModel.excludedCandidateKeys.count == review.candidates.count
                )
            }

            if review.showsInsufficientImagesForm {
                insufficientImagesForm(review)
            }

            if review.hasContentIntegrityIssue {
                integrityIssueCard()
            }
        }
    }

    private func insufficientImagesForm(
        _ review: LookbookExtractionReview
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(insufficientTitle(review))
                    .font(.headline)
                Text(insufficientDescription(review))
                    .font(.subheadline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("원본의 전체 이미지 수")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                TextField("예: 24", text: $viewModel.expectedCandidateCountText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("참고 내용")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                ZStack(alignment: .topLeading) {
                    if viewModel.note.isEmpty {
                        Text("빠진 구간이나 원본 페이지 상태를 적어 주세요. (선택)")
                            .font(.subheadline)
                            .foregroundStyle(OutPickTheme.SwiftUIColor.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                    TextEditor(text: $viewModel.note)
                        .frame(minHeight: 96)
                        .padding(.horizontal, 8)
                        .background(Color.clear)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(OutPickTheme.SwiftUIColor.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            OutPickTheme.SwiftUIColor.borderSubtle,
                            lineWidth: 1
                        )
                )
            }

            Button("누락된 이미지 알리기") {
                Task { await viewModel.reportInsufficientImages() }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(
                viewModel.isSubmitting ||
                !viewModel.canReportInsufficientImages
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(OutPickTheme.SwiftUIColor.surfaceBase)
        )
    }

    private func integrityIssueCard() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("이미지 확인을 완료하지 못했어요")
                .font(.headline)
            Text("일부 이미지의 중복 여부를 확인하지 못해 지금은 승인할 수 없습니다.")
                .font(.subheadline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(OutPickTheme.SwiftUIColor.surfaceBase)
        )
    }

    private func correctionActions(_ review: LookbookExtractionReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("누락된 이미지가 있어 등록을 잠시 멈췄어요.")
                .font(.subheadline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.warning)
            if review.canReanalyze {
                Button("이미지 다시 찾기") {
                    Task { await viewModel.reanalyze() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSubmitting)
            }
        }
    }

    private func reasonText(_ reason: String) -> String {
        switch reason {
        case "programmatic_gallery_requires_review":
            return "스크립트로 생성된 갤러리 구조를 처음 확인합니다."
        case "expected_count_mismatch":
            return "페이지가 선언한 이미지 수와 추출 결과가 다릅니다."
        case "content_hash_incomplete":
            return "일부 이미지의 중복 확인을 완료하지 못했습니다."
        case "raw_candidate_drop":
            return "원본 후보에서 많은 이미지가 필터링되었습니다."
        case "expected_count_unverified":
            return "원본의 전체 이미지 수를 확인해 주세요."
        default:
            return "추출 결과를 확인해 주세요."
        }
    }

    private func visibleQualityReasons(
        _ review: LookbookExtractionReview
    ) -> [String] {
        review.qualityReasons.filter {
            $0 != "raw_candidate_drop" &&
            $0 != "programmatic_gallery_requires_review"
        }
    }

    private func summaryTitle(_ review: LookbookExtractionReview) -> String {
        switch review.candidateCountComparison {
        case .unknown:
            return "이미지 수를 확인해 주세요"
        case .matches:
            return "예상한 만큼 이미지를 찾았어요"
        case .extractedMore:
            return "예상보다 많은 이미지를 찾았어요"
        case .extractedFewer:
            return "예상보다 적은 이미지를 찾았어요"
        }
    }

    private func insufficientTitle(
        _ review: LookbookExtractionReview
    ) -> String {
        switch review.candidateCountComparison {
        case .unknown:
            return "원본 이미지 수를 알려주세요"
        case .extractedFewer:
            return "누락된 이미지가 있는 것 같아요"
        case .matches, .extractedMore:
            return "이미지 수를 확인해 주세요"
        }
    }

    private func insufficientDescription(
        _ review: LookbookExtractionReview
    ) -> String {
        switch review.candidateCountComparison {
        case let .extractedFewer(expected):
            return "원본은 \(expected)장으로 보이지만 \(review.candidates.count)장만 찾았습니다. 내용을 남기면 추출 규칙 개선에 활용됩니다."
        case .unknown:
            return "원본 페이지의 전체 이미지 수를 입력하면 누락 여부를 정확하게 기록할 수 있어요."
        case .matches, .extractedMore:
            return "원본 페이지와 비교한 결과를 남겨 주세요."
        }
    }
}
