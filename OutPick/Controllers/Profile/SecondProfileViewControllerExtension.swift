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
            let image = images.first
            
            DispatchQueue.main.async {
                self.profileImageView.image = image
            }
            
        }
        
    }
    
}

extension SecondProfileViewController: UIImagePickerControllerDelegate & UINavigationControllerDelegate {
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let selectedImage = info[.originalImage] as? UIImage {
            profileImageView.image = selectedImage
            self.removeImageButtonSetup()
        }
        picker.dismiss(animated: true, completion: nil)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
    
}
