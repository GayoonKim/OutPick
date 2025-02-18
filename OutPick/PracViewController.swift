//
//  PracViewController.swift
//  OutPick
//
//  Created by 김가윤 on 1/3/25.
//

import UIKit
import AVKit
import Foundation
import AVFoundation
import Alamofire
import PhotosUI
import Kingfisher
import Firebase
import FirebaseStorage

class PracViewController: UIViewController, UINavigationControllerDelegate {
    
    @IBOutlet weak var sendBtn: UIButton!
    
    // Firestore 인스턴스
    let db = Firestore.firestore()
    
    // Storage 인스턴스
    let storage = Storage.storage()
    
    private var selectedVideos: [String] = []
    private var selectedImages: [URL] = []
    
    private var convertVideosTask: Task<Void, Error>? = nil
    private var convertImagesTask: Task<Void, Error>? = nil
    
    deinit {
        convertImagesTask?.cancel()
        convertVideosTask?.cancel()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        Task {
            do {
                
                let room_snapshot = try await db.collection("Rooms").document("2월").collection("2월 Rooms").whereField("roomName", isEqualTo: "Test").limit(to: 1).getDocuments()
                guard let roomDocument = room_snapshot.documents.first else {
                    print("방 문서 불러오기 실패")
                    return
                }
                let room_ref = roomDocument.reference
                
                let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                
                    
                    
                    return nil
                })
                
            } catch {
                
            }
        }

    }
    
    @IBAction func sendBtnTapped(_ sender: UIButton) {
        
        
        
    }
    

    
    @IBAction func albumBtnTapped(_ sender: UIButton) {
        openPHPicker()
    }
    
    private func openPHPicker() {
        
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 0
        configuration.selection = .ordered
        configuration.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
        
    }
    
    func playVideo(from url: URL) {
        
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        
        present(playerViewController, animated: true) {
            player.play()
        }
        
    }
    
}

extension PracViewController: PHPickerViewControllerDelegate {
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        
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
        
        if !resultsForVideos.isEmpty {
            convertVideosTask = Task {
                do {
                    
                    let compressedURLs = try await MediaManager.shared.dealWithVideos(resultsForVideos)
                    if let url = compressedURLs.first {
                        self.playVideo(from: url)
                    }
                    self.selectedVideos = try await FirebaseStorageManager.shared.uploadVideosToStorage(compressedURLs)
                    
                } catch {
                    
                    print("비디오 불러오기 실패: \(error.localizedDescription)")
                    
                }
                
                convertVideosTask = nil
                
            }
        }
        
        if !resultsForImages.isEmpty {
            convertImagesTask = Task {
                do {
                    
                    let images = try await MediaManager.shared.dealWithImages(resultsForImages)
                    for image in images {
                        
                        Task {
                            try await FirebaseStorageManager.shared.uploadImageToStorage(image: image, location: ImageLocation.Test)
                        }
                    }
                    
                    
                } catch MediaError.FailedToConvertImage {
                    
                    AlertManager.showAlert(title: "이미지 변환 실패", message: "이미지를 다시 선택해 주세요/", viewController: self)
                    
                } catch StorageError.FailedToUploadImage {
                    
                    print("이미지 업로드 실패")
                    
                } catch StorageError.FailedToFetchImage {
                    
                    print("이미지 불러오기 실패")
                    
                }
            }
            
            convertImagesTask = nil
            
        }
        
    }
    
}


extension PracViewController: UIImagePickerControllerDelegate {
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        
//        if let editedImage = info[.editedImage] as? UIImage {
//            self.testImageView0.image = editedImage
//        } else if let originalImage = info[.originalImage] as? UIImage {
//            self.testImageView0.image = originalImage
//        }
        
        dismiss(animated: true)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
    
}

extension FourCharCode {
    // Create a string representation of a FourCC.
    func toString() -> String {
        let bytes: [CChar] = [
            CChar((self >> 24) & 0xff),
            CChar((self >> 16) & 0xff),
            CChar((self >> 8) & 0xff),
            CChar(self & 0xff),
            0
        ]
        let result = String(cString: bytes)
        let characterSet = CharacterSet.whitespaces
        return result.trimmingCharacters(in: characterSet)
    }
}
