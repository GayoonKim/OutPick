//
//  PhotoPicker.swift
//  OutPick
//
//  Created by 김가윤 on 1/9/26.
//

import SwiftUI
import PhotosUI

struct PhotoPicker: UIViewControllerRepresentable {
    let onPicked: (Data?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: (Data?) -> Void

        init(onPicked: @escaping (Data?) -> Void) {
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let itemProvider = results.first?.itemProvider else {
                onPicked(nil)
                return
            }

            // 한국어 주석: 이미지 데이터를 바로 받아옵니다.
            if itemProvider.canLoadObject(ofClass: UIImage.self) {
                itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    let image = object as? UIImage
                    let data = image?.pngData() ?? image?.jpegData(compressionQuality: 1.0)
                    DispatchQueue.main.async { self.onPicked(data) }
                }
            } else {
                onPicked(nil)
            }
        }
    }
}
