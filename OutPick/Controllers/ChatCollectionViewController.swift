//
//  ChatCollectionViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit

class ChatCollectionViewController: UICollectionViewController {
    
    typealias DataSourceType = UICollectionViewDiffableDataSource<ViewModel.Section, ViewModel.Item>

    class ViewModel {
        enum Section: Hashable {
            case main
        }
        
        typealias Item = ChatRoom
    }
    
    struct Model {
        var chatRooms: [ChatRoom] = []
    }
    
    var dataSource: DataSourceType!
    var model = Model()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        dataSource = configureDataSource()
        collectionView.dataSource = dataSource
        collectionView.collectionViewLayout = configureLayout()
        
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
            self.model.chatRooms = documents.compactMap{ document -> ChatRoom? in
                guard var chatRoom = try? document.data(as: ChatRoom.self) else { return nil}
                chatRoom.id = document.documentID
                return chatRoom
            }
            
            self.updateCollectionView()
        }
        
    }
    
    private func updateCollectionView() {
        let chatRoomsList = self.model.chatRooms.sorted(by: <)
        
        let itemBySection = [ViewModel.Section.main: chatRoomsList]
        
        dataSource.applySnapshotUsing(sectionIDs: [.main], itemsBySection: itemBySection)
    }
    
    private func configureDataSource() -> DataSourceType {
        let dataSource = DataSourceType(collectionView: collectionView) { (collectionView, indexPath, item) in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ChatRoom", for: indexPath) as! RoomListCollectionViewCell
            
            cell.roomImageView.layer.cornerRadius = cell.roomImageView.frame.width / 2
            cell.roomImageView.clipsToBounds =  true
            
            cell.roomNameLabel.text = item.roomName
            
            return cell
        }
        
        return dataSource
    }
    
    private func configureLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(0.45))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, repeatingSubitem: item, count: 1)
        
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 20
        section.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
        
        return UICollectionViewCompositionalLayout(section: section)
    }
    
}
