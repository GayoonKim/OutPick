//
//  UICollectionViewDiffableDataSource+ViewModel.swift
//  OutPick
//
//  Created by 김가윤 on 7/12/24.
//

import UIKit

// UICollectionViewDiffableDataSource 확장
extension UICollectionViewDiffableDataSource {
    // Apply a snapshot to the data source with the given section IDs and items by section.
    // If a section has no items and is not in the sectionsRetainedIfEmpty set, it will be removed.
    func applySnapshotUsing(sectionIDs: [SectionIdentifierType], itemsBySection: [SectionIdentifierType: [ItemIdentifierType]], sectionsRetainedIfEmpty: Set<SectionIdentifierType> = Set<SectionIdentifierType>()) {
        applySnapshotUsing(sectionIDs: sectionIDs, itemsBySection: itemsBySection, animatingDifferences: true, sectionsRetainedIfEmpty: sectionsRetainedIfEmpty)
    }

    // Apply a snapshot to the data source with the given section IDs and items by section.
    // If a section has no items and is not in the sectionsRetainedIfEmpty set, it will be removed.
    // If animatingDifferences is true, the changes will be animated.
    func applySnapshotUsing(sectionIDs: [SectionIdentifierType], itemsBySection: [SectionIdentifierType: [ItemIdentifierType]], animatingDifferences: Bool, sectionsRetainedIfEmpty: Set<SectionIdentifierType> = Set<SectionIdentifierType>()) {
        var snapshot = NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>()

        for sectionID in sectionIDs {
            guard let sectionItems = itemsBySection[sectionID],
                sectionItems.count > 0 || sectionsRetainedIfEmpty.contains(sectionID) else { continue }

            snapshot.appendSections([sectionID])
            snapshot.appendItems(sectionItems, toSection: sectionID)
            snapshot.reloadItems(sectionItems)
        }

        self.apply(snapshot, animatingDifferences: animatingDifferences)
    }
}