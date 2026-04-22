//
//  CreateBrandFlowView.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import SwiftUI

struct CreateBrandFlowView: View {
    private enum Step: Equatable {
        case form
        case discovering(CreateBrandViewModel.CreatedBrand)
        case candidateSelection(CreateBrandViewModel.CreatedBrand)
    }

    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .form
    @State private var latestCreatedBrand: CreateBrandViewModel.CreatedBrand?
    @State private var discoveryTask: Task<Void, Never>?
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

    var body: some View {
        content
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
                Button(closeConfirmationActionTitle, role: .destructive) {
                    closeFlow()
                }
                Button("계속 진행", role: .cancel) {}
            } message: {
                Text(closeConfirmationMessage)
            }
            .onDisappear {
                discoveryTask?.cancel()
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
                step = .discovering(createdBrand)
                scheduleCandidateSelectionTransition(for: createdBrand)
            }

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

private struct CreateBrandDiscoveringView: View {
    let createdBrand: CreateBrandViewModel.CreatedBrand
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)

            ProgressView()
                .scaleEffect(1.2)
                .tint(.black)

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
