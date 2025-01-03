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

class PracViewController: UIViewController, UINavigationControllerDelegate {

    @IBOutlet weak var testImageView: UIImageView!
    
    private let url =
    ["https://firebasestorage.googleapis.com:443/v0/b/outpick-664ae.appspot.com/o/roomImages%2F0A96E637-8DDC-4CE0-A807-A85F105182DF.jpg?alt=media&token=b5064cda-72c5-4a84-812c-f0bb2355aa10",
     "https://firebasestorage.googleapis.com:443/v0/b/outpick-664ae.appspot.com/o/profileImages%2FF123AE8D-428D-4FE4-8881-8612544B43C9.jpg?alt=media&token=3ded1f50-cde4-4a48-852d-d4ade85b6d17"]
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func fetchImage(from url: String) async throws -> Data {
        
        return try await withCheckedThrowingContinuation { continuation in
            AF.request(url).responseData { response in
                switch response.result {
                case .success(let data):
                    // 작업 성공
                    continuation.resume(returning: data)
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
            self.testImageView.image = editedImage
        } else if let originalImage = info[.originalImage] as? UIImage {
            self.testImageView.image = originalImage
        }
        
        dismiss(animated: true)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
    
}
