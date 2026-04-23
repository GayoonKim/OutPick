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
                onComplete: {
                    closeFlow()
                }
            )
        }
    }

    func advanceAfterBrandCreation(_ createdBrand: CreateBrandViewModel.CreatedBrand) {
        if createdBrand.canDiscoverSeasons {
            step = .discovering(createdBrand)
            scheduleCandidateSelectionTransition(for: createdBrand)
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

    func scheduleCandidateSelectionTransition(for createdBrand: CreateBrandViewModel.CreatedBrand) {
        discoveryTask?.cancel()
        discoveryTask = Task {
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
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
                    // 한국어 주석: 일시적인 조회 실패는 바로 종료하지 않고 다음 시도에서 다시 확인합니다.
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

private struct CreateBrandFinishingView: View {
    let createdBrand: CreateBrandViewModel.CreatedBrand

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                Text("브랜드 생성을 마무리하고 있습니다")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("\(createdBrand.name) 브랜드 문서는 이미 생성되었습니다. 로고 이미지를 홈 목록에서 자연스럽게 보여주기 위해 최소 썸네일 리소스를 준비하고 있습니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.black)

                Text("브랜드 로고 썸네일을 준비 중입니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(red: 0.98, green: 0.97, blue: 0.94).ignoresSafeArea())
    }
}

private struct CreateBrandCompletedView: View {
    let createdBrand: CreateBrandViewModel.CreatedBrand
    let onComplete: () -> Void

    private var descriptionText: String {
        if createdBrand.canDiscoverSeasons {
            return "브랜드 생성이 완료되었습니다. 시즌 후보 탐색과 선택은 다음 단계에서 이어서 진행할 수 있습니다."
        }
        if createdBrand.hasLogoAsset {
            return "브랜드 생성이 완료되었습니다. 브랜드 URL이 없어서 시즌 탐색은 생략했고, 로고 준비도 마무리되었습니다."
        }
        return "브랜드 생성이 완료되었습니다. 브랜드 URL이 없어 시즌 탐색 단계는 건너뛰었습니다."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                Text("브랜드 생성이 완료되었습니다")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text(descriptionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let websiteURL = createdBrand.websiteURL, websiteURL.isEmpty == false {
                Label(websiteURL, systemImage: "link")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                onComplete()
            } label: {
                HStack {
                    Spacer()
                    Text("브랜드 생성 마침")
                        .font(.headline)
                    Spacer()
                }
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(red: 0.98, green: 0.97, blue: 0.94).ignoresSafeArea())
    }
}

private struct CreateBrandDiscoveringView: View {
    let createdBrand: CreateBrandViewModel.CreatedBrand
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                Text("시즌 목록 탐색을 진행합니다")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("\(createdBrand.name) 브랜드 등록이 완료되었습니다. 다음 단계에서 실제 시즌 후보 탐색 API를 연결할 예정이라, 지금은 진행 화면과 선택 화면 구조를 먼저 정리합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let websiteURL = createdBrand.websiteURL, !websiteURL.isEmpty {
                    Label(websiteURL, systemImage: "link")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("브랜드 URL이 비어 있어도 브랜드 등록은 유지됩니다. 이후에는 수동 시즌 URL 등록 경로를 함께 제공할 예정입니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.black)

                Text("브랜드 홈페이지에서 등록 가능한 시즌을 찾고 있습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)

            Button {
                onSkip()
            } label: {
                HStack {
                    Spacer()
                    Text("시즌 선택 단계로 이동")
                        .font(.headline)
                    Spacer()
                }
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(red: 0.98, green: 0.97, blue: 0.94).ignoresSafeArea())
    }
}

private struct CreateBrandCandidateSelectionView: View {
    let createdBrand: CreateBrandViewModel.CreatedBrand
    let onComplete: () -> Void

    @State private var selectedCandidateIDs: Set<String> = []

    private var candidates: [SeasonCandidatePreview] {
        []
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("등록할 시즌을 선택해주세요")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("자동 탐색 결과가 연결되면 이 화면에 등록 가능한 시즌 목록이 표시됩니다. 현재는 화면 구조를 먼저 정리한 단계라 비어 있는 상태를 보여줍니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("등록 가능 시즌")
                        .font(.headline)

                    if candidates.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("아직 표시할 시즌 후보가 없습니다.")
                                .font(.subheadline.weight(.semibold))
                            Text("다음 단계에서 브랜드 URL 기반 후보 탐색 API를 연결하면, 이 영역이 실제 시즌 목록 선택 화면으로 바뀝니다.")
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
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: selectedCandidateIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedCandidateIDs.contains(candidate.id) ? .black : .secondary)

                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(candidate.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Text(candidate.subtitle)
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
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

                Button {
                    onComplete()
                } label: {
                    HStack {
                        Spacer()
                        Text("브랜드 등록 마치기")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
    }

    private func toggleSelection(candidateID: String) {
        if selectedCandidateIDs.contains(candidateID) {
            selectedCandidateIDs.remove(candidateID)
        } else {
            selectedCandidateIDs.insert(candidateID)
        }
    }
}

private struct SeasonCandidatePreview: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
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
