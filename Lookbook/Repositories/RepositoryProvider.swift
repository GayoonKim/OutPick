//
//  RepositoryProvider.swift
//  OutPick
//
//  Created by 김가윤 on 12/17/25.
//

import Foundation

final class RepositoryProvider {
    static let shared = RepositoryProvider()

//    let brandRepository: BrandRepositoryProtocol
//    let seasonRepository: SeasonRepositoryProtocol
//    let lookbookRepository: LookbookRepositoryProtocol
    let storageService: StorageServiceProtocol

    init(//brandRepository: BrandRepositoryProtocol = FirestoreBrandRepository(),
//         seasonRepository: SeasonRepositoryProtocol = FirestoreSeasonRepository(),
//         lookbookRepository: LookbookRepositoryProtocol = FirestoreLookbookRepository(),
         storageService: StorageServiceProtocol = FirebaseStorageService()) {
//        self.brandRepository = brandRepository
//        self.seasonRepository = seasonRepository
//        self.lookbookRepository = lookbookRepository
        self.storageService = storageService
    }
}
