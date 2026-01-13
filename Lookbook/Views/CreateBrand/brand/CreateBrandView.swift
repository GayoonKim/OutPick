//
//  CreateBrandView.swift
//  OutPick
//
//  Created by 김가윤 on 12/20/25.
//

import SwiftUI
import UIKit

struct CreateBrandView: View {

    @StateObject private var viewModel: CreateBrandViewModel
    @State private var isImagePickerPresented: Bool = false

    /// RepositoryProvider 기반으로만 의존성을 주입합니다.
    /// - Note: 화면/상위 조립 계층(AppContainer 등)에서 provider를 내려주는 구조를 유지합니다.
    init(provider: RepositoryProvider = .shared) {
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
                            // 한국어 주석: 선택된 이미지만 제거하고, 피커는 열지 않습니다.
                            viewModel.selectedLogoImage = nil
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
                            } else {
                                Text("Firestore에 저장")
                            }
                            Spacer()
                        }
                    }
                    .disabled(viewModel.isSaving || viewModel.brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let message = viewModel.message {
                    Section {
                        Text(message)
                            .font(.footnote)
                    }
                }

                Section(
                    footer: Text(
                        "주의: 현재는 임시로 Firestore는 brands/{autoId}에 저장하고, 로고 이미지는 StorageService(FirebaseStorageService)를 통해 brands/{autoId}/logo/thumb.jpg(썸네일) + logo/original.jpg(원본) 2개를 업로드한 뒤 Firestore에 logoThumbPath, logoOriginalPath로 저장합니다. (호환을 위해 logoPath에는 썸네일 경로를 넣습니다.)"
                    )
                ) {
                    EmptyView()
                }
            }
            .navigationTitle("브랜드 생성")
            .sheet(isPresented: $isImagePickerPresented) {
                ImagePicker(sourceType: .photoLibrary) { image in
                    // 한국어 주석: 선택한 이미지를 ViewModel 상태에 저장합니다.
                    viewModel.selectedLogoImage = image
                }
            }
        }
    }
}

// MARK: - iOS 15 호환 이미지 피커 (UIImagePickerController)

private struct ImagePicker: UIViewControllerRepresentable {

    let sourceType: UIImagePickerController.SourceType
    let onPicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {

        let onPicked: (UIImage) -> Void

        init(onPicked: @escaping (UIImage) -> Void) {
            self.onPicked = onPicked
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onPicked(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

#Preview {
    CreateBrandView()
}
