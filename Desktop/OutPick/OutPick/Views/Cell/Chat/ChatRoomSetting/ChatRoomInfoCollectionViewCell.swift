//
//  roomInfoCollectionViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 5/13/25.
//

import UIKit

class ChatRoomInfoCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatRoomInfoCell"
    
    private let roomImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "Default_Profile")
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 20
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        return imageView
    }()
    
    private let roomNameLabel: UILabel = {
        let label = UILabel()
        label.font = .boldSystemFont(ofSize: 16)
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    private let roomParticipantCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .gray
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    private let editButtonView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.clipsToBounds = true
        view.layer.cornerRadius = 15
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private let editButton: UIButton = {
        let btn = UIButton()
        btn.setTitle("오픈채팅 관리", for: .normal)
        btn.setTitleColor(.black, for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        
        return btn
    }()
    
    var editButtonTapped: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        addSubview(roomImageView)
        addSubview(roomNameLabel)
        addSubview(roomParticipantCountLabel)
        addSubview(editButtonView)
        editButtonView.addSubview(editButton)
        editButton.addTarget(self, action: #selector(handleEditButtonTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            roomImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            roomImageView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            roomImageView.heightAnchor.constraint(equalToConstant: 70),
            roomImageView.widthAnchor.constraint(equalToConstant: 70),
            
            roomNameLabel.centerXAnchor.constraint(equalTo: roomImageView.centerXAnchor),
            roomNameLabel.topAnchor.constraint(equalTo: roomImageView.bottomAnchor, constant: 10),
            
            roomParticipantCountLabel.centerXAnchor.constraint(equalTo: roomNameLabel.centerXAnchor),
            roomParticipantCountLabel.topAnchor.constraint(equalTo: roomNameLabel.bottomAnchor, constant: 5),
            
            editButtonView.centerXAnchor.constraint(equalTo: roomParticipantCountLabel.centerXAnchor),
            editButtonView.topAnchor.constraint(equalTo: roomParticipantCountLabel.bottomAnchor, constant: 15),
            editButtonView.heightAnchor.constraint(equalTo: editButton.heightAnchor),
            editButtonView.widthAnchor.constraint(equalTo: editButton.widthAnchor, constant: 20),
            editButtonView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            
            editButton.centerXAnchor.constraint(equalTo: editButtonView.centerXAnchor),
        ])
    }
    
    @objc private func handleEditButtonTapped() {
        editButtonTapped?()
    }
    
    func configureCell(room: ChatRoom) {
        guard let roomImageName = room.roomImagePath else { return }
        if roomImageName != "" {
            Task {
                guard let imageName = room.roomImagePath else { return }
                let image = try await FirebaseStorageManager.shared.fetchImageFromStorage(image: imageName, location: .RoomImage)
                self.roomImageView.image = image
            }
        }
        
        roomNameLabel.text = room.roomName
        roomParticipantCountLabel.text = "\(room.participants.count)명 참여"
        backgroundColor = UIColor(white: 0.3, alpha: 0.03)
        
        if LoginManager.shared.currentUserProfile?.email != room.creatorID {
            editButtonView.isHidden = true
            NSLayoutConstraint.activate([
                editButtonView.bottomAnchor.constraint(equalTo: roomParticipantCountLabel.bottomAnchor),
            ])
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
