//
//  ChatCollectionViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit

class ChatCollectionViewController: UICollectionViewController {
    
    var chatRooms: [ChatRoom] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        
        listenForRooms()
    }

    // Firestore에 저장된 모든 오픈 채팅 목록 불러오는 함수
    private func listenForRooms() {
        FirestoreManager.shared.db.collection("Rooms").addSnapshotListener{ querySnapshot, error in
            guard let documents = querySnapshot?.documents else {
                print("Documents 불러오기 실패: \(error!)")
                return
            }
            
            // 데이터 업데이트 시 chatRooms 배열 갱신
            self.chatRooms = documents.compactMap{ document -> ChatRoom? in
                try? document.data(as: ChatRoom.self)
            }
            print("*********Test: \(self.chatRooms)*********")
        }
    }
    
    
    
}
