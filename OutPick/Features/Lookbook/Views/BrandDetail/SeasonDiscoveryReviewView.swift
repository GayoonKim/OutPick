import SwiftUI

struct SeasonDiscoveryReviewView: View {
    @StateObject private var viewModel: SeasonDiscoveryReviewViewModel
    private let onBack: () -> Void

    init(
        viewModel: SeasonDiscoveryReviewViewModel,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onBack = onBack
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.candidates.isEmpty {
                ProgressView("검토할 시즌 후보를 불러오는 중입니다.")
                    .tint(OutPickTheme.SwiftUIColor.accent)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        Text("자동으로 기존 시즌과 연결할 수 없는 후보입니다. 각 후보의 처리 방법을 선택해주세요.")
                            .font(.footnote)
                            .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(viewModel.candidates) { candidate in
                            candidateCard(candidate)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
        .lookbookNavigationBar(
            title: "시즌 후보 검토",
            showsBackButton: true,
            onBack: onBack
        )
        .task {
            await viewModel.load()
        }
        .appToast(message: viewModel.errorMessage) {
            viewModel.clearError()
        }
    }

    private func candidateCard(
        _ candidate: SeasonDiscoveryReviewCandidate
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(candidate.title)
                .font(.headline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

            Text(candidate.seasonURL)
                .font(.caption)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                .lineLimit(2)

            Text(reviewReason(candidate.resolution))
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.warning)

            HStack(spacing: 8) {
                Menu("기존 시즌 연결") {
                    ForEach(viewModel.seasons) { season in
                        Button(season.displayTitle) {
                            Task { await viewModel.connect(candidate, to: season) }
                        }
                    }
                }
                .disabled(
                    viewModel.seasons.isEmpty ||
                    viewModel.resolvingCandidateID != nil
                )

                Button("새 시즌 유지") {
                    Task { await viewModel.keepAsNew(candidate) }
                }

                Button("후보 제외", role: .destructive) {
                    Task { await viewModel.reject(candidate) }
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .disabled(viewModel.resolvingCandidateID != nil)

            if viewModel.resolvingCandidateID == candidate.id {
                ProgressView("저장 중입니다.")
                    .font(.caption)
                    .tint(OutPickTheme.SwiftUIColor.accent)
            }
        }
        .padding(16)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
        )
    }

    private func reviewReason(_ resolution: String) -> String {
        switch resolution {
        case "awaitingReviewConflictingMatch":
            return "URL과 시즌명이 서로 다른 기존 시즌을 가리킵니다."
        case "awaitingReviewDuplicateConvergence":
            return "여러 후보가 같은 기존 시즌으로 판단됐습니다."
        default:
            return "시즌명이 모호하거나 일치하는 기존 시즌이 여러 개입니다."
        }
    }
}
