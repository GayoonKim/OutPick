//
//  EditRoomImageTableViewCell.swift
//  OutPick
//
//  Created by 김가윤 on 6/25/25.
//

import UIKit

class EditRoomImageTableViewCell: UITableViewCell {
    static let identifier = "EditRoomImageCell"
    
    var onImgViewTapped: (() -> Void)?
    
    private let imgView: UIImageView = {
       let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 20
        imageView.image = UIImage(named: "Default_Profile")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        return imageView
    }()
    
    private let cameraIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .center
        imageView.tintColor = .black
        imageView.backgroundColor = .white
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 13
        imageView.image = UIImage(systemName: "camera.fill")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        return imageView
    }()

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
        selectionStyle = .none
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        contentView.addSubview(imgView)
        imgView.addSubview(cameraIconView)
        imgView.isUserInteractionEnabled = true
        
        NSLayoutConstraint.activate([
            imgView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            imgView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imgView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 110),
            imgView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -110),
            imgView.heightAnchor.constraint(equalToConstant: 200),
            
            cameraIconView.widthAnchor.constraint(equalToConstant: 30),
            cameraIconView.heightAnchor.constraint(equalToConstant: 30),
            cameraIconView.trailingAnchor.constraint(equalTo: imgView.trailingAnchor, constant: -10),
            cameraIconView.bottomAnchor.constraint(equalTo: imgView.bottomAnchor, constant: -10)
        ])
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleImgViewTap))
        imgView.addGestureRecognizer(tapGesture)
    }
    
    @objc private func handleImgViewTap() {
        onImgViewTapped?()
    }
    
    @MainActor
    func configure(_ room: ChatRoom, selectedImage: UIImage?) {
//        if let selectedImage = selectedImage {
//            imgView.image = selectedImage
//        } else if room.roomImagePath != "" {
//                Task {
//                    guard let imagePath = room.roomImagePath else { return }
//                    let image = try await FirebaseStorageManager.shared.fetchImageFromStorage(image: imagePath, location: .RoomImage)
//                    self.imgView.image = image
//                }
//        } else {
//            self.imgView.image = UIImage(named: "Default_Profile")
//        }
    }
}
