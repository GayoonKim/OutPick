//
//  LookbookAdminHomeView.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import SwiftUI

struct LookbookAdminHomeView: View {
    private let coordinator: LookbookCoordinator
    private let createBrandFlowFactory: (@escaping (Brand.ID) -> Void) -> AnyView
    private let onCreatedBrand: (Brand.ID) -> Void

    @EnvironmentObject private var brandAdminSessionStore: BrandAdminSessionStore
    @State private var isPresentingCreateBrand = false
    @State private var createdBrandID: Brand.ID?

    init(
        coordinator: LookbookCoordinator,
        createBrandFlowFactory: @escaping (@escaping (Brand.ID) -> Void) -> AnyView,
        onCreatedBrand: @escaping (Brand.ID) -> Void
    ) {
        self.coordinator = coordinator
        self.createBrandFlowFactory = createBrandFlowFactory
        self.onCreatedBrand = onCreatedBrand
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("관리자 콘솔")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                if brandAdminSessionStore.isTotalAdmin {
                    adminActionButton(
                        title: "요청 목록",
                        subtitle: "브랜드 요청 그룹 확인과 처리 상태 변경",
                        systemImage: "tray.full"
                    ) {
                        coordinator.pushAdminBrandRequestGroups()
                    }

                    adminActionButton(
                        title: "브랜드 추가",
                        subtitle: "브랜드 생성, 로고 업로드, 시즌 후보 가져오기",
                        systemImage: "plus"
                    ) {
                        isPresentingCreateBrand = true
                    }
                }

                adminActionButton(
                    title: "브랜드 관리",
                    subtitle: "브랜드 수정, 관리자 추가, 시즌 가져오기 현황 관리",
                    systemImage: "slider.horizontal.3"
                ) {
                    coordinator.pushAdminBrandManagement()
                }
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
        .fullScreenCover(isPresented: $isPresentingCreateBrand, onDismiss: {
            guard let createdBrandID else { return }
            self.createdBrandID = nil
            onCreatedBrand(createdBrandID)
        }) {
            NavigationView {
                createBrandFlowFactory { createdBrandID in
                    self.createdBrandID = createdBrandID
                }
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }

    private func adminActionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
                    .frame(width: 48, height: 48)
                    .background(OutPickTheme.SwiftUIColor.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.iconSecondary)
            }
            .padding(18)
            .background(OutPickTheme.SwiftUIColor.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
