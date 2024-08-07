//
//  SecondProfileViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/6/24.
//

import UIKit
import PhotosUI

class SecondProfileViewController: UIViewController, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate & UINavigationControllerDelegate {

    @IBOutlet weak var nicknameTextField: UITextField!
    @IBOutlet weak var nicknameWordsCountLabel: UILabel!
    @IBOutlet weak var profileImageView: UIImageView!
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupNicknameTextField(nicknameTextField)
        profileImageViewSetup()
        addImageButtonSetup()
    }
    
    fileprivate func setupNicknameTextField(_ textField: UITextField) {
        textField.delegate = self
        textField.clipsToBounds = true
        textField.layer.cornerRadius = 10
        textField.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
        
        self.nicknameTextField.addTarget(self, action: #selector(textFieldDidChanacge), for: .editingChanged)
    }
    
    @objc fileprivate func textFieldDidChanacge(_ sender: UITextField) {
        guard let text = sender.text else { return }
        
        nicknameWordsCountLabel.text = "\(text.count) / 20"
    }
    
    fileprivate func profileImageViewSetup() {
        profileImageView.contentMode = .scaleAspectFill
        profileImageView.clipsToBounds = true
        profileImageView.layer.cornerRadius = 10
        profileImageView.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
    }
    
    fileprivate func addImageButtonSetup() {
        let addImageButton: UIButton = {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
            button.addTarget(self, action: #selector(addImageButtonTapped), for: .touchUpInside)
            
            return button
        }()
        
        view.addSubview(addImageButton)
        
        addImageButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            addImageButton.centerXAnchor.constraint(equalTo: profileImageView.trailingAnchor),
            addImageButton.centerYAnchor.constraint(equalTo: profileImageView.lastBaselineAnchor),
            addImageButton.widthAnchor.constraint(equalToConstant: 30),
            addImageButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    
    @objc fileprivate func addImageButtonTapped() {
        let alertController = UIAlertController(title: "사진 추가 ", message: "사진을 선택하거나 촬영하세요", preferredStyle: .actionSheet)
        
        alertController.addAction(UIAlertAction(title: "앨범", style: .default, handler: { _ in
            self.openPhotoLibrary()
        }))
        
        alertController.addAction(UIAlertAction(title: "카메라", style: .default, handler: { _ in
            self.openCamera()
        }))
        
        alertController.addAction(UIAlertAction(title: "취소", style: .cancel, handler: nil))
        
        present(alertController, animated: true, completion: nil)
    }
    
    fileprivate func openPhotoLibrary() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images // 이미지만 선택 가능하도록 설정
        config.selectionLimit = 1 // 선택 가능한 최대 이미지 수
        config.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        
        present(picker, animated: true, completion: nil)
    }
    
    fileprivate func openCamera() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self
            imagePicker.sourceType = .camera
        
            present(imagePicker, animated: true, completion: nil)
        }
    }
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        
        guard let itemProvider = results.first?.itemProvider else { return }
        
        if itemProvider.canLoadObject(ofClass: UIImage.self) {
            itemProvider.loadObject(ofClass: UIImage.self) { (image, error) in
                DispatchQueue.main.async {
                    self.profileImageView.image = image as? UIImage
                }
            }
        }
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let selectedImage = info[.originalImage] as? UIImage {
            profileImageView.image = selectedImage
        }
        picker.dismiss(animated: true, completion: nil)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
}

extension SecondProfileViewController: UITextFieldDelegate {
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let currentText = nicknameTextField.text ?? ""
        
        guard let stringRange = Range(range, in: currentText) else { return false }
        let updatedText = currentText.replacingCharacters(in: stringRange, with: string)
        
        return updatedText.count <= 20
    }
    
}
