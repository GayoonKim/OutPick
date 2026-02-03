//
//  ParticipantsSectionCell.swift
//  OutPick
//
//  Created by 김가윤 on 5/17/25.
//

import UIKit

class ParticipantsSectionParticipantCell: UICollectionViewCell {
    static let reuseIdentifier = "ParticipantsSectionParticipantCell"
    
    private var userProfiles: [LocalUser] = []
    
    private lazy var participantLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    public lazy var verticalCollectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { sectionIndex, environment in
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(60))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            
            let groupSIze = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(60))
            let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSIze, subitems: [item])
//            group.interItemSpacing = .fixed(5)
            
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = .init(top: 0, leading: 0, bottom: 0, trailing: 0)
            
            return section
        }
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .white
        collectionView.allowsSelection = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ParticipantListCell.self, forCellWithReuseIdentifier: ParticipantListCell.reuseIdentifier)
        
        return collectionView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.layer.cornerRadius = 10
        contentView.layer.masksToBounds = true
        contentView.backgroundColor = .white
        
        contentView.addSubview(participantLabel)
        contentView.addSubview(verticalCollectionView)
    
        NSLayoutConstraint.activate([
            participantLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            participantLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            
            verticalCollectionView.topAnchor.constraint(equalTo: participantLabel.bottomAnchor, constant: 0),
            verticalCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            verticalCollectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 0),
            verticalCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configureCell(_ profiles: [LocalUser]) {
        print(#function, "호출 완료: ", profiles.map { $0.nickname })
        self.userProfiles = profiles
        participantLabel.text = "대화상대 \(profiles.count)"
        
        // 메인 스레드에서 UI 업데이트
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.verticalCollectionView.reloadData()
            self.verticalCollectionView.layoutIfNeeded()
            
            // 강제로 레이아웃 업데이트
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
    }
}

extension ParticipantsSectionParticipantCell: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        print("numberOfItemsInSection:", userProfiles.count)
        return self.userProfiles.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
//        if indexPath.item < self.userProfiles.count {
//
//        }
        print("cellForItemAt:", indexPath, userProfiles[indexPath.item].nickname)
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ParticipantListCell.reuseIdentifier, for: indexPath) as! ParticipantListCell
        cell.configureCell(userProfile: self.userProfiles[indexPath.item])
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.cellForItem(at: indexPath)?.backgroundView?.backgroundColor = .blue
    }
}
