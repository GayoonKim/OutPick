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
    
    private let url =
    ["https://firebasestorage.googleapis.com:443/v0/b/outpick-664ae.appspot.com/o/roomImages%2F89F79D4E-C60D-432E-832C-31B8A5DE6C8C.jpg?alt=media&token=63ddac2a-6aab-4e3f-91b0-44ea399c08f4",
     "https://firebasestorage.googleapis.com:443/v0/b/outpick-664ae.appspot.com/o/profileImages%2FF123AE8D-428D-4FE4-8881-8612544B43C9.jpg?alt=media&token=3ded1f50-cde4-4a48-852d-d4ade85b6d17"]
    
    // Firestore 인스턴스
    let db = Firestore.firestore()
    
    // Storage 인스턴스
    let storage = Storage.storage()
    
    private var selectedVideos: [URL] = []
    private var selectedImages: [URL] = []
    
    private var convertVideoTask: Task<Void, Error>? = nil
    private var convertImageTask: Task<Void, Error>? = nil
    
    deinit {
        convertVideoTask?.cancel()
        convertImageTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
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
            convertVideoTask = Task {
                do {
                    
                    let compressedURLs = try await MediaManager.shared.dealWithVideos(resultsForVideos)
                    
                    self.selectedVideos = try await FirebaseMediaManager.shared.uploadVideosToStorage(compressedURLs)
                    
                    for video in selectedVideos {
                        DispatchQueue.main.async {
                            self.playVideo(from: video)
                        }
                    }
                    
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
                    print("dealWithImages 끝")
                    
                    for image in images {
                        self.testImageView0.image = image
                    }
                    
                    let _ = try await FirebaseMediaManager.shared.uploadImagesToStorage(images)
                    
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
