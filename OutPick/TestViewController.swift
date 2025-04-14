//
//  TestViewController.swift
//  OutPick
//
//  Created by 김가윤 on 4/15/25.
//

import UIKit
import FirebaseStorage
import Firebase
import Kingfisher

class TestViewController: UIViewController {

    @IBOutlet weak var imageView: UIImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let image = UIImage(named: "Default_Profile") {
            Task { try await uploadAndFetchImage(image) }
        }
    }

    func uploadAndFetchImage(_ image: UIImage) async throws {
        let imageName = try await FirebaseStorageManager.shared.uploadImageToStorage(image: image, location: .RoomImage)
        let fetchedImage = try await FirebaseStorageManager.shared.fetchImageFromStorage(image: imageName, location: .RoomImage, createdDate: Date())
        
        DispatchQueue.main.async {
            self.imageView.image = fetchedImage
        }
    }
    
}
