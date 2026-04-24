//
//  CreateBrandFlowView.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import SwiftUI

struct CreateBrandFlowView: View {
    enum PreviewStep {
        case form
        case finishing
        case completed
        case discovering
        case candidateSelection
    }

    private enum Step: Equatable {
        case form
        case finishing(CreateBrandViewModel.CreatedBrand)
        case completed(CreateBrandViewModel.CreatedBrand)
        case discovering(CreateBrandViewModel.CreatedBrand)
        case candidateSelection(CreateBrandViewModel.CreatedBrand)
    }

    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .form
    @State private var latestCreatedBrand: CreateBrandViewModel.CreatedBrand?
    @State private var discoveryTask: Task<Void, Never>?
    @State private var logoPreparationTask: Task<Void, Never>?
    @State private var isShowingCloseConfirmation: Bool = false
    @State private var discoveryErrorMessage: String?

    private let provider: LookbookRepositoryProvider
    private let onFinished: (BrandID?) -> Void

    init(
        provider: LookbookRepositoryProvider = .shared,
        onFinished: @escaping (BrandID?) -> Void = { _ in }
    ) {
        self.provider = provider
        self.onFinished = onFinished
    }

    init(
        previewStep: PreviewStep,
        provider: LookbookRepositoryProvider = .shared,
        onFinished: @escaping (BrandID?) -> Void = { _ in }
    ) {
        self.provider = provider
        self.onFinished = onFinished

        let previewBrand = CreateBrandViewModel.CreatedBrand(
            id: BrandID(value: "preview-brand"),
            name: "Preview Atelier",
            websiteURL: "https://preview.example.com",
            lookbookArchiveURL: "https://preview.example.com/collections",
            hasLogoAsset: true
        )

        switch previewStep {
        case .form:
            _step = State(initialValue: .form)
        case .finishing:
            _step = State(initialValue: .finishing(previewBrand))
            _latestCreatedBrand = State(initialValue: previewBrand)
        case .completed:
            _step = State(initialValue: .completed(
                CreateBrandViewModel.CreatedBrand(
                    id: previewBrand.id,
                    name: previewBrand.name,
                    websiteURL: nil,
                    lookbookArchiveURL: nil,
                    hasLogoAsset: false
                )
            ))
            _latestCreatedBrand = State(initialValue: previewBrand)
        case .discovering:
            _step = State(initialValue: .discovering(previewBrand))
            _latestCreatedBrand = State(initialValue: previewBrand)
        case .candidateSelection:
            _step = State(initialValue: .candidateSelection(previewBrand))
            _latestCreatedBrand = State(initialValue: previewBrand)
        }
    }

    var body: some View {
        content
            .tint(.black)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isShowingCloseConfirmation = true
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.black)
                    }
                    .accessibilityLabel("브랜드 등록 닫기")
                }
            }
            .confirmationDialog(
                closeConfirmationTitle,
                isPresented: $isShowingCloseConfirmation,
                titleVisibility: .visible
            ) {
                Button(closeConfirmationActionTitle) {
                    closeFlow()
                }
                Button("계속 진행", role: .cancel) {}
            } message: {
                Text(closeConfirmationMessage)
            }
            .onDisappear {
                discoveryTask?.cancel()
                logoPreparationTask?.cancel()
            }
    }
}

private extension CreateBrandFlowView {
    @ViewBuilder
    var content: some View {
        switch step {
        case .form:
            CreateBrandView(provider: provider) { createdBrand in
                latestCreatedBrand = createdBrand
                advanceAfterBrandCreation(createdBrand)
            }

        case .finishing(let createdBrand):
            CreateBrandFinishingView(createdBrand: createdBrand)

        case .completed(let createdBrand):
            CreateBrandCompletedView(
                createdBrand: createdBrand,
                onComplete: {
                    closeFlow()
                }
            )

        case .discovering(let createdBrand):
            CreateBrandDiscoveringView(
                createdBrand: createdBrand,
                onSkip: {
                    discoveryTask?.cancel()
                    step = .candidateSelection(createdBrand)
                }
            )

        case .candidateSelection(let createdBrand):
            CreateBrandCandidateSelectionView(
                createdBrand: createdBrand,
                loadSelectableSeasonCandidatesUseCase: LoadSelectableSeasonCandidatesUseCase(
                    candidateRepository: provider.seasonCandidateRepository,
                    seasonImportJobRepository: provider.seasonImportJobRepository
                ),
                startSeasonImportExtractionUseCase: StartSeasonImportExtractionUseCase(
                    processingRepository: provider.seasonImportJobProcessingRepository,
                    seasonImportJobRepository: provider.seasonImportJobRepository
                ),
                discoveryErrorMessage: discoveryErrorMessage,
                emptySelectionButtonTitle: "브랜드 등록 마치기",
                onComplete: {
                    closeFlow()
                }
            )
        }
    }

