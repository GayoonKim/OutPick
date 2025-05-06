//
//  ChatCollectionViewController.swift
//  OutPick
//
//  Created by 김가윤 on 8/5/24.
//

import UIKit
import Kingfisher

class RoomListsCollectionViewController: UICollectionViewController {
    
    enum Section: Hashable {
        case main
    }
    
    typealias Item = ChatRoom
    typealias DataSourceType = UICollectionViewDiffableDataSource<Section, Item>
    
    var chatRooms: [ChatRoom] = []
    var dataSource: DataSourceType!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        dataSource = configureDataSource()
        collectionView.dataSource = dataSource
        collectionView.collectionViewLayout = configureLayout()
        collectionView.backgroundColor = UIColor(white: 0.3, alpha: 0.1)
        
        NotificationCenter.default.addObserver(self, selector: #selector(chatRoomsUpdated), name: .chatRoomsUpdated, object: nil)
        
        self.updateCollectionView()
    }
    
    @objc private func chatRoomsUpdated(notification: Notification) {
        // UI 업데이트
        DispatchQueue.main.async {
            self.updateCollectionView()
        }
    }
    
    private func updateCollectionView() {
        let chatRoomsList = FirebaseManager.shared.currentChatRooms.sorted(by: <)
        let itemBySection = [Section.main: chatRoomsList]
        
        dataSource.applySnapshotUsing(sectionIDs: [Section.main], itemsBySection: itemBySection)
    }
    
    private func configureDataSource() -> DataSourceType {
        let dataSource = DataSourceType(collectionView: collectionView) { (collectionView, indexPath, item) in
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ChatRoom", for: indexPath) as! RoomListCollectionViewCell
            cell.backgroundColor = .white
            
            print(indexPath, item)
            
            cell.roomImageView.layer.cornerRadius = 15
            cell.roomImageView.clipsToBounds = true
            
            // 기본 이미지 설정
            cell.roomImageView.image = UIImage(named: "Default_Profile")
            
            // 사용자 지정 이미지가 있는 경우에만 이미지 로딩 진행
            if let imageName = item.roomImageName, !imageName.isEmpty {
                Task {
                    do {
                        if let cachedImage = KingfisherManager.shared.cache.retrieveImageInMemoryCache(forKey: imageName) {
                            DispatchQueue.main.async {
                                cell.roomImageView.image = cachedImage
                            }
                        } else {
                            let image = try await FirebaseStorageManager.shared.fetchImageFromStorage(image: imageName, location: .RoomImage, createdDate: item.createdAt)
                            try await KingfisherManager.shared.cache.store(image, forKey: imageName)
                            DispatchQueue.main.async {
                                cell.roomImageView.image = image
                            }
                        }
                    } catch {
                        print("이미지 로딩 실패: \(error.localizedDescription)")
                    }
                }
            }
            
            cell.roomNameLabel.text = item.roomName
            cell.roomDescriptionLabel.text = item.roomDescription
            
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
        section.interGroupSpacing = 5
        section.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 0, bottom: 0, trailing: 0)
        
        return UICollectionViewCompositionalLayout(section: section)
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let selectedItem = dataSource.itemIdentifier(for: indexPath) else { return }
        
        performSegue(withIdentifier: "ToChatRoom", sender: selectedItem)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "ToChatRoom",
           let chatRoomVC = segue.destination as? ChatViewController,
           let tempRoomInfo = sender as? ChatRoom {
            chatRoomVC.room = tempRoomInfo
            chatRoomVC.isRoomSaving = false
        }
    }
}
