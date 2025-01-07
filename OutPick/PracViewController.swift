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
    
    private let url =
    ["https://firebasestorage.googleapis.com:443/v0/b/outpick-664ae.appspot.com/o/roomImages%2F0A96E637-8DDC-4CE0-A807-A85F105182DF.jpg?alt=media&token=b5064cda-72c5-4a84-812c-f0bb2355aa10",
     "https://firebasestorage.googleapis.com:443/v0/b/outpick-664ae.appspot.com/o/profileImages%2FF123AE8D-428D-4FE4-8881-8612544B43C9.jpg?alt=media&token=3ded1f50-cde4-4a48-852d-d4ade85b6d17"]
    
    // Firestore 인스턴스
    let db = Firestore.firestore()
    
    // Storage 인스턴스
    let storage = Storage.storage()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
//        Task {
//            
//            let results = try await fetchImages(from: self.url)
//            
//            DispatchQueue.main.async {
//                self.testImageView0.image = results[0]
//                self.testImageView1.image = results[1]
//            }
//            
//        }
        
    }
    
    private func generateThumbnail(from url: URL, at time: CMTime = CMTime(seconds: 1, preferredTimescale: 600)) -> UIImage? {
        
        let asset = AVAsset(url: url)
        let assetImageGenerator = AVAssetImageGenerator(asset: asset)
        assetImageGenerator.appliesPreferredTrackTransform = true
        
        do {
            let cgImage = try assetImageGenerator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("Error generating thumbnail: \(error.localizedDescription)")
                    return nil
        }
        
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
    
    @IBAction func playBtnTapped(_ sender: UIButton) {
        
        if let videoURL = URL(string: "https://youtu.be/DiyBJqGTmgE?si=cF51ZBiT5fNzArQf") {
            playVideo(from: videoURL)
        }
        
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
    
    func fetchImages(from urls: [String]) async throws -> [UIImage] {
        
        var images = Array<UIImage?>(repeating: nil, count: urls.count)
        
        try await withThrowingTaskGroup(of: (Int, UIImage).self, returning: Void.self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    
                    let image = try await self.fetchImage(from: url)
                    return (index, image)
                    
                }
            }
            
            for try await (index, image) in group {
                
                images[index] = image
                
            }
            
        }

        return images.compactMap { $0 }
        
    }
        
    func fetchImage(from url: String) async throws -> UIImage {
        
        // 메모리 캐시 확인
        if let cachedImage = KingfisherManager.shared.cache.retrieveImageInMemoryCache(forKey: url) {
            print("cachedImage: \(cachedImage)")
            return cachedImage
        }
        // 디스크 캐시 확인
        if let cachedImage = try await KingfisherManager.shared.cache.retrieveImageInDiskCache(forKey: url) {
            print("cachedImage: \(cachedImage)")
            return cachedImage
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            AF.request(url).responseData { response in
                
                switch response.result {
                case .success(let data):
                    // 작업 성공
                    guard let image = UIImage(data: data) else { return }
                    image.prepareThumbnail(of: CGSize(width: 240, height: 156)) { cgImage in
                        guard let cgImage = cgImage else { return }
                        KingfisherManager.shared.cache.store(cgImage, forKey: url)
                    }
                    continuation.resume(returning: image)
                    
                case .failure(let error):
                    // 에러 발생
                    continuation.resume(throwing: error)
                }
                
            }
        }
        
    }
    
    @IBAction func cameraBtnTapped(_ sender: UIButton) {
        openCamera()
    }
    
    private func openCamera() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self
            imagePicker.allowsEditing = true
            imagePicker.sourceType = .camera
        
            present(imagePicker, animated: true, completion: nil)
            
        }
    }
    
    func uploadVideoToStorage(videoURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        
        guard let videoData = try? Data(contentsOf: videoURL) else {
            print("비디오 데이터 생성 실패")
            return
        }
        
//        let fileName = videoURL.lastPathComponent
        let videoRef = storage.reference().child("Videos/\(UUID().uuidString).mp4")

        videoRef.putData(videoData) { (metaData, error) in
        
            guard let metaData = metaData, error == nil else {
                print("Storage에 업로드 실패!")
                return
            }
            
            videoRef.downloadURL { downloadURL, error in
                
                if let error = error {
                    completion(.failure(error))
                }
                
                if let downloadURL = downloadURL {
                    completion(.success(downloadURL.absoluteString))
                }
                
            }
            
        }
        
    }
    
}

extension PracViewController: PHPickerViewControllerDelegate {
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        
        for result in results {
            let itemProvider = result.itemProvider
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] fileURL, error in
                    guard let fileURL = fileURL, error == nil else { return }
                    self?.uploadVideoToStorage(videoURL: fileURL) { result in
                        
                        switch result {
                            
                        case .success(let downloadURL):
                            guard let url = URL(string: downloadURL) else { return }
                            self?.testImageView0.image = self?.generateThumbnail(from: url)
//                            self?.playVideo(from: url)
                            
                        case .failure(let error):
                            print("File URL 다운로드 실패: \(error.localizedDescription)")
                            
                        }
                        
                    }
                }
            }
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
