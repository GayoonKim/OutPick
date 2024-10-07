//
//  RoomCreateViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit
import PhotosUI

class RoomCreateViewController: UIViewController, PHPickerViewControllerDelegate {
    
    @IBOutlet weak var roomNameTextView: UITextView!
    @IBOutlet weak var roomNameCountLabel: UILabel!
    @IBOutlet weak var roomDescriptionTextView: UITextView!
    @IBOutlet weak var roomDescriptionCountLabel: UILabel!
    @IBOutlet weak var createButton: UIButton!
    
    @IBOutlet weak var roomImageView: UIImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupTextView(roomNameTextView)
        setupTextView(roomDescriptionTextView)
        addImageButtonSetup()
        setCreateButton(createButton)

        let backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(backButtonTapped))
        backButton.tintColor = .black
        self.navigationItem.leftBarButtonItem = backButton
    }
    
    @objc func backButtonTapped() {
        let alert = UIAlertController(title: "채팅방 개설을 취소하시겠어요?", message: nil, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "계속 작성", style: .default, handler: nil))
        alert.addAction(UIAlertAction(title: "취소", style: .destructive, handler:  { _ in
            self.navigationController?.popViewController(animated: true)
        }))
        
        self.present(alert, animated: true, completion: nil)
        }
    
    
    private func setupTextView(_ textView: UITextView) {
        textView.delegate = self
        textView.clipsToBounds = true
        textView.layer.cornerRadius = 10
        textView.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
        textView.font = UIFont.preferredFont(forTextStyle: .headline)
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
            addImageButton.centerXAnchor.constraint(equalTo: roomImageView.trailingAnchor),
            addImageButton.centerYAnchor.constraint(equalTo: roomImageView.bottomAnchor),
            addImageButton.widthAnchor.constraint(equalToConstant: 30),
            addImageButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    
    @objc private func addImageButtonTapped() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images // 이미지만 선택 가능하도록 설정
        config.selectionLimit = 1 // 선택 가능한 최대 이미지 수
        config.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        
        present(picker, animated: true, completion: nil)
    }
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        
        guard let itemProvider = results.first?.itemProvider else { return }
        
        if itemProvider.canLoadObject(ofClass: UIImage.self) {
            itemProvider.loadObject(ofClass: UIImage.self) { (image, error) in
                DispatchQueue.main.async {
                    self.roomImageView.image = image as? UIImage
                    self.removeImageButtonSetup()
                }
            }
        }
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
            removeImageButton.centerXAnchor.constraint(equalTo: roomImageView.leadingAnchor),
            removeImageButton.centerYAnchor.constraint(equalTo: roomImageView.bottomAnchor),
            removeImageButton.widthAnchor.constraint(equalToConstant: 30),
            removeImageButton.heightAnchor.constraint(equalToConstant: 30)
        ])

        if let image = roomImageView.image {
            if image.isEqual(UIImage(systemName: "photo")) {
                removeImageButton.isHidden = true
            } else {
                removeImageButton.isHidden = false
            }
        }
    }
    
    @objc private func removeImageButtonTapped(_ sender: UIButton) {
        roomImageView.image = UIImage(systemName: "photo")
        
        sender.isHidden = true
    }
    
    private func setCreateButton(_ button: UIButton) {
        button.clipsToBounds = true
        button.layer.cornerRadius = 10
        button.backgroundColor = UIColor(white: 0.1, alpha: 0.03)
    }
    
    @IBAction func createBtnTapped(_ sender: UIButton) {
        let roomInfo = ChatRoom(roomName: roomNameTextView.text, roomDescription: roomDescriptionTextView.text, participants: [UserProfile.sharedUserProfile], creatorID: UserProfile.sharedUserProfile.nickname ?? "", createdAt: Date())
        
        saveRoomInfoToFirestore(room: roomInfo) { result in
            switch result {
            case .success:
                // 성공
                print("방 저장 성공")
            case .failure(let error):
                // 실패
                print("방 저장 실패: \(error.localizedDescription)")
                let alert = UIAlertController(title: "방 이름 중복", message: "다른 이름을 선택해 주세요.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                self.present(alert, animated: true, completion: nil)
                return
            }
        }
    }
    
}

extension RoomCreateViewController: UITextViewDelegate {
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let currentText = textView.text ?? ""
        
        guard let stringRange = Range(range, in: currentText) else { return false }
        
        let updatedText = currentText.replacingCharacters(in: stringRange, with: text)
        
        return updatedText.count <= 20
    }
    
    func textViewDidChange(_ textView: UITextView) {
        guard let text = textView.text else { return }
        
        switch textView {
        case roomNameTextView:
            roomNameCountLabel.text = "\(text.count) / 20"
        case roomDescriptionTextView:
            roomDescriptionCountLabel.text = "\(text.count) / 20"
        default:
            break
        }
    }
    
}
