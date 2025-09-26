//
//  TEstViewController.swift
//  OutPick
//
//  Created by 김가윤 on 9/26/25.
//

import UIKit
import Firebase
import Kingfisher

class TEstViewController: UIViewController {
    
    let imageView: UIImageView = {
        let imageView = UIImageView()
        
        imageView.backgroundColor = .systemBlue
        imageView.heightAnchor.constraint(equalToConstant: 100).isActive = true
        imageView.widthAnchor.constraint(equalToConstant: 100).isActive = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        return imageView
    }()


    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        
        Task { await setImageView() }
    }
    
    func setImageView() async {
        do {
            
            
            let image = try await FirebaseStorageManager.shared.fetchImageFromStorage(image: "Room_Images/Test Room/A254CCD1-4FF6-4F6C-ABA1-1F3E813CB427-1758865872.jpg", location: .RoomImage)
            imageView.image = image
        } catch {
            
        }
    }
}
