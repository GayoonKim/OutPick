//
//  CreateBrandView.swift
//  OutPick
//
//  Created by 김가윤 on 12/20/25.
//

import SwiftUI
import UIKit
import FirebaseFirestore
import FirebaseStorage

struct CreateBrandView: View {

    // MARK: - 입력 상태
    @State private var brandName: String = ""
    @State private var selectedLogoImage: UIImage? = nil
    @State private var isImagePickerPresented: Bool = false
    @State private var isFeatured: Bool = false

    // MARK: - UI 상태
    @State private var isSaving: Bool = false
    @State private var message: String? = nil

    private let db: Firestore
    private let storage: Storage
    private let thumbnailer: ImageThumbnailing

    /// 기본은 싱글톤 사용, 테스트/교체를 위해 주입 가능
    init(
        db: Firestore = Firestore.firestore(),
        storage: Storage = Storage.storage(),
        thumbnailer: ImageThumbnailing = ImageIOThumbnailer()
    ) {
        self.db = db
        self.storage = storage
        self.thumbnailer = thumbnailer
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("브랜드 정보")) {
                    TextField("브랜드명 (문서 ID로 사용)", text: $brandName)
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

                    if let selectedLogoImage {
                        Image(uiImage: selectedLogoImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                            .cornerRadius(12)
                    } else {
                        Text("선택된 로고 이미지가 없습니다.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    Toggle("피처드", isOn: $isFeatured)
                }

                Section {
                    Button {
                        Task { await saveBrand() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Firestore에 저장")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSaving || brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                    }
                }

                Section(footer: Text("주의: 현재는 임시로 Firestore는 brands/{brand name}에 저장하고, 로고 이미지는 Storage의 brands/{brand name}/logo/thumb.jpg(썸네일) + logo/original.jpg(원본) 2개를 업로드한 뒤 Firestore에 logoThumbPath, logoOriginalPath로 저장합니다. (호환을 위해 logoPath에는 썸네일 경로를 넣습니다.) 브랜드명에 '/' 문자가 포함되면 '_'로 치환되어 저장됩니다.")) {
                    EmptyView()
                }
            }
            .navigationTitle("브랜드 생성")
            .sheet(isPresented: $isImagePickerPresented) {
                ImagePicker(sourceType: .photoLibrary) { image in
                    // 선택한 이미지를 상태에 저장
                    self.selectedLogoImage = image
                }
            }
        }
    }

    // MARK: - 저장 로직

    /// 임시 요구사항: brands/{brand name} 로 저장
    private func saveBrand() async {
        await MainActor.run {
            message = nil
        }

        let rawName = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawName.isEmpty else {
            await MainActor.run {
                message = "브랜드명을 입력해주세요."
            }
            return
        }

        // Firestore 문서 ID에 '/'는 들어갈 수 없어서 안전하게 치환
        let docID = makeDocumentID(from: rawName)

        await MainActor.run {
            isSaving = true
        }
        defer {
            Task { @MainActor in
                isSaving = false
            }
        }

        do {
            // 1) 이미지가 있으면 Storage에 (썸네일 + 원본) 업로드하고 경로 확보
            var logoThumbPath: String? = nil
            var logoOriginalPath: String? = nil

            if let image = await MainActor.run(body: { selectedLogoImage }) {
                let thumbPath = "brands/\(docID)/logo/thumb.jpg"
                let originalPath = "brands/\(docID)/logo/original.jpg"

                // 원본 업로드 (화질 우선)
                guard let originalJPEGData = image.jpegData(compressionQuality: 0.9) else {
                    throw NSError(domain: "CreateBrandView", code: -10, userInfo: [
                        NSLocalizedDescriptionKey: "원본 이미지를 JPEG 데이터로 변환하지 못했습니다."
                    ])
                }

                try await uploadData(originalJPEGData, toPath: originalPath, contentType: "image/jpeg")
                logoOriginalPath = originalPath

                // 썸네일 생성(ImageIOThumbnailer 사용) 후 업로드 (목록/카드용)
                let policy = ThumbnailPolicies.brandLogoList
                let thumbJPEGData = try thumbnailer.makeThumbnailJPEGData(from: originalJPEGData, policy: policy)

                try await uploadData(thumbJPEGData, toPath: thumbPath, contentType: "image/jpeg")
                logoThumbPath = thumbPath
            }

            // 2) Firestore에 저장
            let data: [String: Any] = [
                "name": rawName,

                // 호환: 기존 UI가 logoPath만 읽는 경우를 대비해 썸네일 경로를 넣어둡니다.
                "logoPath": logoThumbPath ?? NSNull(),

                // 신규: 썸네일/원본을 분리 저장
                "logoThumbPath": logoThumbPath ?? NSNull(),
                "logoOriginalPath": logoOriginalPath ?? NSNull(),

                "isFeatured": isFeatured,
                "likeCount": 0,
                "viewCount": 0,
                "popularScore": 0.0,
                "updatedAt": FieldValue.serverTimestamp()
            ]

            try await db
                .collection("brands")
                .document(docID)
                .setDataAsync(data, merge: true)

            await MainActor.run {
                message = "저장 완료: brands/\(docID)"
            }
        } catch {
            await MainActor.run {
                message = "저장 실패: \(error.localizedDescription)"
            }
        }
    }

    /// Firebase Storage에 데이터를 업로드합니다.
    /// - Note: 동일 경로로 업로드하면 덮어쓰기(업데이트) 됩니다.
    private func uploadData(_ data: Data, toPath path: String, contentType: String) async throws {
        let ref = storage.reference(withPath: path)
        let metadata = StorageMetadata()
        metadata.contentType = contentType

        _ = try await ref.putDataAsync(data, metadata: metadata)
    }

    /// Firestore 문서 ID로 쓰기 위해 최소한의 정리만 수행
    private func makeDocumentID(from name: String) -> String {
        // '/'는 컬렉션 경로 구분자라서 사용 불가
        let replaced = name.replacingOccurrences(of: "/", with: "_")
        // 너무 공격적으로 바꾸지는 않고, 앞뒤 공백만 제거
        return replaced.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Firestore async 호환 (setData completion -> async/await)

private extension DocumentReference {
    /// Firebase 버전에 따라 setData의 async 지원이 없을 수 있어, 안전하게 브릿지합니다.
    func setDataAsync(_ documentData: [String: Any], merge: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.setData(documentData, merge: merge) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

// MARK: - Firebase Storage async 호환 (putData completion -> async/await)

private extension StorageReference {
    /// Firebase 버전에 따라 putData의 async 지원이 없을 수 있어, 안전하게 브릿지합니다.
    func putDataAsync(_ uploadData: Data, metadata: StorageMetadata?) async throws -> StorageMetadata {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StorageMetadata, Error>) in
            self.putData(uploadData, metadata: metadata) { metadata, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let metadata else {
                    continuation.resume(throwing: NSError(domain: "CreateBrandView", code: -2, userInfo: [
                        NSLocalizedDescriptionKey: "업로드 메타데이터를 받지 못했습니다."
                    ]))
                    return
                }
                continuation.resume(returning: metadata)
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

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
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
