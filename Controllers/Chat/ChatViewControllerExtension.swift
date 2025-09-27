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
import AVKit
import FirebaseStorage
import AVFoundation

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
        
        // // 720p 표준: .standard720
        // 데이터 절약 모드: .dataSaver720
        // 1080p 고화질: .high1080
        if !resultsForVideos.isEmpty {
            convertVideosTask = Task {
                for result in resultsForVideos {
                    // 비디오별 진행 HUD 생성
                    var hud: CircularProgressHUD?
                    await MainActor.run {
                        let h = CircularProgressHUD.show(in: self.view, title: nil)
                        h.setProgress(0.0) // 시작점
                        hud = h
                    }
                    do {
                        // 1) 비디오 개별 변환 (한 메시지 = 한 동영상)
                        let url = try await MediaManager.shared.convertVideo(result, preset: .standard720)
                        
                        // 2) 방 식별 후 업로드+브로드캐스트 (메타만 소켓으로 전송)
                        if let room = self.room {
                            let roomID = room.ID ?? ""
                            await self.uploadCompressedVideoAndBroadcast(
                                roomID: roomID,
                                compressedURL: url,
                                preset: .standard720,
                                hud: hud
                            )
                        } else {
                            await MainActor.run {
                                hud?.dismiss()
                                AlertManager.showAlertNoHandler(
                                    title: "방 정보를 찾을 수 없습니다",
                                    message: "동영상을 전송할 방이 없습니다.",
                                    viewController: self
                                )
                            }
                        }
                        
                    } catch {
                        await MainActor.run {
                            hud?.dismiss()
                            AlertManager.showAlertNoHandler(
                                title: "비디오 변환 실패",
                                message: "압축 중 오류가 발생했습니다.\n\(error.localizedDescription)",
                                viewController: self
                            )
                        }
                        // 다음 비디오 계속 처리
                        continue
                    }
                }
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

// MARK: -  video 관련
extension ChatViewController {
    func uploadCompressedVideoAndBroadcast(roomID: String,
                                           compressedURL: URL,
                                           preset: MediaManager.VideoUploadPreset,
                                           hud: CircularProgressHUD? = nil) async {
        let messageID = UUID().uuidString
        let basePath = "videos/\(roomID)/\(messageID)"
        let videoPath = "\(basePath)/video.mp4"
        let thumbPath = "\(basePath)/thumb.jpg"
        
        // HUD 확보(주입받았으면 재사용, 없으면 생성)
        var localHUD: CircularProgressHUD? = hud
        if localHUD == nil {
            await MainActor.run {
                let h = CircularProgressHUD.show(in: self.view, title: nil)
                h.setProgress(0.0)
                localHUD = h
            }
        } else {
            await MainActor.run {
                localHUD?.setProgress(0.0)
            }
        }
        
        // 메타 추출
        let asset = AVAsset(url: compressedURL)
        let duration = CMTimeGetSeconds(asset.duration)
        var width = 0, height = 0
        if let track = asset.tracks(withMediaType: .video).first {
            let n = track.naturalSize, t = track.preferredTransform
            let portrait = (t.a == 0 && abs(t.b) == 1 && abs(t.c) == 1 && t.d == 0)
            let res = portrait ? CGSize(width: n.height, height: n.width) : n
            width = Int((res.width / 2).rounded(.down) * 2)
            height = Int((res.height / 2).rounded(.down) * 2)
        }
        let sizeBytes = (try? FileManager.default.attributesOfItem(atPath: compressedURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        let approxBitrateMbps = duration > 0 ? (Double(sizeBytes) * 8.0 / duration) / 1_000_000.0 : 0
        
        // 썸네일 생성
        let thumbData: Data = (try? makeVideoThumbnailData(url: compressedURL, maxPixel: 720)) ?? Data()
        
        do {
            // 1) 비디오 업로드
            try await FirebaseStorageManager.shared.putVideoFileToStorage(localURL: compressedURL, path: videoPath, contentType: "video/mp4") { fraction in
                Task { @MainActor in
                    localHUD?.setProgress(fraction)
                }
            }
            
            // 2) 썸네일 업로드
            if !thumbData.isEmpty {
                try await FirebaseStorageManager.shared.putVideoDataToStorage(data: thumbData, path: thumbPath, contentType: "image/jpeg")
            }
            
            // 3) 메타 브로드캐스트 (바이너리 X)
            let payload = VideoMetaPayload(
                roomID: roomID,
                messageID: messageID,
                storagePath: videoPath,
                thumbnailPath: thumbPath,
                duration: duration,
                width: width, height: height,
                sizeBytes: sizeBytes,
                approxBitrateMbps: approxBitrateMbps,
                preset: preset.code
            )
            SocketIOManager.shared.sendVideo(roomID: roomID, payload: payload)
            await MainActor.run { localHUD?.dismiss() }
        } catch {
            await MainActor.run { localHUD?.dismiss() }
            await MainActor.run {
                AlertManager.showAlertNoHandler(
                    title: "업로드 실패",
                    message: error.localizedDescription,
                    viewController: self
                )
            }
            
            // 실패 메시지를 로컬 UI에 표시
            let thumbData: Data = (try? makeVideoThumbnailData(url: compressedURL, maxPixel: 720)) ?? Data()
            SocketIOManager.shared.sendFailedVideos(
                roomID: roomID,
                senderID: LoginManager.shared.getUserEmail,
                senderNickname: LoginManager.shared.currentUserProfile?.nickname ?? "",
                localURL: compressedURL,
                thumbData: thumbData,
                duration: duration,
                width: width,
                height: height,
                presetCode: preset.code
            )
        }
    }
    
    
    
    // 썸네일 생성(첫 프레임)
    func makeVideoThumbnailData(url: URL, maxPixel: CGFloat) throws -> Data {
        let asset = AVAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        let cg = try gen.copyCGImage(at: .zero, actualTime: nil)
        let ui = UIImage(cgImage: cg)
        let scaled = ui.resizeMaxPixel(maxPixel) // 간단한 UIImage 확장 메서드로 축소
        return scaled.jpegData(compressionQuality: 0.8) ?? Data()
    }
    
    
    
    fileprivate func previewCompressedVideo(_ url: URL) {
        let player = AVPlayer(url: url)
        let playerVC = AVPlayerViewController()
        playerVC.player = player
        playerVC.modalPresentationStyle = .formSheet
        if let sheet = playerVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        self.present(playerVC, animated: true) {
            player.play()
        }
    }
}

// Stable string codes for payload logging/analytics
private extension MediaManager.VideoUploadPreset {
    var code: String {
        switch self {
        case .standard720: return "standard720"
        case .dataSaver720: return "dataSaver720"
        case .high1080:    return "high1080"
        }
    }
}

// MARK: - UIImage resizing helper
extension UIImage {
    /// Longer side will be resized to `maxPixel` while preserving aspect ratio.
    /// If the image is already within bounds or `maxPixel` <= 0, returns self.
    func resizeMaxPixel(_ maxPixel: CGFloat) -> UIImage {
        guard maxPixel > 0 else { return self }
        let w = size.width
        let h = size.height
        guard w > 0, h > 0 else { return self }
        let longSide = max(w, h)
        guard longSide > maxPixel else { return self }

        let scaleRatio = maxPixel / longSide
        var newW = floor(w * scaleRatio)
        var newH = floor(h * scaleRatio)
        // enforce even pixels (some encoders prefer multiples of 2)
        newW = max(2, floor(newW / 2) * 2)
        newH = max(2, floor(newH / 2) * 2)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1   // 1 point == 1 pixel in the output
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: newW, height: newH), format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(x: 0, y: 0, width: newW, height: newH))
        }
    }
}
