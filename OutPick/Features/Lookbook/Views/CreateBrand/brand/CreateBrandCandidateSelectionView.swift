//
//  CreateBrandCandidateSelectionView.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import SwiftUI

struct CreateBrandCandidateSelectionView: View {
    @Environment(\.scenePhase) private var scenePhase

    private enum ImportProgressPhase: Equatable {
        case selecting
        case extracting
        case completed
        case needsReconcile
    }

    private enum CandidateImportStatus: Equatable {
        case processing
        case succeeded
        case failed
        case reviewRequired
        case duplicate
        case recoveryRequired
    }

    let createdBrand: CreateBrandViewModel.CreatedBrand
    let loadSelectableSeasonCandidatesUseCase: any LoadSelectableSeasonCandidatesUseCaseProtocol
    let startSeasonImportExtractionUseCase: any StartSeasonImportExtractionUseCaseProtocol
    let discoveryErrorMessage: String?
    let emptySelectionButtonTitle: String
    let onToolbarCloseVisibilityChange: (Bool) -> Void
    let onComplete: () -> Void

    @State private var selectedCandidateIDs: Set<String> = []
    @State private var candidates: [SeasonCandidate] = []
    @State private var importProgressPhase: ImportProgressPhase = .selecting
    @State private var extractionCandidateIDs: [String] = []
    @State private var extractionRequestID: String?
    @State private var extractionTotalCount: Int = 0
    @State private var extractionCompletedCount: Int = 0
    @State private var extractionFailedCount: Int = 0
    @State private var extractionProgressItems: [SeasonImportExtractionProgress.Item] = []
    @State private var failedToStartCandidateIDs: Set<String> = []
    @State private var retryingCandidateIDs: Set<String> = []
    @State private var progressPollingTask: Task<Void, Never>?
    @State private var progressPollingRequestID: String?
    @State private var submissionTask: Task<Void, Never>?
    @State private var isLoading: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var didFailToDiscoverCandidates: Bool = false
    @State private var message: String?

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    switch importProgressPhase {
                    case .selecting:
                        headerSection
                        candidateListSection
                        submitButton
                    case .extracting, .completed, .needsReconcile:
                        extractionProgressSection
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: progressContentMinimumHeight(in: geometry.size.height),
                    alignment: progressContentAlignment
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
            }
            .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
        }
        .task {
            await loadCandidates()
        }
        .onDisappear {
            progressPollingTask?.cancel()
            progressPollingRequestID = nil
        }
        .onAppear {
            notifyToolbarCloseVisibility()
        }
        .onChange(of: importProgressPhase) { _ in
            notifyToolbarCloseVisibility()
        }
        .onChange(of: scenePhase) { phase in
            guard let requestID = extractionRequestID else { return }
            if phase == .active {
                startImportProgressPolling(requestID: requestID)
            } else {
                progressPollingTask?.cancel()
            }
        }
    }

    private var progressContentAlignment: Alignment {
        importProgressPhase == .selecting ? .topLeading : .center
    }

    private func progressContentMinimumHeight(in containerHeight: CGFloat) -> CGFloat? {
        guard importProgressPhase != .selecting else { return nil }
        return max(0, containerHeight - 64)
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

            if didFailToDiscoverCandidates {
                discoveryFailureSection
            } else if candidates.isEmpty {
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

    private var discoveryFailureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message ?? "시즌 목록을 불러오지 못했습니다.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("0개 시즌을 불러왔습니다.")
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task {
                    await loadCandidates()
                }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(OutPickTheme.SwiftUIColor.backgroundBase)
                    } else {
                        Text("재시도")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
            .background(OutPickTheme.SwiftUIColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(isLoading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

                    Text("완료 \(extractionCompletedCount)/\(extractionTotalCount) · 검토 필요 \(reviewRequiredCandidates.count) · 실패 \(extractionFailedCount)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                        .multilineTextAlignment(.center)

                    progressCloseActionSection
                } else if importProgressPhase == .needsReconcile {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title2)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.warning)
                    Text("접수 결과를 확인하고 있습니다.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                    Button("접수 상태 다시 확인") {
                        reconcileCurrentRequest()
                    }
                    .disabled(isSubmitting)
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
            if reviewRequiredCandidates.isEmpty == false {
                Text("검토가 필요한 시즌 \(reviewRequiredCandidates.count)개는 성공으로 처리되지 않았습니다.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.warning)
            }
            if recoveryRequiredCandidates.isEmpty == false {
                Text("\(recoveryRequiredCandidates.count)개 시즌은 서버 복구 확인이 필요합니다.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.warning)
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
            if reviewRequiredCandidates.isEmpty == false {
                resultGroup(title: "검토 필요", candidates: reviewRequiredCandidates, status: .reviewRequired)
            }
            if duplicateCandidates.isEmpty == false {
                resultGroup(title: "기존 작업과 연결", candidates: duplicateCandidates, status: .duplicate)
            }
            if recoveryRequiredCandidates.isEmpty == false {
                resultGroup(title: "복구 확인 필요", candidates: recoveryRequiredCandidates, status: .recoveryRequired)
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
                guard isSubmitting == false else { return }
                onComplete()
            } label: {
                Text(isSubmitting ? "요청을 보내는 중" : "현황에서 계속 확인")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(OutPickTheme.SwiftUIColor.accent, lineWidth: 1)
            }
            .disabled(isSubmitting)

            if isSubmitting {
                Text("선택한 시즌 작업을 등록한 뒤 닫을 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
        case .needsReconcile:
            return "접수 상태 확인이 필요합니다"
        }
    }

    private var headerDescription: String {
        switch importProgressPhase {
        case .selecting:
            return "새로 추가된 룩북을 확인한 뒤, 이미 처리 중이거나 가져온 시즌은 제외합니다."
        case .extracting:
            return "선택한 시즌의 사진을 가져오고 있습니다. 닫은 뒤에는 현황에서 계속 확인할 수 있습니다."
        case .completed:
            return "시즌 불러오기 요청 결과를 확인하세요."
        case .needsReconcile:
            return "같은 요청 ID를 보존했습니다. 상태 확인을 다시 시도하면 새 중복 요청을 만들지 않습니다."
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
        didFailToDiscoverCandidates = false
        defer { isLoading = false }

        do {
            candidates = try await loadSelectableSeasonCandidatesUseCase.execute(
                brandID: createdBrand.id
            )
            selectedCandidateIDs = selectedCandidateIDs.intersection(
                Set(candidates.map(\.id))
            )
            await restoreUnsettledRequests()
            if candidates.isEmpty {
                message = "지금 바로 가져올 수 있는 시즌이 없습니다."
            }
        } catch {
            candidates = []
            selectedCandidateIDs = []
            didFailToDiscoverCandidates = true
            message = "시즌 목록을 불러오지 못했습니다."
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
        isSubmitting = true
        message = nil
        extractionCandidateIDs = selectedCandidates.map(\.id)
        extractionTotalCount = selectedCandidates.count
        extractionCompletedCount = 0
        extractionFailedCount = 0
        extractionProgressItems = []
        failedToStartCandidateIDs = []
        retryingCandidateIDs = []
        importProgressPhase = .extracting

        submissionTask?.cancel()
        submissionTask = Task {
            do {
                let receipt = try await startSeasonImportExtractionUseCase.execute(
                    brandID: createdBrand.id,
                    candidates: selectedCandidates
                )
                let progress = try await startSeasonImportExtractionUseCase.loadProgress(
                    requestID: receipt.requestID
                )
                await MainActor.run {
                    guard extractionCandidateIDs == selectedCandidates.map(\.id) else { return }
                    isSubmitting = false
                    extractionRequestID = receipt.requestID
                    applyImageExtractionProgress(progress)
                    finishImageExtractionIfPossible()
                    if !progress.isFinished { startImportProgressPolling(requestID: receipt.requestID) }
                }
            } catch {
                let recoveredReceipts = (try? await startSeasonImportExtractionUseCase
                    .reconcileUnsettledRequests(brandID: createdBrand.id)) ?? []
                let recovered = recoveredReceipts.first {
                    $0.items.map(\.targetID) == selectedCandidates.map(\.id)
                }
                var pendingRequestID = recovered?.requestID
                if pendingRequestID == nil {
                    pendingRequestID = try? await startSeasonImportExtractionUseCase.unsettledRequestID(
                        brandID: createdBrand.id,
                        candidates: selectedCandidates
                    )
                }
                var progress: SeasonImportExtractionProgress?
                if let recovered {
                    progress = try? await startSeasonImportExtractionUseCase
                        .loadProgress(requestID: recovered.requestID)
                }
                await MainActor.run {
                    guard extractionCandidateIDs == selectedCandidates.map(\.id) else { return }
                    isSubmitting = false

                    if let progress {
                        extractionRequestID = recovered?.requestID ?? pendingRequestID
                        applyImageExtractionProgress(progress)
                        message = "준비 상태를 다시 확인하고 있습니다."
                        finishImageExtractionIfPossible()
                        if let requestID = extractionRequestID, !progress.isFinished {
                            startImportProgressPolling(requestID: requestID)
                        }
                        return
                    }

                    guard let pendingRequestID else {
                        progressPollingTask?.cancel()
                        progressPollingTask = nil
                        extractionRequestID = nil
                        importProgressPhase = .selecting
                        message = "요청을 기기에 저장하지 못해 서버에 보내지 않았습니다. 다시 시도해 주세요."
                        return
                    }

                    progressPollingTask?.cancel()
                    progressPollingTask = nil
                    extractionRequestID = pendingRequestID
                    importProgressPhase = .needsReconcile
                    message = "요청 결과가 아직 확인되지 않았습니다. 다시 확인하거나 현황 화면에서 이어서 확인할 수 있습니다."
                    startImportProgressPolling(requestID: pendingRequestID)
                }
            }
        }
    }

    @MainActor
    private func applyRestoredReceipt(
        _ receipt: LookbookImportQueueReceipt,
        progress: SeasonImportExtractionProgress
    ) {
        extractionRequestID = receipt.requestID
        extractionCandidateIDs = receipt.candidateIDs
        selectedCandidateIDs = Set(receipt.candidateIDs)
        extractionTotalCount = progress.totalCount
        failedToStartCandidateIDs = []
        retryingCandidateIDs = []
        applyImageExtractionProgress(progress)
        importProgressPhase = progress.isFinished ? .completed : .extracting
        finishImageExtractionIfPossible()
        if !progress.isFinished { startImportProgressPolling(requestID: receipt.requestID) }
    }

    @MainActor
    private func restoreUnsettledRequests() async {
        let receipts = (try? await startSeasonImportExtractionUseCase
            .reconcileUnsettledRequests(brandID: createdBrand.id)) ?? []
        guard let receipt = receipts.first else {
            guard let requestID = try? await startSeasonImportExtractionUseCase
                .latestUnsettledRequestID(brandID: createdBrand.id) else { return }
            extractionRequestID = requestID
            importProgressPhase = .needsReconcile
            message = "이전 시즌 요청의 접수 결과를 확인하고 있습니다."
            startImportProgressPolling(requestID: requestID)
            return
        }
        guard let progress = try? await startSeasonImportExtractionUseCase
            .loadProgress(requestID: receipt.requestID) else {
            extractionRequestID = receipt.requestID
            importProgressPhase = .needsReconcile
            message = "이전 시즌 요청 상태를 다시 확인해 주세요."
            return
        }
        applyRestoredReceipt(receipt, progress: progress)
    }

    private func reconcileCurrentRequest() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            let receipts = (try? await startSeasonImportExtractionUseCase
                .reconcileUnsettledRequests(brandID: createdBrand.id)) ?? []
            guard let receipt = receipts.first,
                  let progress = try? await startSeasonImportExtractionUseCase
                    .loadProgress(requestID: receipt.requestID) else {
                let pendingRequestID = try? await startSeasonImportExtractionUseCase
                    .latestUnsettledRequestID(brandID: createdBrand.id)
                await MainActor.run {
                    isSubmitting = false
                    if let pendingRequestID {
                        extractionRequestID = pendingRequestID
                        startImportProgressPolling(requestID: pendingRequestID)
                    }
                    message = "아직 접수 결과를 확인할 수 없습니다. 잠시 후 다시 확인해 주세요."
                }
                return
            }
            await MainActor.run {
                isSubmitting = false
                applyRestoredReceipt(receipt, progress: progress)
            }
        }
    }

    private func startImportProgressPolling(requestID: String) {
        guard scenePhase == .active else { return }
        guard progressPollingTask == nil else {
            if progressPollingRequestID != requestID {
                progressPollingRequestID = requestID
                progressPollingTask?.cancel()
            }
            return
        }
        progressPollingRequestID = requestID
        progressPollingTask = Task { @MainActor in
            defer {
                progressPollingTask = nil
                if scenePhase == .active,
                   importProgressPhase != .completed,
                   let nextRequestID = progressPollingRequestID {
                    startImportProgressPolling(requestID: nextRequestID)
                }
            }
            var consecutiveErrors = 0
            var waitingState = false
            while !Task.isCancelled && scenePhase == .active {
                do {
                    let progress = try await startSeasonImportExtractionUseCase.loadProgress(requestID: requestID)
                    consecutiveErrors = 0
                    waitingState = progress.batchState == .preparing || progress.batchState == .queued || progress.batchState == .retryWaiting
                    guard extractionRequestID == requestID else { return }
                    applyImageExtractionProgress(progress)
                    finishImageExtractionIfPossible()
                } catch {
                    if importProgressPhase == .needsReconcile {
                        let receipts = (try? await startSeasonImportExtractionUseCase
                            .reconcileUnsettledRequests(brandID: createdBrand.id)) ?? []
                        if let receipt = receipts.first(where: { $0.requestID == requestID }),
                           let progress = try? await startSeasonImportExtractionUseCase
                            .loadProgress(requestID: requestID) {
                            guard extractionRequestID == requestID else { return }
                            extractionCandidateIDs = receipt.candidateIDs
                            extractionTotalCount = progress.totalCount
                            importProgressPhase = .extracting
                            applyImageExtractionProgress(progress)
                            finishImageExtractionIfPossible()
                        }
                    }
                    consecutiveErrors = min(consecutiveErrors + 1, 4)
                }

                guard !Task.isCancelled, scenePhase == .active else { return }

                let delaySeconds: UInt64
                if consecutiveErrors > 0 {
                    delaySeconds = [10, 20, 40, 60][consecutiveErrors - 1]
                } else {
                    delaySeconds = waitingState ? 10 : 3
                }
                try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
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
        guard extractionProgressItems.count >= extractionTotalCount,
              extractionProgressItems.allSatisfy({ $0.status.isTerminal }) ||
                extractionProgressItems.contains(where: { $0.status == .recoveryRequired }) else { return }

        progressPollingTask?.cancel()
        progressPollingRequestID = nil
        importProgressPhase = .completed
        if extractionProgressItems.contains(where: { $0.status == .recoveryRequired }) {
            message = "일부 시즌은 서버 복구 확인이 필요합니다. 완료로 간주하지 않았습니다."
        } else if reviewRequiredCandidates.isEmpty == false {
            message = "검토가 필요한 시즌은 성공으로 처리하지 않았습니다."
        } else {
            message = extractionFailedCount > 0 ? "실패한 시즌은 다시 시도할 수 있습니다." : nil
        }
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
                let receipt = try await startSeasonImportExtractionUseCase.execute(
                    brandID: createdBrand.id,
                    candidates: retryCandidates
                )
                let progress = try await startSeasonImportExtractionUseCase.loadProgress(
                    requestID: receipt.requestID
                )
                await MainActor.run {
                    extractionRequestID = receipt.requestID
                    extractionCandidateIDs = retryCandidates.map(\.id)
                    applyImageExtractionProgress(progress)
                    importProgressPhase = progress.isFinished ? .completed : .extracting
                    if !progress.isFinished { startImportProgressPolling(requestID: receipt.requestID) }
                }
            } catch {
                let pendingRequestID = try? await startSeasonImportExtractionUseCase
                    .unsettledRequestID(brandID: createdBrand.id, candidates: retryCandidates)
                await MainActor.run {
                    extractionCandidateIDs = retryCandidateIDs
                    if let pendingRequestID {
                        extractionRequestID = pendingRequestID
                        importProgressPhase = .needsReconcile
                        message = "재시도 접수 결과를 확인하고 있습니다."
                        startImportProgressPolling(requestID: pendingRequestID)
                    } else {
                        failedToStartCandidateIDs.formUnion(retryCandidateIDs)
                        message = "요청을 기기에 저장하지 못해 서버에 보내지 않았습니다."
                    }
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

    private var reviewRequiredCandidates: [SeasonCandidate] {
        selectedImportCandidates.filter { candidateImportStatus(candidateID: $0.id) == .reviewRequired }
    }

    private var duplicateCandidates: [SeasonCandidate] {
        selectedImportCandidates.filter { candidateImportStatus(candidateID: $0.id) == .duplicate }
    }

    private var recoveryRequiredCandidates: [SeasonCandidate] {
        selectedImportCandidates.filter { candidateImportStatus(candidateID: $0.id) == .recoveryRequired }
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
        case .queued, .retryWaiting:
            return .processing
        case .processing:
            return .processing
        case .succeeded:
            return .succeeded
        case .failed:
            return .failed
        case .awaitingReview:
            return .reviewRequired
        case .skipped:
            return .failed
        case .duplicate:
            return .duplicate
        case .recoveryRequired:
            return .recoveryRequired
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
        case .reviewRequired:
            return "eye.fill"
        case .duplicate:
            return "arrow.triangle.branch"
        case .recoveryRequired:
            return "exclamationmark.arrow.triangle.2.circlepath"
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
        case .reviewRequired, .recoveryRequired:
            return OutPickTheme.SwiftUIColor.warning
        case .duplicate:
            return OutPickTheme.SwiftUIColor.textSecondary
        }
    }
}
