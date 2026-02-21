//
//  AppContainer.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import Foundation

@MainActor
final class LookbookContainer {
    let provider: LookbookRepositoryProvider
    let lookbookHomeViewModel: LookbookHomeViewModel

    init(provider: LookbookRepositoryProvider = .shared) {
        self.provider = provider

        self.lookbookHomeViewModel = LookbookHomeViewModel(
            repo: provider.brandRepository,
            brandImageCache: provider.brandImageCache,
            initialBrandLimit: 12,
            prefetchLogoCount: 4
        )
    }

    func preloadLookbook() {
        Task { await lookbookHomeViewModel.loadInitialPageIfNeeded() }
    }
}
