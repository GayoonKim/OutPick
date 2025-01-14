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
    
    private var convertVideoTask: Task<Void, Error>? = nil
    private var convertImageTask: Task<Void, Error>? = nil
    
    deinit {
        convertVideoTask?.cancel()
        convertImageTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let currentDate = Date()
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: currentDate)
        
        print(currentDate)
        
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
    
//    // Storage에서 이미지 불러오기
//    func fetchVideoFromStorage(video videoName: String, location: VideoLocation) async throws -> UIImage {
//        
//        return try await withCheckedThrowingContinuation { continuation in
//            let imageRef = storage.reference().child("\(location)/\(imageName).jpg")
//            imageRef.getData(maxSize: 1 * 1024 * 1024) { data, error in
//                if let error = error {
//                    
//                    print("\(imageName): 이미지 불러오기 실패: \(error.localizedDescription)")
//                    
//                }
//                    
//                if let data = data,
//                   let image = UIImage(data: data) {
//                 
//                    KingfisherManager.shared.cache.store(image, forKey: imageName)
//                    continuation.resume(returning: image)
//                    
//                }
//            }
//        }
//    }
    
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
            convertVideoTask = Task {
                do {
                    
                    let compressedURLs = try await MediaManager.shared.dealWithVideos(resultsForVideos)
                    
                    self.selectedVideos = try await FirebaseStorageManager.shared.uploadVideosToStorage(compressedURLs)
                    
                } catch {
                    
                    print("비디오 불러오기 실패: \(error.localizedDescription)")
                    
                }
                
                convertVideoTask = nil
                
            }
        }
        
        if !resultsForImages.isEmpty {
            convertImageTask = Task {
                do {
                    
                    let images = try await MediaManager.shared.dealWithImages(resultsForImages)
                    let imageNames = try await FirebaseStorageManager.shared.uploadImagesToStorage(images: images, location: ImageLocation.Test)

                    for imageName in imageNames {
                        print(imageName)
                    }
                    
                } catch {
                    
                    print("이미지 불러오기 실패: \(error.localizedDescription)")
                    
                }
            }
            
            convertImageTask = nil
            
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
