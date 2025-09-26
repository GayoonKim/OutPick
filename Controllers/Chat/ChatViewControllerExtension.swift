//
//  ChatExtension.swift
//  OutPick
//
//  Created by 김가윤 on 1/16/25.
//

import Foundation
import UIKit
import PhotosUI
import Kingfisher

// 내비게이션 아이템 타이틀 설정
extension UINavigationItem {
    func setTitle(title: String, subtitle: String) {
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 17)
        titleLabel.sizeToFit()
        
        let subTitleLabel = UILabel()
        subTitleLabel.text = subtitle
        subTitleLabel.font = UIFont.systemFont(ofSize: 12)
        subTitleLabel.textAlignment = .center
        subTitleLabel.sizeToFit()
        
        let stackView = UIStackView(arrangedSubviews: [titleLabel, subTitleLabel])
        stackView.distribution = .equalCentering
        stackView.axis = .vertical
        stackView.alignment = .center
        
        let width = max(titleLabel.frame.size.width, subTitleLabel.frame.size.width)
        stackView.frame = CGRect(x: 0, y: 0, width: width, height: 35)
        
        titleLabel.sizeToFit()
        subTitleLabel.sizeToFit()
        
        self.titleView = stackView
        
    }
}

extension UITextView {
    func alignTextVertically() {
        
        var topConstraint = (self.bounds.size.height - (self.contentSize.height)) / 2
        topConstraint = topConstraint < 0.0 ? 0.0 : topConstraint
        self.contentInset.left = 5
        self.contentInset.top = topConstraint
        
    }
}

extension ChatViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        
        // 터치된 뷰가 UIButton일 경우 제스처 제외
        if let touchedView = touch.view, touchedView is UIButton {
            return false
        }
        
        if let excludeView = touch.view, excludeView.tag == 99 || excludeView.tag == 98 {
            return false
        }
        
        return true
        
    }
}

extension ChatViewController: PHPickerViewControllerDelegate {
    private enum PickerConst { static let maxImagesPerMessage = 30 }
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        var resultsForVideos: [PHPickerResult] = []
        var resultsForImages: [PHPickerResult] = []
        
        for result in results {
            let itemProvider = result.itemProvider
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                resultsForVideos.append(result)
            } else if itemProvider.canLoadObject(ofClass: UIImage.self) {
                resultsForImages.append(result)
            }
        }
        
        if !resultsForImages.isEmpty {
            let imageResults = resultsForImages
            
            // 30장씩 배치 전송
            let total = imageResults.count
            let chunkSize = PickerConst.maxImagesPerMessage
            let chunks: [[PHPickerResult]] = stride(from: 0, to: total, by: chunkSize).map { start in
                let end = min(start + chunkSize, total)
                return Array(imageResults[start..<end])
            }
            
            if chunks.count > 1 {
                Task { @MainActor in
                    let lastCount = total % chunkSize == 0 ? chunkSize : total % chunkSize
                    AlertManager.showAlertNoHandler(
                        title: "이미지 다중 전송",
                        message: "총 \(total)장을 \(chunkSize)장 + \(lastCount)장으로 나눠 \(chunks.count)개의 메시지로 전송합니다.",
                        viewController: self
                    )
                }
            }
            
            convertImagesTask = Task {
                do {
                    for chunk in chunks {
                        try Task.checkCancellation()
                        
                        // 1) PHPickerResult 배열 -> [ImagePair] (썸네일 Data + 원본 파일URL + 메타)
                        let pairs = try await MediaManager.shared.preparePairs(chunk)
                        
                        // 2) 메시지/폴더 경로 식별자 준비
                        guard let room = self.room else { continue }
                        let roomID = room.ID ?? ""
                        let messageID = UUID().uuidString  // 멱등 식별자(서버에서 대체 가능)

                        // Show HUD
                        let hud = CircularProgressHUD.show(in: self.view, title: nil)
                        hud.setProgress(0.0)

                        do {
                            let attachments = try await FirebaseStorageManager.shared.uploadPairsToRoomMessage(
                                pairs,
                                roomID: roomID,
                                messageID: messageID,
                                cacheTTLThumbDays: 30,
                                cacheTTLOriginalDays: 7,
                                cleanupTemp: true,
                                onProgress: { fraction in
                                    Task { @MainActor in
                                        hud.setProgress(fraction)
                                    }
                                }
                            )
                            
                            // Hide HUD
                            Task { @MainActor in hud.dismiss() }

                            // 3) 소켓/DB 전송: 메타만 (바이너리 X)
                            let payload = attachments.map { $0.toDict() }
                            SocketIOManager.shared.sendImages(room, payload)

                        } catch {
                            Task { @MainActor in hud.dismiss() }
                            
                            for pair in pairs {
                                guard let img = UIImage(data: pair.thumbData) else { return }
                                
                                let cache = KingfisherManager.shared.cache
                                try await cache.store(img, original: nil, forKey: pair.sha256)
                                
                                print(#function, "KingFisher cache saved: \(pair.sha256)")
                            }
                            SocketIOManager.shared.sendFailedImages(room, fromPairs: pairs)
                            
                            print("업로드 실패:", error)
                        }
                    }
                } catch MediaError.FailedToConvertImage {
                    AlertManager.showAlertNoHandler(title: "이미지 변환 실패", message: "이미지를 다시 선택해 주세요/", viewController: self)
                } catch StorageError.FailedToUploadImage {
                    print("이미지 업로드 실패")
                } catch StorageError.FailedToFetchImage {
                    print("이미지 불러오기 실패")
                } catch {
                    print("알 수 없는 오류: \(error)")
                }
            }
            
            convertImagesTask = nil
            
            if !resultsForVideos.isEmpty {
            }
            
        }
    }
}

extension ChatViewController: UIImagePickerControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
//        if let editedImage = info[.editedImage] as? UIImage {
//
//        } else if let originalImage = info[.originalImage] as? UIImage {
//
//        }
        dismiss(animated: true)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
