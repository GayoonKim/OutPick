//
//  ChatViewController.swift
//  OutPick
//
//  Created by 김가윤 on 10/14/24.
//

import UIKit

class ChatViewController: UIViewController {
    
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    var swipeRecognizer: UISwipeGestureRecognizer!
    
    var room: ChatRoom?
    var isRoomSaving = false

    override func viewDidLoad() {
        super.viewDidLoad()

        let backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(backButtonTapped))
        backButton.tintColor = .black
        self.navigationItem.leftBarButtonItem = backButton
        
        if isRoomSaving {
            activityIndicator.startAnimating()
            configureNotifications()
        }
        
        swipeRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(swipeAction(_:)))
        self.view.addGestureRecognizer(swipeRecognizer)
    }
    
    private func configureNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleRoomSaveCompleted), name: .roomSavedComplete, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRoomSaveFailed), name: .roomSaveFailed, object: nil)
    }
    
    @objc private func handleRoomSaveCompleted(notification: Notification) {
        activityIndicator.stopAnimating()
        
        guard let savedRoom = notification.userInfo?["room"] as? ChatRoom else { return }
        self.room = savedRoom
        
        guard let room = self.room else { return }
    }
    
    @objc private func handleRoomSaveFailed(notification: Notification) {
        activityIndicator.stopAnimating()
        
        guard let error = notification.userInfo?["error"] as? RoomCreationError else { return }
        showAlert(error: error)
        
    }
    
    private func showAlert(error: RoomCreationError) {
        var title: String
        var message: String
        
        switch error {
        case .saveFailed:
            title = "저장 실패"
            message = "채팅방 정보 저장에 실패했습니다. 다시 시도해주세요."
        case .imageUploadFailed:
            title = "이미지 업로드 실패"
            message = "방 이미지 업로드에 실패했습니다. 다시 시도해주세요."
        default:
            title = "오류"
            message = "알 수 없는 오류가 발생했습니다."
        }
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { action in
            self.navigationController?.popViewController(animated: true)
        })
    }
    
    @objc func backButtonTapped() {
        self.navigationController?.popToRootViewController(animated: true)
    }
    
    @objc func swipeAction(_ sender: UISwipeGestureRecognizer) {
        if sender.direction == .right {
            self.navigationController?.popToRootViewController(animated: true)
        }
    }

}
