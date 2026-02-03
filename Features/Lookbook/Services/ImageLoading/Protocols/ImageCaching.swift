//
//  ImageCaching.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import UIKit

protocol ImageCaching: AnyObject {
    func image(forKey key: String) -> UIImage?
    func setImage(_ image: UIImage, forKey key: String)
    func removeImage(forKey key: String)
    func removeAll()
}
