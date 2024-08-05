//
//  ChatCollectionViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit

private let reuseIdentifier = "Cell"

class ChatCollectionViewController: UICollectionViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        SocketIOManager.shared.establishConnection()
    }

    
    
}
