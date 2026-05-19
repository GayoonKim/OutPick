//
//  CreateSeasonFromURLView.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import SwiftUI

struct CreateSeasonFromURLView: View {
    @StateObject private var viewModel: CreateSeasonFromURLViewModel
    @Environment(\.dismiss) private var dismiss

    let onCompleted: (SeasonImportRequestReceipt) -> Void

    init(
        viewModel: CreateSeasonFromURLViewModel,
        onCompleted: @escaping (SeasonImportRequestReceipt) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onCompleted = onCompleted
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("가져오고 싶은 시즌 상세 페이지 URL을 입력해주세요.")
                    Text("현재 단계에서는 시즌 URL import job 생성까지만 연결되어 있습니다. 실제 수집 워커는 다음 단계에서 이어서 붙일 예정입니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("안내")
                }

                Section(header: Text("시즌 URL")) {
                    TextField(
                        "예: https://brand.com/collections/fall-winter-2025",
                        text: $viewModel.seasonURLText
                    )
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task {
                            guard let receipt = await viewModel.requestImport() else { return }
                            onCompleted(receipt)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text(viewModel.isSaving ? "요청 생성 중..." : "등록 요청 생성")
                            Spacer()
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            .tint(.black)
            .navigationTitle("시즌 URL로 등록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
    }
}