    func advanceAfterBrandCreation(_ createdBrand: CreateBrandViewModel.CreatedBrand) {
        if createdBrand.canDiscoverSeasons {
            step = .discovering(createdBrand)
            startSeasonCandidateDiscovery(for: createdBrand)
            return
        }

        discoveryTask?.cancel()

        if createdBrand.hasLogoAsset {
            step = .finishing(createdBrand)
            scheduleLogoPreparationTransition(for: createdBrand)
        } else {
            step = .completed(createdBrand)
        }
    }

    func startSeasonCandidateDiscovery(for createdBrand: CreateBrandViewModel.CreatedBrand) {
        discoveryTask?.cancel()
        discoveryErrorMessage = nil
        discoveryTask = Task {
            do {
                _ = try await provider.seasonCandidateDiscoveryRepository
                    .discoverSeasonCandidates(brandID: createdBrand.id)
            } catch {
                await MainActor.run {
                    discoveryErrorMessage = "시즌을 바로 찾지 못했습니다. 다음 화면에서 직접 확인할 수 있습니다."
                }
            }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                guard latestCreatedBrand == createdBrand else { return }
                step = .candidateSelection(createdBrand)
            }
        }
    }

    func scheduleLogoPreparationTransition(for createdBrand: CreateBrandViewModel.CreatedBrand) {
        logoPreparationTask?.cancel()
        logoPreparationTask = Task {
            defer {
                Task { @MainActor in
                    self.logoPreparationTask = nil
                }
            }

            while !Task.isCancelled {
                guard !Task.isCancelled else { return }

                do {
                    let brand = try await provider.brandRepository.fetchBrand(brandID: createdBrand.id)
                    if await isLogoReadyToDisplay(for: brand) {
                        await MainActor.run {
                            guard latestCreatedBrand == createdBrand else { return }
                            step = .completed(createdBrand)
                        }
                        return
                    }
                } catch {
                    // 일시적인 조회 실패는 바로 종료하지 않고 다음 시도에서 다시 확인합니다.
                }

                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    func isLogoReadyToDisplay(for brand: Brand) async -> Bool {
        guard let logoThumbPath = brand.logoThumbPath, logoThumbPath.isEmpty == false else {
            return false
        }

        do {
            _ = try await provider.brandImageCache.loadImage(
                path: logoThumbPath,
                maxBytes: 1 * 1024 * 1024
            )
            return true
        } catch {
            return false
        }
    }

    func closeFlow() {
        onFinished(latestCreatedBrand?.id)
        dismiss()
    }

    var closeConfirmationTitle: String {
        if latestCreatedBrand == nil {
            return "브랜드 등록을 취소할까요?"
        }

        return "브랜드 등록 플로우를 닫을까요?"
    }

    var closeConfirmationMessage: String {
        if let latestCreatedBrand {
            return "\(latestCreatedBrand.name) 브랜드는 이미 생성된 상태로 유지됩니다. 시즌 선택은 나중에 다시 진행할 수 있습니다."
        }

        return "지금 닫으면 입력 중인 브랜드 정보는 저장되지 않습니다."
    }

    var closeConfirmationActionTitle: String {
        latestCreatedBrand == nil ? "등록 취소" : "닫기"
    }
}

#Preview("Brand Flow Form") {
    NavigationView {
        CreateBrandFlowView(previewStep: .form)
    }
}

#Preview("Brand Flow Finishing") {
    NavigationView {
        CreateBrandFlowView(previewStep: .finishing)
    }
}

#Preview("Brand Flow Completed") {
    NavigationView {
        CreateBrandFlowView(previewStep: .completed)
    }
}

#Preview("Brand Flow Discovering") {
    NavigationView {
        CreateBrandFlowView(previewStep: .discovering)
    }
}

#Preview("Brand Flow Candidate Selection") {
    NavigationView {
        CreateBrandFlowView(previewStep: .candidateSelection)
    }
}
