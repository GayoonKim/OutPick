//
//  CreateBrandCandidateSelectionView.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import SwiftUI

struct CreateBrandCandidateSelectionView: View {
    private enum ImportProgressPhase: Equatable {
        case selecting
        case extracting
        case completed
    }

    private enum CandidateImportStatus {
        case processing
        case succeeded
        case failed
    }

    let createdBrand: CreateBrandViewModel.CreatedBrand
    let loadSelectableSeasonCandidatesUseCase: any LoadSelectableSeasonCandidatesUseCaseProtocol
    let refreshSeasonCandidatesUseCase: (any SeasonCandidateDiscoveryRepositoryProtocol)?
    let startSeasonImportExtractionUseCase: any StartSeasonImportExtractionUseCaseProtocol
    let discoveryErrorMessage: String?
    let emptySelectionButtonTitle: String
    let onToolbarCloseVisibilityChange: (Bool) -> Void
    let onComplete: () -> Void

    @State private var selectedCandidateIDs: Set<String> = []
    @State private var candidates: [SeasonCandidate] = []
    @State private var importProgressPhase: ImportProgressPhase = .selecting
    @State private var extractionCandidateIDs: [String] = []
    @State private var extractionTotalCount: Int = 0
    @State private var extractionCompletedCount: Int = 0
    @State private var extractionFailedCount: Int = 0
    @State private var extractionProgressItems: [SeasonImportExtractionProgress.Item] = []
    @State private var failedToStartCandidateIDs: Set<String> = []
    @State private var retryingCandidateIDs: Set<String> = []
    @State private var progressPollingTask: Task<Void, Never>?
    @State private var submissionTask: Task<Void, Never>?
    @State private var isLoading: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var message: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                switch importProgressPhase {
                case .selecting:
                    headerSection
                    candidateListSection
                    submitButton
                case .extracting, .completed:
                    extractionProgressSection
                        .frame(maxWidth: .infinity, minHeight: 520, alignment: .center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
        .task {
            await loadCandidates()
        }
        .onDisappear {
            progressPollingTask?.cancel()
        }
        .onAppear {
            notifyToolbarCloseVisibility()
        }
        .onChange(of: importProgressPhase) { _ in
            notifyToolbarCloseVisibility()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(headerTitle)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

            Text(headerDescription)
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let discoveryErrorMessage {
                Text(discoveryErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var candidateListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("선택할 시즌")
                    .font(.headline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                Spacer()

                if isLoading {
                    ProgressView()
                        .tint(OutPickTheme.SwiftUIColor.accent)
                }
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if candidates.isEmpty == false {
                HStack(spacing: 10) {
                    Text("\(selectedCandidateIDs.count)/\(candidates.count)개 선택됨")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)

                    Spacer(minLength: 8)

                    Button {
                        selectAllCandidates()
                    } label: {
                        Text("모두 선택")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                    .background(
                        areAllCandidatesSelected
                            ? OutPickTheme.SwiftUIColor.surfaceElevated
                            : OutPickTheme.SwiftUIColor.accent
                    )
                    .clipShape(Capsule())
                    .disabled(areAllCandidatesSelected || isSubmitting)

                    Button {
                        deselectAllCandidates()
                    } label: {
                        Text("모두 해제")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .foregroundStyle(
                        selectedCandidateIDs.isEmpty
                            ? OutPickTheme.SwiftUIColor.textTertiary
                            : OutPickTheme.SwiftUIColor.accent
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                selectedCandidateIDs.isEmpty
                                    ? OutPickTheme.SwiftUIColor.borderSubtle
                                    : OutPickTheme.SwiftUIColor.accent,
                                lineWidth: 1
                            )
                    }
                    .disabled(selectedCandidateIDs.isEmpty || isSubmitting)
                }
            }

            if candidates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(isLoading ? "시즌을 불러오고 있습니다." : "더 가져올 시즌이 없습니다.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                    Text("지금 바로 가져올 수 있는 시즌이 없습니다.")
                        .font(.footnote)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OutPickTheme.SwiftUIColor.surfaceBase)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    ForEach(candidates) { candidate in
                        Button {
                            toggleSelection(candidateID: candidate.id)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                SeasonCandidateCoverView(
                                    coverImageURL: candidate.coverImageURL,
                                    sourceArchiveURL: candidate.sourceArchiveURL
                                )

                                Image(systemName: selectedCandidateIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(
                                        selectedCandidateIDs.contains(candidate.id)
                                            ? OutPickTheme.SwiftUIColor.accent
                                            : OutPickTheme.SwiftUIColor.iconSecondary
                                    )

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(candidate.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                                }

                                Spacer()
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                selectedCandidateIDs.contains(candidate.id)
                                    ? OutPickTheme.SwiftUIColor.accent.opacity(0.12)
                                    : OutPickTheme.SwiftUIColor.surfaceBase
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(
                                        selectedCandidateIDs.contains(candidate.id)
                                            ? OutPickTheme.SwiftUIColor.accent.opacity(0.45)
                                            : OutPickTheme.SwiftUIColor.borderSubtle,
                                        lineWidth: 1
                                    )
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var submitButton: some View {
        Button {
            submitSelection()
        } label: {
            HStack {
                Spacer()
                if isSubmitting {
                    ProgressView()
                        .tint(OutPickTheme.SwiftUIColor.backgroundBase)
                } else {
                    Text(primaryButtonTitle)
                        .font(.headline)
                }
                Spacer()
            }
            .padding(.vertical, 16)
            .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
            .background(OutPickTheme.SwiftUIColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .disabled(isSubmitting)
        .opacity(isSubmitting ? 0.55 : 1)
    }

    private var extractionProgressSection: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text(headerTitle)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(headerDescription)
                    .font(.subheadline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                if importProgressPhase == .extracting {
                    ProgressView()
                        .tint(OutPickTheme.SwiftUIColor.accent)

                    Text("준비 완료 \(extractionCompletedCount)/\(extractionTotalCount)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                        .multilineTextAlignment(.center)

                    progressCloseActionSection
                } else {
                    resultSummarySection
                    resultListSection
                    resultActionsSection
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var resultSummarySection: some View {
        VStack(spacing: 8) {
            Text("\(succeededCandidates.count)개 시즌을 불러왔습니다.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                .multilineTextAlignment(.center)

            if failedCandidates.isEmpty == false {
                Text("\(failedCandidates.count)개 시즌을 불러오지 못했습니다.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.warning)
                    .multilineTextAlignment(.center)

                Text("실패한 시즌은 다시 시도할 수 있습니다.")
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var resultListSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if succeededCandidates.isEmpty == false {
                resultGroup(
                    title: "성공",
                    candidates: succeededCandidates,
                    status: .succeeded
                )
            }

            if failedCandidates.isEmpty == false {
                resultGroup(
                    title: "실패",
                    candidates: failedCandidates,
                    status: .failed
                )
            }

            if processingCandidates.isEmpty == false {
                resultGroup(
                    title: "진행 중",
                    candidates: processingCandidates,
                    status: .processing
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resultActionsSection: some View {
        VStack(spacing: 10) {
            if failedCandidates.isEmpty == false {
                Button {
                    retryCandidates(failedCandidates)
                } label: {
                    Text("실패한 시즌 모두 재시도")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                .background(OutPickTheme.SwiftUIColor.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(isSubmitting || retryingCandidateIDs.isEmpty == false)
            }

            Button {
                onComplete()
            } label: {
                Text("닫기")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(OutPickTheme.SwiftUIColor.accent, lineWidth: 1)
            }
        }
    }

    private var progressCloseActionSection: some View {
        VStack(spacing: 10) {
            Button {
                onComplete()
            } label: {
                Text("닫기")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(OutPickTheme.SwiftUIColor.accent, lineWidth: 1)
            }
        }
        .padding(.top, 4)
    }

    private func resultGroup(
        title: String,
        candidates: [SeasonCandidate],
        status: CandidateImportStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)

            ForEach(candidates) { candidate in
                HStack(spacing: 10) {
                    Image(systemName: resultIconName(for: status))
                        .foregroundStyle(resultColor(for: status))

                    Text(candidate.title)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    if status == .failed {
                        Button {
                            retryCandidates([candidate])
                        } label: {
                            if retryingCandidateIDs.contains(candidate.id) {
                                ProgressView()
                                    .tint(OutPickTheme.SwiftUIColor.accent)
                            } else {
                                Text("재시도")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .disabled(
                            isSubmitting ||
                            retryingCandidateIDs.isEmpty == false ||
                            retryingCandidateIDs.contains(candidate.id)
                        )
                    }
                }
                .padding(12)
                .background(OutPickTheme.SwiftUIColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var headerTitle: String {
        switch importProgressPhase {
        case .selecting:
            return "가져올 시즌을 선택해주세요"
        case .extracting:
            return "시즌을 불러오는 중입니다"
        case .completed:
            return "시즌 불러오기 결과"
        }
    }

    private var headerDescription: String {
        switch importProgressPhase {
        case .selecting:
            return "새로 추가된 룩북을 확인한 뒤, 이미 처리 중이거나 가져온 시즌은 제외합니다."
        case .extracting:
            return "선택한 시즌의 사진을 가져오고 룩북 목록에 반영하고 있습니다."
        case .completed:
            return "시즌 불러오기 요청 결과를 확인하세요."
        }
    }

    private func notifyToolbarCloseVisibility() {
        onToolbarCloseVisibilityChange(importProgressPhase == .selecting)
    }

    private func toggleSelection(candidateID: String) {
        if selectedCandidateIDs.contains(candidateID) {
            selectedCandidateIDs.remove(candidateID)
        } else {
            selectedCandidateIDs.insert(candidateID)
        }
    }

    private var areAllCandidatesSelected: Bool {
        candidates.isEmpty == false && selectedCandidateIDs.count == candidates.count
    }

    private func selectAllCandidates() {
        selectedCandidateIDs = Set(candidates.map(\.id))
    }

    private func deselectAllCandidates() {
        selectedCandidateIDs.removeAll()
    }

    private var primaryButtonTitle: String {
        if selectedCandidateIDs.isEmpty {
            return emptySelectionButtonTitle
        }
        return "선택한 시즌 \(selectedCandidateIDs.count)개 가져오기"
    }

    @MainActor
    private func loadCandidates() async {
        isLoading = true
        message = nil
        defer { isLoading = false }

        do {
            if let refreshSeasonCandidatesUseCase {
                do {
                    _ = try await refreshSeasonCandidatesUseCase
                        .discoverSeasonCandidates(brandID: createdBrand.id)
                } catch {
                    message = "최신 시즌을 확인하지 못해 저장된 후보를 보여드립니다."
                }
            }

            candidates = try await loadSelectableSeasonCandidatesUseCase.execute(
                brandID: createdBrand.id
            )
            selectedCandidateIDs = selectedCandidateIDs.intersection(
                Set(candidates.map(\.id))
            )
            if candidates.isEmpty {
                message = "지금 바로 가져올 수 있는 시즌이 없습니다."
            }
        } catch {
            message = "시즌 후보를 불러오지 못했습니다."
        }
    }

    private func submitSelection() {
        guard selectedCandidateIDs.isEmpty == false else {
            onComplete()
            return
        }

        let selectedCandidates = candidates
            .filter { selectedCandidateIDs.contains($0.id) }
            .sorted { $0.sortIndex < $1.sortIndex }
        let candidateIDs = selectedCandidates.map(\.id)

        isSubmitting = true
        message = nil
        beginImageExtractionProgress(candidateIDs: candidateIDs)

        submissionTask?.cancel()
        submissionTask = Task {
            do {
                let result = try await startSeasonImportExtractionUseCase.execute(
                    brandID: createdBrand.id,
                    candidates: selectedCandidates
                )
                let progress = try await startSeasonImportExtractionUseCase.loadProgress(
                    brandID: createdBrand.id,
                    candidateIDs: candidateIDs
                )
                await MainActor.run {
                    guard extractionCandidateIDs == candidateIDs else { return }
                    isSubmitting = false
                    failedToStartCandidateIDs = Set(
                        result.failedCandidates.map(\.candidateID)
                    )
                    applyImageExtractionProgress(progress)
                    finishImageExtractionIfPossible()
                }
            } catch {
                let progress = try? await startSeasonImportExtractionUseCase.loadProgress(
                    brandID: createdBrand.id,
                    candidateIDs: candidateIDs
                )
                await MainActor.run {
                    guard extractionCandidateIDs == candidateIDs else { return }
                    isSubmitting = false

                    if let progress, progress.matchedJobCount > 0 {
                        applyImageExtractionProgress(progress)
                        message = "준비 상태를 다시 확인하고 있습니다."
                        finishImageExtractionIfPossible()
                        return
                    }

                    progressPollingTask?.cancel()
                    progressPollingTask = nil
                    importProgressPhase = .selecting
                    extractionCandidateIDs = []
                    extractionTotalCount = 0
                    extractionCompletedCount = 0
                    extractionFailedCount = 0
                    extractionProgressItems = []
                    failedToStartCandidateIDs = []
                    retryingCandidateIDs = []
                    message = "선택한 시즌을 준비하지 못했습니다."
                }
            }
        }
    }

    @MainActor
    private func beginImageExtractionProgress(candidateIDs: [String]) {
        extractionCandidateIDs = candidateIDs
        extractionTotalCount = candidateIDs.count
        extractionCompletedCount = 0
        extractionFailedCount = 0
        extractionProgressItems = []
        failedToStartCandidateIDs = []
        retryingCandidateIDs = []
        importProgressPhase = .extracting
        startImportProgressPolling(candidateIDs: candidateIDs)
    }

    private func startImportProgressPolling(candidateIDs: [String]) {
        progressPollingTask?.cancel()
        progressPollingTask = Task {
            while !Task.isCancelled {
                do {
                    let progress = try await startSeasonImportExtractionUseCase.loadProgress(
                        brandID: createdBrand.id,
                        candidateIDs: candidateIDs
                    )
                    await MainActor.run {
                        guard extractionCandidateIDs == candidateIDs else { return }
                        applyImageExtractionProgress(progress)
                        finishImageExtractionIfPossible()
                    }
                } catch {
                    // 한국어 주석: 진행률 조회 실패는 일시적일 수 있어 다음 polling 주기에서 다시 확인합니다.
                }

                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    @MainActor
    private func applyImageExtractionProgress(
        _ progress: SeasonImportExtractionProgress
    ) {
        extractionTotalCount = progress.totalCount
        extractionCompletedCount = progress.completedCount + failedToStartCandidateIDs.count
        extractionFailedCount = progress.failedCount + failedToStartCandidateIDs.count
        extractionProgressItems = progress.items
    }

    @MainActor
    private func finishImageExtractionIfPossible() {
        guard extractionTotalCount > 0 else { return }
        guard extractionCompletedCount >= extractionTotalCount else { return }

        progressPollingTask?.cancel()
        progressPollingTask = nil
        importProgressPhase = .completed
        message = extractionFailedCount > 0 ? "실패한 시즌은 다시 시도할 수 있습니다." : nil
    }

    private func retryCandidates(_ candidatesToRetry: [SeasonCandidate]) {
        let retryCandidates = candidatesToRetry.filter {
            retryingCandidateIDs.contains($0.id) == false
        }
        guard retryCandidates.isEmpty == false else { return }

        let retryCandidateIDs = retryCandidates.map(\.id)
        retryingCandidateIDs.formUnion(retryCandidateIDs)
        failedToStartCandidateIDs.subtract(retryCandidateIDs)
        message = nil

        submissionTask?.cancel()
        submissionTask = Task {
            defer {
                Task { @MainActor in
                    retryingCandidateIDs.subtract(retryCandidateIDs)
                }
            }

            do {
                let result = try await startSeasonImportExtractionUseCase.execute(
                    brandID: createdBrand.id,
                    candidates: retryCandidates
                )
                let progress = try await startSeasonImportExtractionUseCase.loadProgress(
                    brandID: createdBrand.id,
                    candidateIDs: extractionCandidateIDs
                )
                await MainActor.run {
                    failedToStartCandidateIDs.formUnion(
                        result.failedCandidates.map(\.candidateID)
                    )
                    applyImageExtractionProgress(progress)
                    if importProgressPhase == .completed {
                        startImportProgressPolling(candidateIDs: extractionCandidateIDs)
                    }
                }
            } catch {
                await MainActor.run {
                    failedToStartCandidateIDs.formUnion(retryCandidateIDs)
                    message = "선택한 시즌을 다시 요청하지 못했습니다."
                }
            }
        }
    }

    private var selectedImportCandidates: [SeasonCandidate] {
        candidates
            .filter { extractionCandidateIDs.contains($0.id) }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    private var succeededCandidates: [SeasonCandidate] {
        selectedImportCandidates.filter {
            candidateImportStatus(candidateID: $0.id) == .succeeded
        }
    }

    private var failedCandidates: [SeasonCandidate] {
        selectedImportCandidates.filter {
            candidateImportStatus(candidateID: $0.id) == .failed
        }
    }

    private var processingCandidates: [SeasonCandidate] {
        selectedImportCandidates.filter {
            candidateImportStatus(candidateID: $0.id) == .processing
        }
    }

    private func candidateImportStatus(candidateID: String) -> CandidateImportStatus {
        if failedToStartCandidateIDs.contains(candidateID) {
            return .failed
        }

        if retryingCandidateIDs.contains(candidateID) {
            return .processing
        }

        guard let item = extractionProgressItems.first(where: {
            $0.candidateID == candidateID
        }) else {
            return .processing
        }

        switch item.status {
        case .processing:
            return .processing
        case .succeeded:
            return .succeeded
        case .failed:
            return .failed
        }
    }

    private func resultIconName(for status: CandidateImportStatus) -> String {
        switch status {
        case .processing:
            return "clock"
        case .succeeded:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private func resultColor(for status: CandidateImportStatus) -> Color {
        switch status {
        case .processing:
            return OutPickTheme.SwiftUIColor.accent
        case .succeeded:
            return OutPickTheme.SwiftUIColor.success
        case .failed:
            return OutPickTheme.SwiftUIColor.warning
        }
    }
}
