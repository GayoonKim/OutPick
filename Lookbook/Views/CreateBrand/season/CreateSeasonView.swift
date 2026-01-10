//
//  CreateSeasonView.swift
//  OutPick
//
//  Created by 김가윤 on 1/9/26.
//

//
//  CreateSeasonView.swift
//  OutPick
//
//  Created by 김가윤 on 1/9/26.
//

//
//  CreateSeasonView.swift
//  OutPick
//
//  Created by 김가윤 on 1/9/26.
//

//
//  CreateSeasonView.swift
//  OutPick
//
//  Created by 김가윤 on 1/9/26.
//

import SwiftUI
import UIKit

struct CreateSeasonView: View {

    @StateObject private var viewModel: CreateSeasonViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isPhotoPickerPresented: Bool = false

    // iOS 15 지원. 검색창 포커스로 키보드 제어
    @FocusState private var isQueryFocused: Bool

    init(viewModel: CreateSeasonViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("시즌 정보")) {
                    TextField("연도 (예: 2025)", text: $viewModel.yearText)
                        .keyboardType(.numberPad)

                    Picker("시즌", selection: $viewModel.term) {
                        Text("F/W").tag(SeasonTerm.fw)
                        Text("S/S").tag(SeasonTerm.ss)
                    }

                    TextField("설명(선택)", text: $viewModel.descriptionText)
                }

                Section(header: Text("무드/태그 검색")) {
                    TextField("검색 (예: 미니멀 / 스트리트 / 고프코어)", text: $viewModel.query)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .focused($isQueryFocused)
                        .onChange(of: viewModel.query) { _ in
                            // 디바운스/취소/스킵은 ViewModel이 담당
                            viewModel.onQueryChanged()
                        }

                    if viewModel.isSearching {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("검색 중...")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !viewModel.conceptSuggestions.isEmpty {
                        Text("추천 무드")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        ForEach(viewModel.conceptSuggestions, id: \.id) { c in
                            Button {
                                // 추천 탭 시 키보드 내리기
                                isQueryFocused = false
                                viewModel.addConcept(c)
                            } label: {
                                HStack {
                                    Text(c.displayName)
                                    Spacer()
                                }
                            }
                        }
                    }

                    if !viewModel.tagSuggestions.isEmpty {
                        Text("추천 태그")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        ForEach(viewModel.tagSuggestions, id: \.id.value) { t in
                            Button {
                                // 추천 탭 시 키보드 내리기
                                isQueryFocused = false
                                viewModel.addTag(t)
                            } label: {
                                HStack {
                                    Text(t.name)
                                    Spacer()
                                }
                            }
                        }
                    }
                }

                Section(header: Text("커버(선택)")) {

                    if let data = viewModel.coverImageData,
                       let uiImage = UIImage(data: data) {

                        VStack(alignment: .leading, spacing: 12) {

                            // ✅ 세로로 긴 이미지는 상단 기준으로 더 자연스럽게 크롭
                            TopAlignedCroppedImage(uiImage: uiImage, height: 180)
                                .cornerRadius(12)

                            HStack(spacing: 12) {

                                Button {
                                    isPhotoPickerPresented = true
                                } label: {
                                    HStack {
                                        Image(systemName: "photo")
                                        Text("이미지 변경")
                                    }
                                }
                                .buttonStyle(.borderless)

                                Spacer()

                                Button(role: .destructive) {
                                    // 한국어 주석: Form에서 버튼 충돌 방지용 안전장치
                                    isPhotoPickerPresented = false
                                    viewModel.coverImageData = nil
                                } label: {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("제거")
                                    }
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                    } else {

                        Button {
                            isPhotoPickerPresented = true
                        } label: {
                            HStack {
                                Image(systemName: "photo")
                                Text("이미지 선택")
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                
                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                // ✅ 저장 버튼은 맨 아래
                Section {
                    Button {
                        Task {
                            let created = await viewModel.save()
                            if created != nil {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text(viewModel.isSaving ? "저장 중..." : "저장")
                            Spacer()
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            // ✅ 스크롤 시작 시 자동으로 닫기 (탭 충돌 없음)
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { _ in
                        let shouldDismiss =
                        isQueryFocused ||
                        !viewModel.conceptSuggestions.isEmpty ||
                        !viewModel.tagSuggestions.isEmpty

                        guard shouldDismiss else { return }

                        // 스크롤 시작 시 키보드 + 추천 목록 닫기
                        isQueryFocused = false
                        viewModel.dismissSearchUI()
                    }
            )
            .navigationTitle("시즌 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
            .sheet(isPresented: $isPhotoPickerPresented) {
                PhotoPicker { data in
                    viewModel.coverImageData = data
                }
            }
        }
    }
}

/// 세로로 긴 사진은 상단을 우선 노출하고, 그 외는 중앙 크롭으로 자연스럽게 보이게 하는 뷰
struct TopAlignedCroppedImage: View {

    let uiImage: UIImage
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let containerSize = CGSize(width: proxy.size.width, height: height)
            let imageSize = uiImage.size

            // 한국어 주석: 원본 비율 유지(Aspect Fill) 스케일 계산
            let scale = max(containerSize.width / imageSize.width,
                            containerSize.height / imageSize.height)

            let scaledSize = CGSize(width: imageSize.width * scale,
                                    height: imageSize.height * scale)

            // 한국어 주석: 세로로 “긴” 경우(이미지가 컨테이너보다 더 세로로 긴 경우)에는 top align,
            // 그 외(가로형/덜 세로형)는 center crop이 자연스럽습니다.
            let isTall = (imageSize.height / imageSize.width) > (containerSize.height / containerSize.width)

            Image(uiImage: uiImage)
                .resizable()
                .frame(width: scaledSize.width, height: scaledSize.height)
                // 한국어 주석: position을 이용해 오프셋을 정밀하게 제어합니다.
                // - x: 가운데 정렬
                // - y: 세로로 긴 사진은 top이 0에 오도록(= y를 scaledHeight/2)
                //      그렇지 않으면 가운데(= containerHeight/2)
                .position(
                    x: containerSize.width / 2,
                    y: isTall ? (scaledSize.height / 2) : (containerSize.height / 2)
                )
                .clipped()
        }
        // 한국어 주석: GeometryReader가 높이를 잃지 않도록 고정
        .frame(height: height)
        .clipped()
    }
}
