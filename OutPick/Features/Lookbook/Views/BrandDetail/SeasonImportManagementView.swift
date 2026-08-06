import SwiftUI

struct SeasonImportManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var brandAdminSessionStore: BrandAdminSessionStore
    @StateObject private var viewModel: SeasonImportManagementViewModel
    private let brand: Brand
    private let showsNavigationChrome: Bool
    private let onReview: (String) -> Void
    private let onRepair: (String, SeasonID) -> Void
    private let onSelectCandidates: () -> Void
    private let onDiscoveryReview: (SeasonCandidateDiscoveryResult) -> Void
    private let onUpdateSourceURL: () -> Void

    init(
        viewModel: SeasonImportManagementViewModel,
        brand: Brand,
        showsNavigationChrome: Bool = true,
        onReview: @escaping (String) -> Void = { _ in },
        onRepair: @escaping (String, SeasonID) -> Void = { _, _ in },
        onSelectCandidates: @escaping () -> Void = {},
        onDiscoveryReview: @escaping (SeasonCandidateDiscoveryResult) -> Void = { _ in },
        onUpdateSourceURL: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.brand = brand
        self.showsNavigationChrome = showsNavigationChrome
        self.onReview = onReview
        self.onRepair = onRepair
        self.onSelectCandidates = onSelectCandidates
        self.onDiscoveryReview = onDiscoveryReview
        self.onUpdateSourceURL = onUpdateSourceURL
    }

    var body: some View {
        Group {
            if showsNavigationChrome {
                NavigationView {
                    content
                        .navigationTitle("시즌 가져오기 현황")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("닫기") {
                                    dismiss()
                                }
                            }
                        }
                }
                .navigationViewStyle(StackNavigationViewStyle())
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                discoveryCard

                VStack(alignment: .leading, spacing: 10) {
                    Text("시즌 이미지 가져오기 현황")
                        .font(.headline)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                    if viewModel.isLoading && viewModel.jobs.isEmpty {
                        ProgressView("가져오기 현황을 불러오는 중입니다.")
                            .tint(OutPickTheme.SwiftUIColor.accent)
                            .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 18)
                    } else if viewModel.jobs.isEmpty {
                        Text("아직 이미지를 가져온 시즌이 없습니다.")
                            .font(.subheadline)
                            .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(OutPickTheme.SwiftUIColor.surfaceBase)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        ForEach(viewModel.jobs) { job in
                            jobRow(job)
                                .padding(14)
                                .background(OutPickTheme.SwiftUIColor.surfaceBase)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        }
                    }
                }
            }
            .padding(showsNavigationChrome ? 16 : 0)
        .refreshable {
            await viewModel.load()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OutPickTheme.SwiftUIColor.backgroundBase)
        .tint(OutPickTheme.SwiftUIColor.accent)
        .task {
            await viewModel.monitor()
        }
        .appToast(message: viewModel.presentedErrorMessage) {
            viewModel.clearError()
        }
    }

    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("시즌 목록 탐색")
                    .font(.headline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                Spacer()
                if let result = viewModel.discoveryResult {
                    Text(discoveryStatusText(result))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(discoveryStatusColor(result))
                }
            }

            if let result = viewModel.discoveryResult {
                discoveryResultContent(result)
            } else {
                Text("브랜드의 룩북 목록 URL에서 가져올 시즌을 찾습니다.")
                    .font(.subheadline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                discoveryButton("시즌 찾아오기 시작") {
                    await viewModel.requestDiscovery()
                }
                .disabled(!hasSourceURL || viewModel.isMutatingDiscovery)
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

    @ViewBuilder
    private func discoveryResultContent(
        _ result: SeasonCandidateDiscoveryResult
    ) -> some View {
        if result.status.isActive {
            activeDiscoveryContent(result)
        } else if result.candidateCount > 0 {
            Text(
                "발견 \(result.candidateCount)개 · 신규 \(result.newSeasonCandidateCount)개 · 기존 연결 \(result.matchedCandidateCount)개 · 검토 필요 \(result.reviewCandidateCount)개"
            )
            .font(.subheadline)
            .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        if let errorMessage = result.errorMessage, !errorMessage.isEmpty {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.warning)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let date = result.completedAt ?? result.requestedAt {
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textTertiary)
        }

        discoveryActions(result)
    }

    private func activeDiscoveryContent(
        _ result: SeasonCandidateDiscoveryResult
    ) -> some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(OutPickTheme.SwiftUIColor.accent)

            Text(discoveryPhaseText(result.phase))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

            Text("잠시만 기다려 주세요")
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .center)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func discoveryActions(_ result: SeasonCandidateDiscoveryResult) -> some View {
        switch result.status {
        case .queued, .dispatching, .running:
            discoveryButton("작업 취소", prominent: false) {
                await viewModel.cancelDiscovery()
            }
        case .awaitingReview:
            if result.newSeasonCandidateCount > 0 {
                discoveryButton("검토 불필요 시즌 선택") {
                    onSelectCandidates()
                }
            }
            discoveryButton("시즌 후보 검토") {
                onDiscoveryReview(result)
            }
        case .correctionRequired:
            Text(correctionRequiredMessage(result))
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if result.canRetryExtractionAfterFix &&
                brandAdminSessionStore.isTotalAdmin {
                discoveryButton("다시 가져오기") {
                    await viewModel.retryDiscoveryAfterExtractionFix()
                }
            } else if result.extractionIssueUserState == .wontFix &&
                        canUpdateSourceURL(for: result) {
                discoveryButton("룩북 목록 URL 수정", prominent: false) {
                    onUpdateSourceURL()
                }
            }
        case .failed:
            if result.retryable || result.recommendedAction == "retry" {
                discoveryButton("다시 시도") {
                    await viewModel.retryDiscovery()
                }
            } else if result.recommendedAction == "updateSourceURL" {
                discoveryButton("룩북 목록 URL 수정") {
                    onUpdateSourceURL()
                }
            }
        case .succeeded:
            if result.newSeasonCandidateCount > 0 {
                discoveryButton("신규 시즌 선택") {
                    onSelectCandidates()
                }
            }
            discoveryButton("다시 찾아오기", prominent: false) {
                await viewModel.requestDiscovery()
            }
        case .cancelled, .superseded, .unknown:
            discoveryButton("시즌 다시 찾아오기") {
                await viewModel.requestDiscovery()
            }
        }
    }

    private func discoveryButton(
        _ title: String,
        prominent: Bool = true,
        action: @escaping () async -> Void
    ) -> some View {
        Group {
            if prominent {
                Button {
                    Task { await action() }
                } label: {
                    discoveryButtonLabel(title)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    Task { await action() }
                } label: {
                    discoveryButtonLabel(title)
                }
                .buttonStyle(.bordered)
            }
        }
        .disabled(viewModel.isMutatingDiscovery)
    }

    private func discoveryButtonLabel(_ title: String) -> some View {
        HStack {
            Spacer()
            if viewModel.isMutatingDiscovery {
                ProgressView()
            } else {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
        }
    }

    private var hasSourceURL: Bool {
        guard let value = brand.lookbookArchiveURL else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func discoveryStatusText(_ result: SeasonCandidateDiscoveryResult) -> String {
        switch result.status {
        case .queued, .dispatching: return "대기 중"
        case .running: return "탐색 중"
        case .succeeded: return "완료"
        case .awaitingReview: return "검토 필요"
        case .correctionRequired:
            switch result.extractionIssueUserState {
            case .waiting: return "개선 대기 중"
            case .processing: return "개선 처리 중"
            case .retryReady: return "다시 가져오기 가능"
            case .wontFix: return "추가 작업 필요"
            case .unavailable: return "상태 확인 필요"
            }
        case .failed: return "실패"
        case .cancelled: return "취소됨"
        case .superseded: return "새 요청으로 대체됨"
        case .unknown: return "상태 확인 필요"
        }
    }

    private func discoveryStatusColor(_ result: SeasonCandidateDiscoveryResult) -> Color {
        if result.extractionIssueUserState == .retryReady {
            return OutPickTheme.SwiftUIColor.success
        }
        if result.extractionIssueUserState == .processing {
            return OutPickTheme.SwiftUIColor.accent
        }
        switch result.status {
        case .succeeded: return OutPickTheme.SwiftUIColor.success
        case .failed, .correctionRequired: return OutPickTheme.SwiftUIColor.warning
        case .awaitingReview: return OutPickTheme.SwiftUIColor.accent
        default: return OutPickTheme.SwiftUIColor.textSecondary
        }
    }

    private func correctionRequiredMessage(
        _ result: SeasonCandidateDiscoveryResult
    ) -> String {
        switch result.extractionIssueUserState {
        case .waiting:
            return "시즌 목록을 가져오지 못했어요. 확인이 필요해요."
        case .processing:
            return "시즌 목록을 다시 가져올 수 있도록 확인하고 있어요."
        case .retryReady:
            if brandAdminSessionStore.isTotalAdmin {
                return "시즌 목록을 다시 가져올 수 있어요."
            }
            return "시즌 목록을 다시 가져올 수 있어요. 총 관리자에게 요청해 주세요."
        case .wontFix:
            return wontFixMessage(result.extractionIssueWontFixReason)
        case .unavailable:
            return "현재 상태를 확인할 수 없어요."
        }
    }

    private func wontFixMessage(_ reason: String?) -> String {
        switch reason {
        case "sourceUnavailable":
            return "원본 페이지를 확인할 수 없어요. 룩북 목록 URL을 확인해 주세요."
        case "accessRestricted":
            return "원본 페이지 접근이 제한되어 자동으로 다시 가져올 수 없어요."
        case "ambiguousGroundTruth":
            return "정확한 시즌 목록을 판단하기 어려워 수동 확인이 필요해요."
        case "unsupportedStructure":
            return "현재 지원하지 않는 페이지 구조예요."
        case "lowOperationalValue":
            return "자동 추출 개선 대상에서 제외됐어요."
        default:
            return "자동으로 다시 가져올 수 없어 원본 정보를 확인해 주세요."
        }
    }

    private func canUpdateSourceURL(
        for result: SeasonCandidateDiscoveryResult
    ) -> Bool {
        result.extractionIssueWontFixReason == "sourceUnavailable" ||
            result.extractionIssueWontFixReason == "accessRestricted"
    }

    private func discoveryPhaseText(_ phase: String?) -> String {
        switch phase {
        case "dispatching":
            return "시즌 목록을 준비하고 있어요"
        case "fetching", "rendering":
            return "룩북 페이지를 불러오고 있어요"
        case "parsing", "matchingExistingSeasons", "publishing":
            return "시즌 목록을 확인하고 있어요"
        default:
            return "시즌 목록을 찾고 있어요"
        }
    }

    private func jobRow(_ job: SeasonImportJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(jobTitle(job))
                    .font(.headline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                Spacer()
                Text(statusText(job.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(job.status))
            }

            Text(phaseText(job.phase))
                .font(.subheadline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)

            if job.assetCompletedCount > 0 || job.assetFailedCount > 0 {
                Text(
                    "이미지 \(job.assetCompletedCount + job.assetFailedCount)개 중 \(job.assetCompletedCount)개 완료, \(job.assetFailedCount)개 실패"
                )
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }

            if job.canRetryAssets || viewModel.hasActiveRetry(for: job) {
                HStack {
                    Spacer()
                    Button {
                        Task {
                            await viewModel.retryAssets(for: job)
                        }
                    } label: {
                        if viewModel.retryingJobID == job.id {
                            ProgressView()
                                .tint(OutPickTheme.SwiftUIColor.accent)
                                .frame(width: 44)
                        } else if viewModel.hasActiveRetry(for: job) {
                            Text("재시도 중")
                        } else {
                            Text("재시도")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(
                        viewModel.retryingJobID != nil ||
                        viewModel.hasActiveRetry(for: job)
                    )
                }
            }

            if job.needsExtractionReview {
                HStack {
                    Spacer()
                    Button("이미지 추출 검토") {
                        onReview(job.id)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if let seasonID = job.targetSeasonID,
               job.canRequestSeasonRepair || job.needsSeasonRepairPreview {
                HStack {
                    Spacer()
                    Button(
                        job.needsSeasonRepairPreview
                            ? "변경 검토"
                            : "원본과 다시 비교"
                    ) {
                        onRepair(job.id, seasonID)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func jobTitle(_ job: SeasonImportJob) -> String {
        job.displayTitle
    }

    private func statusText(_ status: SeasonImportJobStatus) -> String {
        switch status {
        case .queued: return "대기 중"
        case .processing: return "처리 중"
        case .awaitingReview: return "검토 필요"
        case .succeeded: return "완료"
        case .partialFailed: return "일부 실패"
        case .failed: return "실패"
        case .cancelled: return "취소"
        }
    }

    private func phaseText(_ phase: SeasonImportJobPhase) -> String {
        switch phase {
        case .dispatching: return "작업 요청을 전달하고 있습니다."
        case .parsing: return "시즌 페이지를 분석하고 있습니다."
        case .reviewing: return "추출 결과의 관리자 검토가 필요합니다."
        case .materializing: return "시즌과 포스트를 만들고 있습니다."
        case .syncingAssets: return "이미지를 저장하고 있습니다."
        case .completed: return "작업이 종료되었습니다."
        }
    }

    private func statusColor(_ status: SeasonImportJobStatus) -> Color {
        switch status {
        case .succeeded:
            return OutPickTheme.SwiftUIColor.success
        case .partialFailed, .failed:
            return OutPickTheme.SwiftUIColor.warning
        case .cancelled:
            return OutPickTheme.SwiftUIColor.textSecondary
        case .queued, .processing, .awaitingReview:
            return OutPickTheme.SwiftUIColor.accent
        }
    }
}

private extension View {
    @ViewBuilder
    func outpickHiddenScrollContentBackground() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
