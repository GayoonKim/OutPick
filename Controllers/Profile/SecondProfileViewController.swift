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
    
    internal var isDefaultProfileImage = true
    public var getIsDefaultProfileImage: Bool {
        return isDefaultProfileImage
    }
    
    let removeImageButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
        button.tintColor = .red
        
        return button
    }()
    
    let addImageButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        
        return button
    }()
    
    var userProfile = UserProfile(email: nil, nickname: nil, gender: nil, birthdate: nil, thumbPath: nil, originalPath: nil, joinedRooms: [])
    
    var profileImage: MediaManager.ImagePair?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.navigationController?.delegate = self
        
        setupNicknameTextField(nicknameTextField)
        profileImageViewSetup()
        addImageButtonSetup()
        removeImageButtonSetup()
        
        completeButton.clipsToBounds = true
        completeButton.layer.cornerRadius = 10
        completeButton.isEnabled = false
        completeButton.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
        
        NavigationBarManager.configureBackButton(for: self)
        
        enableCompleteButton()
    }
    
    // UINavigationControllerDelegate
    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController,
                              animated: Bool) {
        if viewController === self {
            // 이 뷰 컨트롤러가 나타날 때만 back button 커스텀
            NavigationBarManager.configureBackButton(for: self)
        } else {
            // 뒤로 이동할 때 수행할 코드
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
            
            UserDefaults.standard.set(isDefaultProfileImage, forKey: "isDefaultProfileImage")
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if let nickName = UserDefaults.standard.string(forKey: "savedNickName") {
            nicknameTextField.text = nickName
            nicknameWordsCountLabel.text = "\(nickName.count) / 20"
            completeButton.isEnabled = true
            UserDefaults.standard.removeObject(forKey: "savedNickName")
        }
        
        if let imageData = UserDefaults.standard.data(forKey: "savedProfileImage"),
           let image = UIImage(data: imageData) {
            profileImageView.image = image
            UserDefaults.standard.removeObject(forKey: "savedProfileImage")
        }
        
        if UserDefaults.standard.object(forKey: "isDefaultProfileImage") == nil {
            isDefaultProfileImage = true
        } else {
            isDefaultProfileImage = UserDefaults.standard.bool(forKey: "isDefaultProfileImage")
            UserDefaults.standard.removeObject(forKey: "isDefaultProfileImage")
        }
        removeImageButton.isHidden = isDefaultProfileImage
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    
    private func profileImageViewSetup() {
        profileImageView.clipsToBounds = true
        profileImageView.layer.cornerRadius = 10
        profileImageView.backgroundColor = UIColor(white: 0.3, alpha: 0.03)
    }
    
    private func addImageButtonSetup() {
        view.addSubview(addImageButton)
        addImageButton.addTarget(self, action: #selector(addImageButtonTapped), for: .touchUpInside)
        
        addImageButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            addImageButton.centerXAnchor.constraint(equalTo: profileImageView.trailingAnchor),
            addImageButton.centerYAnchor.constraint(equalTo: profileImageView.bottomAnchor),
            addImageButton.widthAnchor.constraint(equalToConstant: 30),
            addImageButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    
    func removeImageButtonSetup() {
        view.addSubview(removeImageButton)
        removeImageButton.addTarget(self, action: #selector(removeImageButtonTapped(_:)), for: .touchUpInside)
        removeImageButton.isHidden = true
        
        removeImageButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            removeImageButton.centerXAnchor.constraint(equalTo: profileImageView.leadingAnchor),
            removeImageButton.centerYAnchor.constraint(equalTo: profileImageView.bottomAnchor),
            removeImageButton.widthAnchor.constraint(equalToConstant: 30),
            removeImageButton.heightAnchor.constraint(equalToConstant: 30)
        ])

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
        self.userProfile.thumbPath = ""
        self.userProfile.originalPath = ""
        self.profileImage = nil
        self.isDefaultProfileImage = true
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
        UserDefaults.standard.removeObject(forKey: "savedProfileImage")
        UserDefaults.standard.removeObject(forKey: "savedNickName")
        
        if let nickname = nicknameTextField.text {
            userProfile.nickname = nickname
        }
        userProfile.joinedRooms = []
        
        if Auth.auth().currentUser?.providerData.first?.providerID == "google.com" {
            LoginManager.shared.getGoogleEmail { success in
                if success {
                    self.userProfile.email = LoginManager.shared.getUserEmail
                    LoginManager.shared.setCurrentUserProfile(self.userProfile)
                    self.saveUserProfile(email: LoginManager.shared.getUserEmail)
                }
            }
        } else {
            LoginManager.shared.getKakaoEmail { success in
                if success {
                    self.userProfile.email = LoginManager.shared.getUserEmail
                    LoginManager.shared.setCurrentUserProfile(self.userProfile)
                    self.saveUserProfile(email: LoginManager.shared.getUserEmail)
                }
            }
        }
    }
    
    private func saveUserProfile(email: String) {
        guard let nickname = self.userProfile.nickname else { return }
        LoadingIndicator.shared.start(on: self)

        Task {
            do {
                // 1) 닉네임 중복 체크 (전환 전 확정)
                if try await FirebaseManager.shared.checkDuplicate(strToCompare: nickname, fieldToCompare: "nickName", collectionName: "Users") {
                    await MainActor.run {
                        AlertManager.showAlertNoHandler(title: "닉네임 중복", message: "다른 닉네임을 선택해 주세요.", viewController: self)
                    }
                    return
                }
                
                // 2) 로컬 상태 업데이트 (아바타 경로는 기본적으로 nil)
                self.userProfile.email = email
                self.userProfile.joinedRooms = []
                if isDefaultProfileImage || self.profileImage == nil {
                    self.userProfile.thumbPath = nil
                    self.userProfile.originalPath = nil
                }
                
                if let data = try? JSONEncoder().encode(self.userProfile) {
                    KeychainManager.shared.save(data, service: "GayoonKim.OutPick", account: "UserProfile")
                }
                
                LoginManager.shared.setCurrentUserProfile(self.userProfile)
                
                // 3) 낙관적 전환: 홈으로 이동 (UI는 메인 스레드)
                await MainActor.run {
                    let rootVC = CustomTabBarViewController()
                    if let window = self.view.window {
                        window.rootViewController = rootVC
                        window.makeKeyAndVisible()
                    } else if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                              let window = windowScene.windows.first {
                        window.rootViewController = rootVC
                        window.makeKeyAndVisible()
                    }
                }
                
                
                // 4) 백그라운드 저장들(동시에 진행)
                async let saveProfileTask: () = FirebaseManager.shared.saveUserProfileToFirestore(email: email)
                
                if !isDefaultProfileImage, let pair = self.profileImage {
                    do {
                        let (thumbPath, oriPath) = try await FirebaseStorageManager.shared.uploadAndSaveProfile(sha: pair.fileBaseName, uid: LoginManager.shared.getUserEmail, type: "profiles", thumbData: pair.thumbData, originalFileURL: pair.originalFileURL)
                        // 로컬 프로필/세션 갱신
                        self.userProfile.thumbPath = thumbPath
                        self.userProfile.originalPath = oriPath
                    } catch {
                        // 업로드 실패는 치명적이지 않으므로 로그만 남기고, 추후 재시도 큐에서 처리 가능
                        print("아바타 업로드 실패: \(error)")
                    }
                }
                
                
                // Users 문서 저장 완료 대기 (에러는 상단 catch로 전파)
                _ = try await saveProfileTask
            } catch FirebaseError.FailedToSaveProfile {
                await MainActor.run {
                    LoadingIndicator.shared.stop()
                    AlertManager.showAlertNoHandler(title: "프로필 저장 실패", message: "프로필 저장에 실패했습니다. 다시 시도해 주세요.", viewController: self)
                }
            } catch {
                print("알 수 없는 에러: \(error)")
                await MainActor.run {
                    LoadingIndicator.shared.stop()
                    AlertManager.showAlertNoHandler(title: "프로필 저장 실패", message: "프로필 저장에 실패했습니다. 다시 시도해 주세요.", viewController: self)
                }
            }
            
            return
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
