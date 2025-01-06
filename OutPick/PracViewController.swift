//
//  PracViewController.swift
//  OutPick
//
//  Created by 김가윤 on 1/3/25.
//

import UIKit
import Foundation
import Alamofire
import PhotosUI
import Kingfisher

class PracViewController: UIViewController, UINavigationControllerDelegate {

    @IBOutlet weak var testImageView0: UIImageView!
    @IBOutlet weak var testImageView1: UIImageView!
    
    
    private let url =
    ["https://firebasestorage.googleapis.com:443/v0/b/outpick-664ae.appspot.com/o/roomImages%2F0A96E637-8DDC-4CE0-A807-A85F105182DF.jpg?alt=media&token=b5064cda-72c5-4a84-812c-f0bb2355aa10",
     "https://firebasestorage.googleapis.com:443/v0/b/outpick-664ae.appspot.com/o/profileImages%2FF123AE8D-428D-4FE4-8881-8612544B43C9.jpg?alt=media&token=3ded1f50-cde4-4a48-852d-d4ade85b6d17"]
    
    private var i = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        Task {
            
            let results = try await fetchImages(from: self.url)
            
            DispatchQueue.main.async {
                self.testImageView0.image = results[0]
                self.testImageView1.image = results[1]
            }
            
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
                    KingfisherManager.shared.cache.store(image, forKey: url)
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
