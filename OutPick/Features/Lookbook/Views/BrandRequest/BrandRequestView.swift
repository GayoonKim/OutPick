//
//  BrandRequestView.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import SwiftUI

struct BrandRequestView: View {
    @StateObject private var viewModel: BrandRequestViewModel
    private let onSubmitted: () -> Void
    private let coordinator: LookbookCoordinator

    init(
        viewModel: BrandRequestViewModel,
        onSubmitted: @escaping () -> Void,
        coordinator: LookbookCoordinator
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onSubmitted = onSubmitted
        self.coordinator = coordinator
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("브랜드 요청")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                    Text("OutPick은 공식 룩북을 확인할 수 있는 브랜드를 우선 추가해요.")
                        .font(.subheadline)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("브랜드명")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)

                    TextField("공식 브랜드명을 입력하세요", text: $viewModel.brandName)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(OutPickTheme.SwiftUIColor.surfaceBase)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("영문 브랜드명")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)

                    TextField("알고 있다면 공식 영문명을 입력하세요", text: $viewModel.englishBrandName)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(OutPickTheme.SwiftUIColor.surfaceBase)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text("영문명을 함께 입력하면 같은 브랜드 요청을 더 정확히 묶을 수 있어요.")
                        .font(.caption)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textTertiary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    BrandRequestGuideRow(text: "브랜드명은 공식 표기와 최대한 가깝게 입력해주세요.")
                    BrandRequestGuideRow(text: "영문 공식명이 있으면 함께 입력해주세요.")
                    BrandRequestGuideRow(text: "룩북 확인이 어렵거나 브랜드 확인이 어려우면 보류될 수 있어요.")
                    BrandRequestGuideRow(text: "요청 상태는 브랜드 요청 상황에서 확인할 수 있어요.")
                }

                if case .failed(let message) = viewModel.phase {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.warning)
                }

                Button {
                    Task {
                        guard await viewModel.submit() != nil else { return }
                        onSubmitted()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.phase == .submitting {
                            ProgressView()
                                .tint(OutPickTheme.SwiftUIColor.backgroundBase)
                        } else {
                            Text("요청하기")
                                .font(.system(size: 15, weight: .bold))
                        }
                        Spacer()
                    }
                    .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                    .frame(height: 50)
                    .background(
                        viewModel.canSubmit
                            ? OutPickTheme.SwiftUIColor.accent
                            : OutPickTheme.SwiftUIColor.surfaceElevated
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.canSubmit == false)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
        .lookbookNavigationBar(
            title: "",
            showsBackButton: true,
            onBack: { coordinator.pop() }
        )
        .outpickDismissKeyboardOnTap()
    }
}

private struct BrandRequestGuideRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
                .padding(.top, 2)

            Text(text)
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
    }
}
