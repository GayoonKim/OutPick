//
//  SecondProfileViewControllerExtension.swift
//  OutPick
//
//  Created by 김가윤 on 1/16/25.
//

import Foundation
import UIKit
import PhotosUI

extension SecondProfileViewController: UITextFieldDelegate {
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let currentText = nicknameTextField.text ?? ""
        
        guard let stringRange = Range(range, in: currentText) else { return false }
        let updatedText = currentText.replacingCharacters(in: stringRange, with: string)
        
        return updatedText.count <= 20
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    func setupNicknameTextField(_ textField: UITextField) {
        textField.delegate = self
        textField.clipsToBounds = true
        textField.layer.cornerRadius = 10
        textField.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
        
        self.nicknameTextField.addTarget(self, action: #selector(textFieldDidChanacge), for: .editingChanged)
    }
    
    @objc fileprivate func textFieldDidChanacge(_ sender: UITextField) {
        guard let text = sender.text else { return }
        
        nicknameWordsCountLabel.text = "\(text.count) / 20"
        enableCompleteButton()
    }
    
}

extension SecondProfileViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        
        Task {
            let images = try await MediaManager.shared.dealWithImages(results)
            
            DispatchQueue.main.async {
                if let image = images.first {
                    self.profileImageView.image = image
                    self.isDefaultProfileImage = false
                    self.removeImageButton.isHidden = false
                } else {
                    self.profileImageView.image = UIImage(named: "Default_Profile.png")
                }
            }
        }
    }
}

extension SecondProfileViewController: UIImagePickerControllerDelegate & UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let selectedImage = info[.originalImage] as? UIImage,
           let cgImage = MediaManager.compressImageWithImageIO(selectedImage) {
            profileImageView.image = UIImage(cgImage: cgImage)
            self.enableCompleteButton()
        } else if let editedImage = info[.editedImage] as? UIImage,
                  let cgImage = MediaManager.compressImageWithImageIO(editedImage) {
            profileImageView.image = UIImage(cgImage: cgImage)
            self.enableCompleteButton()
        }
        
        picker.dismiss(animated: true, completion: nil)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
    
}
