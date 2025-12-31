//
//  AppContainer.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import Foundation

@MainActor
final class AppContainer {
    let imageLoader: any ImageLoading
    let brandRepository: BrandRepositoryProtocol
    let lookbookHomeViewModel: LookbookHomeViewModel

    init() {
        self.imageLoader = BrandLogoImageStore()
        self.brandRepository = FirestoreBrandRepository()
        self.lookbookHomeViewModel = LookbookHomeViewModel(
            repo: brandRepository,
            imageLoader: imageLoader,
            initialBrandLimit: 20,
            prefetchLogoCount: 12
        )
    }

    func preloadLookbook() {
        Task { await lookbookHomeViewModel.preloadIfNeeded() }
    }
}
