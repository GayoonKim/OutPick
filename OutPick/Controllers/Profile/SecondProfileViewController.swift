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
import FirebaseAuth
import KakaoSDKUser

class SecondProfileViewController: UIViewController {
    
    @IBOutlet weak var nicknameTextField: UITextField!
    @IBOutlet weak var nicknameWordsCountLabel: UILabel!
    @IBOutlet weak var profileImageView: UIImageView!
    @IBOutlet weak var completeButton: UIButton!
    
    private var isDefaultProfileImage = true
    
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
        
        NavigationBarManager.configureBackButton(for: self)
        
        if let nickName = UserDefaults.standard.string(forKey: "savedNickName") {
            nicknameTextField.text = nickName
            nicknameWordsCountLabel.text = "\(nickName.count) / 20"
            UserDefaults.standard.removeObject(forKey: "savedNickName")
        }
        
        if let imageData = UserDefaults.standard.data(forKey: "savedProfileImage"),
           let image = UIImage(data: imageData) {
            profileImageView.image = image
            UserDefaults.standard.removeObject(forKey: "savedProfileImage")
        }
        
        enableCompleteButton()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if let nickName = nicknameTextField.text {
            UserDefaults.standard.set(nickName, forKey: "savedNickName")
        }
        
        if let image = profileImageView.image,
           let imageData = image.jpegData(compressionQuality: 0.5) {
            UserDefaults.standard.set(imageData, forKey: "savedProfileImage")
        } else {
            print("저장된 방 대표 사진 불러오기 실패")
            return
        }
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
    
    func removeImageButtonSetup() {
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

        if let current_image_data = profileImageView.image?.pngData(),
           let new_image_data = UIImage(named: "Default_Profile")?.pngData(),
           current_image_data == new_image_data {
            removeImageButton.isHidden = true
        } else {
            removeImageButton.isHidden = false
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
        profileImageView.image = UIImage(named: "Default_Profile")
        isDefaultProfileImage = true
        sender.isHidden = true
    }
    
    func enableCompleteButton() {
        if self.nicknameTextField.text == "" {
            self.completeButton.isEnabled = false
        } else {
            self.completeButton.isEnabled = true
        }
    }
    
    @IBAction func completeButtonTapped(_ sender: UIButton) {
        if let nickname = nicknameTextField.text {
            UserProfile.shared.nickname = nickname
        }
        
        if Auth.auth().currentUser?.providerData.first?.providerID == "google.com" {
            LoginManager.shared.getGoogleEmail { success in
                if success {
                    UserProfile.shared.email = LoginManager.shared.getUserEmail
                    self.saveUserProfile(email: LoginManager.shared.getUserEmail)
                }
            }
        } else {
            LoginManager.shared.getKakaoEmail { success in
                if success {
                    UserProfile.shared.email = LoginManager.shared.getUserEmail
                    self.saveUserProfile(email: LoginManager.shared.getUserEmail)
                }
            }
        }
        
        UserDefaults.standard.removeObject(forKey: "savedProfileImage")
        UserDefaults.standard.removeObject(forKey: "savedNickName")
    }
    
    private func saveUserProfile(email: String) {
        guard let nickname = UserProfile.shared.nickname else { return }
        
        Task {
            do {
                if try await FirebaseManager.shared.checkDuplicate(strToCompare: nickname, fieldToCompare: "nickname", collectionName: "Users") {
                    AlertManager.showAlertNoHandler(title: "닉네임 중복", message: "다른 닉네임을 선택해 주세요.", viewController: self)
                    return
                }
                
                if let image = profileImageView.image {
                    if isDefaultProfileImage {
                        print("기본 프로필 이미지 감지됨 - 서버 업로드 건너뜀")
                        UserProfile.shared.profileImageName = nil
                    } else {
                        print("사용자 지정 프로필 이미지 감지됨 - 서버 업로드 진행")
                        let imageName = try await FirebaseStorageManager.shared.uploadImageToStorage(image: image, location: ImageLocation.ProfileImage)
                        UserProfile.shared.profileImageName = imageName
                    }
                } else {
                    print("프로필 이미지가 nil입니다")
                    UserProfile.shared.profileImageName = nil
                }
                
                if let data = try? JSONEncoder().encode(UserProfile.shared) {
                    KeychainManager.shared.save(data, service: "GayoonKim.OutPick", account: "UserProfile")
                }
                
                try await FirebaseManager.shared.saveUserProfileToFirestore(email: LoginManager.shared.getUserEmail)
                
                DispatchQueue.main.async {
                    let homeVC = self.storyboard?.instantiateViewController(identifier: "HomeTBC") as? UITabBarController
                    self.view.window?.rootViewController = homeVC
                    self.view.window?.makeKeyAndVisible()
                }
                
            } catch FirebaseError.FailedToSaveProfile {
                print("프로필 저장 실패")
                AlertManager.showAlertNoHandler(title: "프로필 저장 실패", message: "프로필 저장에 실패했습니다. 다시 시도해 주세요.", viewController: self)
            } catch {
                print("알 수 없는 에러: \(error)")
                AlertManager.showAlertNoHandler(title: "프로필 저장 실패", message: "프로필 저장에 실패했습니다. 다시 시도해 주세요.", viewController: self)
                return
            }
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.view.endEditing(true)
    }
    
    private func openPhotoLibrary() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
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
    
}
