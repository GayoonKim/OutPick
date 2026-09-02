//
//  ParticipantsSectionCell.swift
//  OutPick
//
//  Created by 김가윤 on 5/17/25.
//

import UIKit

class ParticipantsSectionParticipantCell: UICollectionViewCell {
    static let reuseIdentifier = "ParticipantsSectionParticipantCell"
    
    private var participants: [ChatRoomParticipant] = []
    private var avatarImageManager: AvatarImageManaging?
    private var currentUserID: String = ""
    private var collectionHeightConstraint: NSLayoutConstraint!
    var onSelectParticipant: ((ChatRoomParticipant) -> Void)?
    var canModerateParticipant: ((ChatRoomParticipant) -> Bool)?
    var onModerateParticipant: ((ChatRoomParticipant) -> Void)?
    
    private lazy var participantLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = OutPickTheme.ColorToken.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    public lazy var verticalCollectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { sectionIndex, environment in
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(60))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            
            let groupSIze = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(60))
            let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSIze, subitems: [item])
//            group.interItemSpacing = .fixed(5)
            
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = .init(top: 0, leading: 0, bottom: 0, trailing: 0)
            
            return section
        }
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        collectionView.allowsSelection = true
        collectionView.isScrollEnabled = false
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
        contentView.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        contentView.layer.borderColor = OutPickTheme.ColorToken.borderSubtle.cgColor
        contentView.layer.borderWidth = 1
        
        contentView.addSubview(participantLabel)
        contentView.addSubview(verticalCollectionView)
        collectionHeightConstraint = verticalCollectionView.heightAnchor.constraint(equalToConstant: 0)
    
        NSLayoutConstraint.activate([
            participantLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            participantLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            
            verticalCollectionView.topAnchor.constraint(equalTo: participantLabel.bottomAnchor, constant: 0),
            verticalCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            verticalCollectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 0),
            verticalCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            collectionHeightConstraint
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCollectionHeightIfNeeded()
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        contentView.bounds.size.width = layoutAttributes.size.width
        contentView.setNeedsLayout()
        contentView.layoutIfNeeded()
        verticalCollectionView.collectionViewLayout.invalidateLayout()
        verticalCollectionView.layoutIfNeeded()
        updateCollectionHeightIfNeeded()
        contentView.layoutIfNeeded()

        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        let targetSize = CGSize(
            width: layoutAttributes.size.width,
            height: UIView.layoutFittingCompressedSize.height
        )
        attributes.size.height = ceil(contentView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height)
        return attributes
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onSelectParticipant = nil
        canModerateParticipant = nil
        onModerateParticipant = nil
        participants = []
        currentUserID = ""
        avatarImageManager = nil
        collectionHeightConstraint.constant = 0
    }
    
    func configureCell(
        _ participants: [ChatRoomParticipant],
        currentUserID: String,
        avatarImageManager: AvatarImageManaging
    ) {
        self.participants = participants
        self.currentUserID = currentUserID
        self.avatarImageManager = avatarImageManager
        participantLabel.text = "대화상대 \(participants.count)"
        // 내부 컬렉션이 0 높이이면 셀을 만들 수 없어 실제 contentSize도 0으로 남는다.
        // 먼저 행별 예상 높이를 제공하고, 레이아웃 후 self-sizing 결과로 교정한다.
        collectionHeightConstraint.constant = CGFloat(participants.count * 60)
        
        // 메인 스레드에서 UI 업데이트
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.verticalCollectionView.reloadData()
            self.verticalCollectionView.collectionViewLayout.invalidateLayout()
            self.verticalCollectionView.layoutIfNeeded()
            self.updateCollectionHeightIfNeeded()
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
    }

    private func updateCollectionHeightIfNeeded() {
        let height = ceil(verticalCollectionView.collectionViewLayout.collectionViewContentSize.height)
        guard abs(collectionHeightConstraint.constant - height) > 0.5 else { return }
        collectionHeightConstraint.constant = height
        invalidateIntrinsicContentSize()
    }
}

extension ParticipantsSectionParticipantCell: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        participants.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
//        if indexPath.item < self.userProfiles.count {
//
//        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ParticipantListCell.reuseIdentifier, for: indexPath) as! ParticipantListCell
        let participant = participants[indexPath.item]
        if let avatarImageManager {
            cell.configureCell(
                participant: participant,
                currentUserID: currentUserID,
                avatarImageManager: avatarImageManager
            )
        } else {
            cell.configureCell(userProfile: participant.user)
        }
        cell.configureModeration(isVisible: canModerateParticipant?(participant) == true) { [weak self] in
            self?.onModerateParticipant?(participant)
        }
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < participants.count else { return }
        onSelectParticipant?(participants[indexPath.item])
        collectionView.deselectItem(at: indexPath, animated: true)
    }
}
