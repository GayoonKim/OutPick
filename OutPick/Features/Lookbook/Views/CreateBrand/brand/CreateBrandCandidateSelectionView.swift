//
//  CreateBrandCandidateSelectionView.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import SwiftUI

struct CreateBrandCandidateSelectionView: View {
    private enum ImportProgressPhase {
        case selecting
        case extracting
        case completed
    }

    let createdBrand: CreateBrandViewModel.CreatedBrand
    let loadSelectableSeasonCandidatesUseCase: any LoadSelectableSeasonCandidatesUseCaseProtocol
    let startSeasonImportExtractionUseCase: any StartSeasonImportExtractionUseCaseProtocol
    let discoveryErrorMessage: String?
    let emptySelectionButtonTitle: String
    let onComplete: () -> Void

    @State private var selectedCandidateIDs: Set<String> = []
    @State private var candidates: [SeasonCandidate] = []
    @State private var importProgressPhase: ImportProgressPhase = .selecting
    @State private var extractionCandidateIDs: [String] = []
    @State private var extractionTotalCount: Int = 0
    @State private var extractionCompletedCount: Int = 0
    @State private var extractionFailedCount: Int = 0
    @State private var progressPollingTask: Task<Void, Never>?
    @State private var submissionTask: Task<Void, Never>?
    @State private var autoCompletionTask: Task<Void, Never>?
    @State private var isLoading: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var message: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("가져올 시즌을 선택해주세요")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("이미 처리 중이거나 가져온 시즌은 보이지 않습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let discoveryErrorMessage {
                        Text(discoveryErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                switch importProgressPhase {
                case .selecting:
                    candidateListSection
                    submitButton
                case .extracting, .completed:
                    extractionProgressSection
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.97, blue: 0.94),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .task {
            await loadCandidates()
        }
        .onDisappear {
            progressPollingTask?.cancel()
            submissionTask?.cancel()
            autoCompletionTask?.cancel()
        }
    }

    @ViewBuilder
    private var candidateListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("선택할 시즌")
                    .font(.headline)

                Spacer()

                if isLoading {
                    ProgressView()
                        .tint(.black)
                }
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if candidates.isEmpty == false {
                HStack(spacing: 10) {
                    Text("\(selectedCandidateIDs.count)/\(candidates.count)개 선택됨")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Button {
                        selectAllCandidates()
                    } label: {
                        Text("모두 선택")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .foregroundStyle(.white)
                    .background(Color.black.opacity(areAllCandidatesSelected ? 0.35 : 1))
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
                    .foregroundStyle(Color.black.opacity(selectedCandidateIDs.isEmpty ? 0.45 : 1))
                    .overlay {
                        Capsule()
                            .stroke(
                                Color.black.opacity(selectedCandidateIDs.isEmpty ? 0.18 : 1),
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
                    Text("지금 바로 가져올 수 있는 시즌이 없습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.97, green: 0.97, blue: 0.96))
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
                                    .foregroundStyle(selectedCandidateIDs.contains(candidate.id) ? .black : .secondary)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(candidate.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                }

                                Spacer()
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white)
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
                        .tint(.white)
                } else {
                    Text(primaryButtonTitle)
                        .font(.headline)
                }
                Spacer()
            }
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .disabled(isSubmitting)
        .opacity(isSubmitting ? 0.55 : 1)
    }

    private var extractionProgressSection: some View {
            VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(importProgressPhase == .completed ? "시즌 준비가 끝났습니다" : "선택한 시즌을 준비하고 있습니다")
                    .font(.title2.weight(.bold))

                Text(
                    importProgressPhase == .completed
                    ? "잠시 후 다음 화면으로 이동합니다."
                    : "사진을 가져오고 시즌 목록에 반영하고 있습니다."
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                ProgressView(
                    value: extractionTotalCount == 0
                    ? 0
                    : Double(extractionCompletedCount),
                    total: Double(max(extractionTotalCount, 1))
                )
                .tint(.black)

                Text("준비 완료 \(extractionCompletedCount)/\(extractionTotalCount)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                if extractionFailedCount > 0 {
                    Text("가져오지 못한 시즌이 있습니다. 나중에 다시 시도할 수 있습니다.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
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
                _ = try await startSeasonImportExtractionUseCase.execute(
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
        extractionCompletedCount = progress.completedCount
        extractionFailedCount = progress.failedCount
    }

    @MainActor
    private func finishImageExtractionIfPossible() {
        guard extractionTotalCount > 0 else { return }
        guard extractionCompletedCount >= extractionTotalCount else { return }
        guard importProgressPhase != .completed else { return }

        progressPollingTask?.cancel()
        progressPollingTask = nil
        importProgressPhase = .completed
        message = extractionFailedCount > 0
        ? "일부 시즌은 가져오지 못했지만, 다음 화면으로 이동합니다."
        : nil
        scheduleAutoCompletion()
    }

    private func scheduleAutoCompletion() {
        autoCompletionTask?.cancel()
        autoCompletionTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                onComplete()
            }
        }
    }
}
