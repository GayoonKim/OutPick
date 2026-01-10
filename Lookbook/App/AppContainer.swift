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

        // ✅ provider에서 repo/service 꺼내서 ViewModel 조립
        self.lookbookHomeViewModel = LookbookHomeViewModel(
            repo: provider.brandRepository,
            imageLoader: BrandLogoImageStore(),   // 기존 그대로 쓰거나 provider로 합치기
            initialBrandLimit: 20,
            prefetchLogoCount: 12
        )
    }

    func preloadLookbook() {
        Task { await lookbookHomeViewModel.preloadIfNeeded() }
    }
}
