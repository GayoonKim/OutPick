//
//  CreateBrandView.swift
//  OutPick
//
//  Created by 김가윤 on 12/20/25.
//

import SwiftUI
import UIKit
import PhotosUI

struct CreateBrandView: View {

    @StateObject private var viewModel: CreateBrandViewModel
    @State private var isImagePickerPresented: Bool = false

    /// RepositoryProvider 기반으로만 의존성을 주입합니다.
    /// - Note: 화면/상위 조립 계층(AppContainer 등)에서 provider를 내려주는 구조를 유지합니다.
    init(provider: LookbookRepositoryProvider = .shared) {
        _viewModel = StateObject(
            wrappedValue: CreateBrandViewModel(
                brandStore: provider.brandStore,
                storageService: provider.storageService,
                thumbnailer: provider.thumbnailer
            )
        )
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("브랜드 정보")) {
                    TextField("브랜드명", text: $viewModel.brandName)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)

                    Button {
                        isImagePickerPresented = true
                    } label: {
                        HStack {
                            Text("로고 이미지 선택")
                            Spacer()
                            Image(systemName: "photo")
                        }
                    }

                    if let selectedLogoImage = viewModel.selectedLogoImage {
                        Image(uiImage: selectedLogoImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                            .cornerRadius(12)

                        Button(role: .destructive) {
                            viewModel.clearPickedLogo()
                        } label: {
                            Text("로고 이미지 제거")
                        }
                    } else {
                        Text("선택된 로고 이미지가 없습니다.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    Toggle("피처드", isOn: $viewModel.isFeatured)
                }

                Section {
                    Button {
                        Task { await viewModel.saveBrand() }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isSaving {
                                ProgressView()
                            } else { Text("브랜드 생성") }
                            Spacer()
                        }
                    }
                    .disabled(
                        viewModel.isSaving ||
                        viewModel.brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                if let message = viewModel.message {
                    Section {
                        Text(message)
                            .font(.footnote)
                    }
                }

                Section(
                    footer: Text(
                        "브랜드 내부 ID는 자동 생성되며, 동일한 브랜드명은 중복 등록할 수 없습니다."
                    )
                ) {
                    EmptyView()
                }
            }
            .navigationTitle("브랜드 생성")
            .sheet(isPresented: $isImagePickerPresented) {
                BrandLogoPicker { picked in
                    viewModel.setPickedLogo(
                        thumbImage: picked.thumbImage,
                        thumbData: picked.thumbData,
                        detailData: picked.detailData
                    )
                } onFailed: { error in
                    viewModel.message = "로고 이미지 처리 실패: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - iOS 15 호환 이미지 피커 (PHPickerViewController)

private struct BrandLogoPickResult {
    let thumbImage: UIImage
    let thumbData: Data
    let detailData: Data
}

private struct BrandLogoPicker: UIViewControllerRepresentable {

    let onPicked: (BrandLogoPickResult) -> Void
    let onFailed: (Error) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onFailed: onFailed)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {

        let onPicked: (BrandLogoPickResult) -> Void
        let onFailed: (Error) -> Void

        init(
            onPicked: @escaping (BrandLogoPickResult) -> Void,
            onFailed: @escaping (Error) -> Void
        ) {
            self.onPicked = onPicked
            self.onFailed = onFailed
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let first = results.first else { return }

            Task {
                do {
                    let pair = try await DefaultMediaProcessingService.shared.makePair(from: first, index: 0)
                    defer { try? FileManager.default.removeItem(at: pair.originalFileURL) }

                    guard let thumbImage = UIImage(data: pair.thumbData) else {
                        throw NSError(
                            domain: "BrandLogoPicker",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "썸네일 이미지 생성에 실패했습니다."]
                        )
                    }
                    let detailPolicy = ThumbnailPolicies.brandLogoDetail
                    guard
                        let detailData = DefaultMediaProcessingService.makeThumbnailData(
                            from: pair.originalFileURL,
                            maxPixel: detailPolicy.maxPixelSize,
                            quality: detailPolicy.quality
                        )
                    else {
                        throw NSError(
                            domain: "BrandLogoPicker",
                            code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "확대용 이미지 생성에 실패했습니다."]
                        )
                    }

                    await MainActor.run {
                        onPicked(
                            BrandLogoPickResult(
                                thumbImage: thumbImage,
                                thumbData: pair.thumbData,
                                detailData: detailData
                            )
                        )
                    }
                } catch {
                    await MainActor.run {
                        onFailed(error)
                    }
                }
            }
        }
    }
}

#Preview {
    CreateBrandView()
}
