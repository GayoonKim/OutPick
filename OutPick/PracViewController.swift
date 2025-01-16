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
import SwiftUI

class PracViewController: UIViewController, UINavigationControllerDelegate {

    @IBOutlet weak var testImageView0: UIImageView!
    @IBOutlet weak var testImageView1: UIImageView!
    
    @IBOutlet weak var playBtn: UIButton!
    @IBOutlet weak var testProgressView: UIProgressView!
    
    // Firestore 인스턴스
    let db = Firestore.firestore()
    
    // Storage 인스턴스
    let storage = Storage.storage()
    
    private var selectedVideos: [String] = []
    private var selectedImages: [URL] = []
    
    private var convertVideosTask: Task<Void, Error>? = nil
    private var convertImagesTask: Task<Void, Error>? = nil
    
    deinit {
        convertVideosTask?.cancel()
        convertImagesTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let test = ChatRoom(id: UUID().uuidString, roomName: "A", roomDescription: "A", participants: [], creatorID: "A", createdAt: Date())
        db.collection("Test").document("1월").collection("1월 Test").addDocument(data: test.toDictionary())
        
        
        
        
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
                    let imageNames = try await FirebaseStorageManager.shared.uploadImagesToStorage(images: images, location: ImageLocation.Test)
                    let imagesFromStorage = try await FirebaseStorageManager.shared.fetchImagesFromStorage(from: imageNames, location: ImageLocation.Test)
                    
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
        
        if let editedImage = info[.editedImage] as? UIImage {
            self.testImageView0.image = editedImage
        } else if let originalImage = info[.originalImage] as? UIImage {
            self.testImageView0.image = originalImage
        }
        
        dismiss(animated: true)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
    
}

//struct PracViewControllerRepresentable: UIViewControllerRepresentable {
//    
//    func makeUIViewController(context: Context) -> PracViewController {
//        <#code#>
//    }
//    
//    func updateUIViewController(_ uiViewController: PracViewController, context: Context) {
//        <#code#>
//    }
//    
//}
