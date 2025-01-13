//
//  SecondProfileViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/6/24.
//

import UIKit
import PhotosUI
import FirebaseFirestore
import FirebaseStorage
import KakaoSDKUser

class SecondProfileViewController: UIViewController, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate & UINavigationControllerDelegate {

    @IBOutlet weak var nicknameTextField: UITextField!
    @IBOutlet weak var nicknameWordsCountLabel: UILabel!
    @IBOutlet weak var profileImageView: UIImageView!
    @IBOutlet weak var completeButton: UIButton!
    
    var profile: UserProfile?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupNicknameTextField(nicknameTextField)
        profileImageViewSetup()
        addImageButtonSetup()
        removeImageButtonSetup()
        
        completeButton.clipsToBounds = true
        completeButton.layer.cornerRadius = 10
        completeButton.isEnabled = false
        completeButton.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
    }
    
    private func setupNicknameTextField(_ textField: UITextField) {
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
    
    private func profileImageViewSetup() {
        profileImageView.clipsToBounds = true
        profileImageView.layer.cornerRadius = 10
        profileImageView.backgroundColor = UIColor(white: 0.3, alpha: 0.03)
    }
    
    private func addImageButtonSetup() {
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
            addImageButton.centerYAnchor.constraint(equalTo: profileImageView.bottomAnchor),
            addImageButton.widthAnchor.constraint(equalToConstant: 30),
            addImageButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    
    private func removeImageButtonSetup() {
        let removeImageButton: UIButton = {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
            button.addTarget(self, action: #selector(removeImageButtonTapped(_:)), for: .touchUpInside)
            button.tintColor = .red
            
            return button
        }()
        
        view.addSubview(removeImageButton)
        
        removeImageButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            removeImageButton.centerXAnchor.constraint(equalTo: profileImageView.leadingAnchor),
            removeImageButton.centerYAnchor.constraint(equalTo: profileImageView.bottomAnchor),
            removeImageButton.widthAnchor.constraint(equalToConstant: 30),
            removeImageButton.heightAnchor.constraint(equalToConstant: 30)
        ])

        if let image = profileImageView.image {
            if image.isEqual(UIImage(systemName: "photo")) {
                removeImageButton.isHidden = true
            } else {
                removeImageButton.isHidden = false
            }
        }
    }
    
    @objc private func addImageButtonTapped() {
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
    
    @objc private func removeImageButtonTapped(_ sender: UIButton) {
        profileImageView.image = UIImage(systemName: "photo")
        
        sender.isHidden = true
    }
    
    private func openPhotoLibrary() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images // 이미지만 선택 가능하도록 설정
        config.selectionLimit = 1 // 선택 가능한 최대 이미지 수
        config.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        
        present(picker, animated: true, completion: nil)
    }
    
    private func openCamera() {
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
                    self.removeImageButtonSetup()
                }
            }
        }
    }
    
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
    
    private func enableCompleteButton() {
        guard let _ = nicknameTextField.text else { return }
        completeButton.isEnabled = true
    }
    
    @IBAction func completeButtonTapped(_ sender: UIButton) {
        
        if let nickname = nicknameTextField.text {
            UserProfile.sharedUserProfile.nickname = nickname
        }
            
        self.saveUserProfile(userProfile: UserProfile.sharedUserProfile, email: LoginManager.shared.getUserEmail)
            
        let homeVC = self.storyboard?.instantiateViewController(identifier: "HomeTBC") as? UITabBarController
        self.view.window?.rootViewController = homeVC
        self.view.window?.makeKeyAndVisible()
    }
    
    private func saveUserProfile(userProfile: UserProfile, email: String) {
        
        guard let nickname = userProfile.nickname else { return }
        FirebaseManager.shared.checkNicknameDuplicate(nickname: nickname) { isDuplicate, error in
            if let error = error {
                print("Failed to check nickname: \(error.localizedDescription)")
                return
            }
            
            if isDuplicate {
                let alert = UIAlertController(title: "닉네임 중복", message: "다른 닉네임을 선택해 주세요.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                self.present(alert, animated: true, completion: nil)
                return
            }
            
            Task {
                if let image = self.profileImageView.image {
                    let imageName = try await FirebaseStorageManager.shared.uploadImageToStorage(image: image, type: ImageType.ProfileImage)
                    userProfile.profileImageName = imageName
                    
                    FirebaseManager.shared.saveUserProfileToFirestore(userProfile: userProfile, email: email) { error in
                        if let error = error {
                            
                            print("Failed to save user profile: \(error.localizedDescription)")
                            
                        } else {
                            
                            print("User profile saved successfully with profile image!")
                            
                        }
                    }
                } else {
                    userProfile.profileImageName = nil
                    FirebaseManager.shared.saveUserProfileToFirestore(userProfile: userProfile, email: email) { error in
                        if let error = error {
                            
                            print("Failed to save user profile: \(error.localizedDescription)")
                            
                        } else {
                            
                            print("User profile saved successfully without profile image!")
                            
                        }
                    }
                }
            }
        }
        
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.view.endEditing(true)
    }
    
}

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
    
}
