//
//  AppContainer.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import Foundation

@MainActor
final class AppContainer {
    let provider: RepositoryProvider
    let lookbookHomeViewModel: LookbookHomeViewModel

    init(provider: RepositoryProvider = .shared) {
        self.provider = provider

        self.lookbookHomeViewModel = LookbookHomeViewModel(
            repo: provider.brandRepository,
            imageLoader: provider.brandLogoImageLoader,
            initialBrandLimit: 20,
            prefetchLogoCount: 12
        )
    }

    func preloadLookbook() {
        Task { await lookbookHomeViewModel.preloadIfNeeded() }
    }
}
