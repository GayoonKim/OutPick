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
                ProgressView("검토 정보를 불러오는 중입니다.")
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
                candidateGrid(review)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("추출 이미지 \(review.candidates.count)개")
                .font(.headline)
            if let expected = review.expectedCandidateCounts.max() {
                Text("페이지가 확인한 예상 수량: \(expected)개")
                    .font(.subheadline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }
            ForEach(review.qualityReasons, id: \.self) { reason in
                Text(reasonText(reason))
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.warning)
            }
        }
    }

    private func candidateGrid(_ review: LookbookExtractionReview) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            ForEach(
                Array(review.candidates.enumerated()),
                id: \.element.candidateKey
            ) { index, candidate in
                Button {
                    viewModel.toggle(candidateKey: candidate.candidateKey)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        LookbookRemotePreviewImageView(
                            request: previewRequest(url: candidate.sourceURL),
                            imageLoader: imageLoader,
                            maxBytes: previewMaxBytes
                        )
                        .frame(height: 210)
                        Image(
                            systemName: viewModel.excludedCandidateKeys.contains(
                                candidate.candidateKey
                            ) ? "xmark.circle.fill" : "checkmark.circle.fill"
                        )
                        .font(.title2)
                        .foregroundStyle(
                            viewModel.excludedCandidateKeys.contains(candidate.candidateKey)
                                ? OutPickTheme.SwiftUIColor.warning
                                : OutPickTheme.SwiftUIColor.success
                        )
                        .padding(8)
                    }
                }
                .buttonStyle(.plain)
                .onAppear {
                    schedulePrefetch(
                        review: review,
                        startingAt: index + 1
                    )
                }
            }
        }
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
        VStack(spacing: 12) {
            Button {
                Task { await viewModel.approve() }
            } label: {
                Text(
                    viewModel.excludedCandidateKeys.isEmpty
                        ? "정상 승인"
                        : "선택한 오탐 제외 후 승인"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                viewModel.isSubmitting ||
                viewModel.excludedCandidateKeys.count == review.candidates.count
            )

            TextField(
                "예상 이미지 수 (선택)",
                text: $viewModel.expectedCandidateCountText
            )
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            TextField("메모 (선택)", text: $viewModel.note)
                .textFieldStyle(.roundedBorder)
            Button("이미지 부족 보고") {
                Task { await viewModel.reportInsufficientImages() }
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isSubmitting)
        }
    }

    private func correctionActions(_ review: LookbookExtractionReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("이미지 부족으로 materialization이 중지되었습니다.")
                .font(.subheadline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.warning)
            if review.canReanalyze {
                Button("같은 작업 다시 분석") {
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
        default:
            return "추출 결과를 확인해 주세요."
        }
    }
}
